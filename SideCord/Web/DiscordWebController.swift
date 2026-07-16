import AppKit
import Combine
import Foundation
import OSLog
import UniformTypeIdentifiers
import WebKit

struct DiscordWebError: Error, Equatable, Identifiable, LocalizedError {
    enum Kind: Equatable {
        case navigation
        case webContentProcess
    }

    let kind: Kind
    let message: String

    var id: String { "\(kind)-\(message)" }
    var errorDescription: String? { message }

    var title: String {
        switch kind {
        case .navigation:
            "Discord couldn’t load"
        case .webContentProcess:
            "Discord stopped unexpectedly"
        }
    }

    var canRetryByReloading: Bool { true }
}

struct DiscordIntegrationHealth: Equatable, Sendable {
    var runtimeReady = false
    var guildRailDetected = false
    var channelListDetected = false
    var composerDetected = false
    var incomingCallDetected = false
    var incomingCallControlsDetected = false
    var settingsShellDetected = false
    var settingsCategoryInjected = false

    var summary: String {
        guard runtimeReady else { return "Waiting for Discord" }
        let core = [guildRailDetected, channelListDetected, composerDetected]
        return core.allSatisfy { $0 } ? "Discord integration ready" : "Some selectors need attention"
    }
}

enum DiscordSessionState: String, Equatable, Sendable {
    case loading
    case signedOut
    case authenticated
}

@MainActor
enum DiscordWebConfiguration {
    static let safariUserAgentSuffix = "Version/26.0 Safari/605.1.15"

    static func make() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        applySafariCompatibility(to: configuration)
        return configuration
    }

    static func applySafariCompatibility(to configuration: WKWebViewConfiguration) {
        configuration.applicationNameForUserAgent = safariUserAgentSuffix
    }
}

struct DiscordRuntimeActionQueue: Equatable {
    private(set) var isReady = false
    private(set) var pending: [String] = []
    private(set) var inFlight: String?

    mutating func enqueue(_ action: String) {
        pending.append(action)
    }

    mutating func markLoading() {
        isReady = false
        inFlight = nil
    }

    mutating func markReady() {
        isReady = true
    }

    mutating func beginNext() -> String? {
        guard isReady, inFlight == nil, let action = pending.first else { return nil }
        inFlight = action
        return action
    }

    mutating func complete(_ action: String, succeeded: Bool) {
        guard inFlight == action else { return }
        inFlight = nil
        if succeeded {
            if pending.first == action { pending.removeFirst() }
        } else {
            isReady = false
        }
    }
}

@MainActor
final class DiscordWebController: NSObject, ObservableObject {
    private static let attentionLogger = Logger(
        subsystem: "com.sidecord.app",
        category: "NotificationGlow"
    )

    static let discordAppURL = URL(string: "https://discord.com/app")!
    private static let runtimeMessageHandlerName = DiscordCSSComposer.messageHandlerName

    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var currentURL: URL?
    @Published private(set) var error: DiscordWebError?
    @Published private(set) var downloadError: String?
    @Published private(set) var isNavigationDrawerOpen = false
    @Published private(set) var integrationHealth = DiscordIntegrationHealth()
    @Published private(set) var sessionState: DiscordSessionState = .loading

    let webView: WKWebView
    lazy private(set) var railModel = DiscordRailModel(controller: self)
    let attentionModel = DiscordAttentionModel()

    private let settings: AppSettings
    private let pluginManager: SideCordPluginManager
    private let pluginRuntime: PluginWebPanelRuntime
    private let compactPresetCSS: String
    private let layoutModifiersCSS: String
    private let visualThemesCSS: String
    private var settingsCancellables = Set<AnyCancellable>()
    private var attemptedProcessRecovery = false
    private struct PendingDownload {
        let temporaryURL: URL
        let destinationURL: URL
        let securityScopedURL: URL?
    }

    private var pendingDownloads: [ObjectIdentifier: PendingDownload] = [:]
    private var pendingUserInitiatedMainFrameNavigation = false
    private var runtimeActions = DiscordRuntimeActionQueue()
    private var runtimeDocumentGeneration = 0
    private var expectedDrawerState: Bool?
    private var drawerExpectationGeneration = 0
    private var authenticationPopups: [ObjectIdentifier: AuthenticationPopupController] = [:]
    private var approvedProgrammaticNavigationURLs = Set<String>()
    private var isRuntimeMessageHandlerInstalled = false
    private var settingsOpenGeneration: UInt64 = 0

    init(
        settings: AppSettings,
        pluginManager: SideCordPluginManager,
        pluginRuntime: PluginWebPanelRuntime,
        resourceBundle: Bundle = .main
    ) {
        self.settings = settings
        self.pluginManager = pluginManager
        self.pluginRuntime = pluginRuntime
        compactPresetCSS = Self.loadBundledCSS(named: "compact", from: resourceBundle)
        layoutModifiersCSS = Self.loadBundledCSS(named: "layout-mods", from: resourceBundle)
        visualThemesCSS = Self.loadBundledCSS(named: "visual-themes", from: resourceBundle)

        let configuration = DiscordWebConfiguration.make()
        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()
        _ = try? DownloadFileInstaller.removeStaleTemporaryFiles()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.configuration.userContentController.add(
            self,
            name: Self.runtimeMessageHandlerName
        )
        isRuntimeMessageHandlerInstalled = true
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = true

        refreshCSS(injectIntoCurrentPage: false)
        observeSettings()
        loadDiscord()
    }

    func loadDiscord() {
        error = nil
        isLoading = true
        webView.load(URLRequest(url: Self.discordAppURL))
        synchronizeNavigationState()
    }

    func reload() {
        error = nil
        if webView.url == nil {
            loadDiscord()
        } else {
            webView.reload()
        }
    }

    func goBack() {
        guard webView.canGoBack else { return }
        webView.goBack()
    }

    func goForward() {
        guard webView.canGoForward else { return }
        webView.goForward()
    }

    func dismissError() {
        error = nil
    }

    func dismissDownloadError() {
        downloadError = nil
    }

    func toggleNavigationDrawer() {
        setOptimisticDrawerState(!isNavigationDrawerOpen)
        performRuntimeAction("toggleDrawer")
    }

    func openNavigationDrawer() {
        setOptimisticDrawerState(true)
        performRuntimeAction("openDrawer")
    }

    func closeNavigationDrawer() {
        setOptimisticDrawerState(false)
        performRuntimeAction("closeDrawer")
    }

    func openSideCordSettings() {
        settingsOpenGeneration &+= 1
        let requestGeneration = settingsOpenGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            var didStartOpening = false
            for attempt in 0..<80 {
                guard self.settingsOpenGeneration == requestGeneration else { return }
                if attempt == 0 || attempt.isMultiple(of: 20) {
                    // Also installs the bridge into an already-loaded document
                    // and survives Discord's startup redirects between documents.
                    self.refreshCSS()
                }
                let result = try? await self.webView.evaluateJavaScript(
                    DiscordCSSComposer.openSideCordSettingsSource()
                )
                if (result as? Bool) == true {
                    didStartOpening = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard didStartOpening else {
                return
            }

            // Discord mounts settings through a lazy SPA layer. Give its DOM
            // observer time to populate that layer, then reinject if needed.
            try? await Task.sleep(for: .seconds(6.5))
            guard self.settingsOpenGeneration == requestGeneration else { return }
            if !self.integrationHealth.settingsCategoryInjected {
                self.refreshCSS()
                _ = try? await self.webView.evaluateJavaScript(
                    DiscordCSSComposer.openSideCordSettingsSource()
                )
            }
        }
    }

    func performIncomingCallAction(
        _ action: IncomingCallAction,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard let url = webView.url, DiscordURLPolicy.isDiscordURL(url) else {
            completion(false)
            return
        }
        let generation = runtimeDocumentGeneration
        webView.evaluateJavaScript(
            DiscordCSSComposer.incomingCallActionSource(action.rawValue)
        ) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.runtimeDocumentGeneration == generation else {
                    completion(false)
                    return
                }
                completion(error == nil && (result as? Bool) == true)
            }
        }
    }

    func shutdown() {
        discardAllPendingDownloads()
        guard isRuntimeMessageHandlerInstalled else { return }
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.runtimeMessageHandlerName
        )
        isRuntimeMessageHandlerInstalled = false
        railModel.reset()
        attentionModel.reset()
    }

    /// Rebuilds the document-end user script and applies it to the currently
    /// loaded Discord document. Settings changes call this automatically.
    func refreshCSS() {
        refreshCSS(injectIntoCurrentPage: true)
    }

    private func observeSettings() {
        let immediateChanges: [AnyPublisher<Void, Never>] = [
            settings.$cssPreset.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$discordLayoutMode.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$customDiscordLayoutOptions.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$visualTheme.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$themeAccent.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$themeIntensity.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$themeColorScheme.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$notificationGlowEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$customCSSEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(immediateChanges)
            .debounce(for: .milliseconds(40), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshCSS()
            }
            .store(in: &settingsCancellables)

        settings.$customCSS
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .filter { [weak self] _ in self?.settings.customCSSEnabled == true }
            .sink { [weak self] _ in self?.refreshCSS() }
            .store(in: &settingsCancellables)

        Publishers.Merge(
            pluginManager.$installed.dropFirst().map { _ in () },
            pluginManager.$enabledIdentifiers.dropFirst().map { _ in () }
        )
        .debounce(for: .milliseconds(40), scheduler: RunLoop.main)
        .sink { [weak self] _ in self?.refreshCSS() }
        .store(in: &settingsCancellables)

        pluginRuntime.$preferenceRevision
            .dropFirst()
            .debounce(for: .milliseconds(40), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshCSS() }
            .store(in: &settingsCancellables)

        settings.objectWillChange
            .debounce(for: .milliseconds(90), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshCSS() }
            .store(in: &settingsCancellables)
    }

    private func refreshCSS(injectIntoCurrentPage: Bool) {
        refreshCSS(
            preset: settings.cssPreset,
            layoutOptions: settings.discordLayoutOptions,
            visualTheme: settings.visualTheme,
            themeAccent: settings.themeAccent,
            themeIntensity: settings.themeIntensity,
            themeColorScheme: settings.themeColorScheme,
            notificationGlowEnabled: settings.notificationGlowEnabled,
            customCSS: settings.customCSS,
            customCSSEnabled: settings.customCSSEnabled,
            injectIntoCurrentPage: injectIntoCurrentPage
        )
    }

    private func refreshCSS(
        preset: CSSPreset,
        layoutOptions: DiscordLayoutOptions,
        visualTheme: DiscordVisualTheme,
        themeAccent: SideCordAccent,
        themeIntensity: Double,
        themeColorScheme: ThemeColorScheme,
        notificationGlowEnabled: Bool,
        customCSS: String,
        customCSSEnabled: Bool,
        injectIntoCurrentPage: Bool
    ) {
        updateWebViewAppearance(
            visualTheme: visualTheme,
            themeIntensity: themeIntensity,
            colorScheme: themeColorScheme
        )

        let css = DiscordCSSComposer.compose(
            preset: preset,
            compactPresetCSS: compactPresetCSS,
            layoutModifiersCSS: layoutModifiersCSS,
            visualThemesCSS: visualThemesCSS,
            layoutOptions: layoutOptions,
            pluginCSS: pluginManager.combinedStyleSheet,
            customCSS: customCSS,
            customCSSEnabled: customCSSEnabled
        )
        let configuration = DiscordCSSComposer.runtimeConfiguration(
            layoutOptions: layoutOptions,
            visualTheme: visualTheme,
            themeAccent: themeAccent,
            themeIntensity: themeIntensity,
            themeColorScheme: themeColorScheme
        )
        let source = DiscordCSSComposer.userScriptSource(
            css: css,
            configuration: configuration
        )
        let notificationBridgeSource = DiscordCSSComposer
            .notificationBridgeUserScriptSource(isEnabled: notificationGlowEnabled)
        let settingsBridgeSource = DiscordCSSComposer.settingsBridgeUserScriptSource(
            snapshot: settingsSnapshot()
        )
        let contentController = webView.configuration.userContentController
        contentController.removeAllUserScripts()
        contentController.addUserScript(
            WKUserScript(
                source: notificationBridgeSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        contentController.addUserScript(
            WKUserScript(
                source: settingsBridgeSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        contentController.addUserScript(
            WKUserScript(
                source: source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        guard injectIntoCurrentPage,
              let url = webView.url,
              DiscordURLPolicy.isDiscordURL(url)
        else {
            return
        }

        let generation = runtimeDocumentGeneration
        let liveSource = notificationBridgeSource + "\n" + source + "\n" + settingsBridgeSource
        webView.evaluateJavaScript(liveSource) { [weak self] _, error in
            // A navigation may replace the document while this is executing.
            // The registered WKUserScript will apply the same CSS to the new one.
            Task { @MainActor in
                guard let self, self.runtimeDocumentGeneration == generation else { return }
                if error == nil {
                    self.runtimeActions.markReady()
                    self.drainRuntimeActions()
                } else {
                    self.runtimeActions.markLoading()
                }
            }
        }
    }

    private func settingsSnapshot() -> SideCordSettingsSnapshot {
        SideCordSettingsSnapshot(
            sidebarEdge: settings.sidebarEdge.rawValue,
            edgeHoverEnabled: settings.edgeHoverEnabled,
            sidebarWidth: Double(settings.sidebarWidth),
            sidebarInset: Double(settings.sidebarInset),
            discordLayoutMode: settings.discordLayoutMode.rawValue,
            floatingRailEnabled: settings.floatingRailEnabled,
            visualTheme: settings.visualTheme.rawValue,
            themeAccent: settings.themeAccent.rawValue,
            themeIntensity: settings.themeIntensity,
            themeColorScheme: settings.themeColorScheme.rawValue,
            notificationGlowEnabled: settings.notificationGlowEnabled,
            attentionGlowColor: settings.attentionGlowColor.rawValue,
            attentionGlowStrength: settings.attentionGlowStrength.rawValue,
            incomingCallCardEnabled: settings.incomingCallCardEnabled,
            pluginsInstalled: pluginManager.installed.count,
            pluginsEnabled: pluginManager.enabledIdentifiers.count,
            plugins: pluginManager.installed.map { plugin in
                let webPanel = plugin.manifest.contributions.webPanels.first.map { panel in
                    let heightBounds = PluginWebPanelLayout.heightBounds(
                        manifestMinimum: panel.minimumHeight,
                        manifestMaximum: panel.maximumHeight
                    )
                    return SideCordWebPanelSettingsSnapshot(
                        identifier: panel.id,
                        name: panel.name,
                        allowedHosts: panel.allowedNavigationHosts,
                        persistentWebsiteData: plugin.manifest.permissions.persistentWebsiteData,
                        backgroundAudioRequested: plugin.manifest.permissions.backgroundAudio,
                        backgroundAudioAllowed: pluginRuntime.isBackgroundAudioAllowed(
                            pluginIdentifier: plugin.id,
                            contributionIdentifier: panel.id
                        ),
                        visible: pluginRuntime.isVisible(
                            pluginIdentifier: plugin.id,
                            contributionIdentifier: panel.id
                        ),
                        height: pluginRuntime.requestedHeight(
                            pluginIdentifier: plugin.id,
                            panel: panel
                        ),
                        minimumHeight: heightBounds.lowerBound,
                        maximumHeight: heightBounds.upperBound,
                        userResizable: panel.userResizable ?? false
                    )
                }
                return SideCordPluginSettingsSnapshot(
                    identifier: plugin.id,
                    name: plugin.manifest.name,
                    version: plugin.manifest.version,
                    enabled: pluginManager.isEnabled(plugin),
                    webPanel: webPanel
                )
            }
        )
    }

    private func handleSettingsAction(_ payload: [String: Any]) {
        guard let action = payload["action"] as? String, action.count <= 64 else { return }
        switch action {
        case "resetTheme":
            settings.resetAppearanceSettings()
            refreshCSS()
        case "resetLayout":
            settings.resetDiscordLayoutSettings()
            refreshCSS()
        case "resetAll":
            settings.resetToDefaults()
            refreshCSS()
        case "installPlugin":
            choosePluginForInstallation()
        case "setPluginEnabled":
            guard let identifier = payload["identifier"] as? String,
                  identifier.count <= 128,
                  let value = payload["value"] as? NSNumber,
                  CFGetTypeID(value) == CFBooleanGetTypeID()
            else { return }
            if value.boolValue {
                pluginRuntime.approveRequestedPermissions(identifier: identifier)
            }
            pluginManager.setEnabled(value.boolValue, identifier: identifier)
            refreshCSS()
        case "setPluginPanelVisible":
            guard let (identifier, panelIdentifier, value) = webPanelBooleanAction(payload)
            else { return }
            pluginRuntime.setVisible(
                value,
                pluginIdentifier: identifier,
                contributionIdentifier: panelIdentifier
            )
        case "setPluginPanelBackgroundAudio":
            guard let (identifier, panelIdentifier, value) = webPanelBooleanAction(payload)
            else { return }
            pluginRuntime.setBackgroundAudioAllowed(
                value,
                pluginIdentifier: identifier,
                contributionIdentifier: panelIdentifier
            )
        case "setPluginPanelHeight":
            guard let identifier = payload["identifier"] as? String,
                  let panelIdentifier = payload["panelIdentifier"] as? String,
                  let value = payload["value"] as? NSNumber,
                  value.doubleValue.isFinite,
                  let panel = pluginManager.installed.first(where: { $0.id == identifier })?
                    .manifest.contributions.webPanels.first(where: { $0.id == panelIdentifier })
            else { return }
            pluginRuntime.setRequestedHeight(
                value.doubleValue,
                pluginIdentifier: identifier,
                panel: panel
            )
        case "reloadPluginPanel":
            guard let (identifier, panelIdentifier) = webPanelIdentifiers(payload) else { return }
            pluginRuntime.reload(
                pluginIdentifier: identifier,
                contributionIdentifier: panelIdentifier
            )
        case "openPluginPanel":
            guard let (identifier, panelIdentifier) = webPanelIdentifiers(payload) else { return }
            pluginRuntime.openInBrowser(
                pluginIdentifier: identifier,
                contributionIdentifier: panelIdentifier
            )
        case "clearPluginPanelData":
            guard let (identifier, panelIdentifier) = webPanelIdentifiers(payload) else { return }
            Task { [weak self] in
                await self?.pluginRuntime.clearWebsiteData(
                    pluginIdentifier: identifier,
                    contributionIdentifier: panelIdentifier
                )
            }
        case "removePlugin":
            guard let identifier = payload["identifier"] as? String,
                  identifier.count <= 128
            else { return }
            do {
                pluginRuntime.prepareForUninstall(identifier: identifier)
                try pluginManager.uninstall(identifier: identifier)
                downloadError = nil
                refreshCSS()
            } catch {
                downloadError = "Couldn’t remove plugin: \(error.localizedDescription)"
            }
        case "removePluginAndData":
            guard let (identifier, panelIdentifier) = webPanelIdentifiers(payload) else { return }
            pluginRuntime.prepareForUninstall(identifier: identifier)
            do {
                try pluginManager.uninstall(identifier: identifier)
                downloadError = nil
                refreshCSS()
                Task { [weak self] in
                    do {
                        try await self?.pluginRuntime.removeWebsiteData(
                            pluginIdentifier: identifier,
                            contributionIdentifier: panelIdentifier
                        )
                    } catch {
                        self?.downloadError = "The plugin was removed, but its website data couldn’t be deleted: \(error.localizedDescription)"
                    }
                }
            } catch {
                downloadError = "Couldn’t remove plugin: \(error.localizedDescription)"
            }
        default:
            return
        }
    }

    private func webPanelIdentifiers(_ payload: [String: Any]) -> (String, String)? {
        guard let identifier = payload["identifier"] as? String,
              identifier.count <= 128,
              let panelIdentifier = payload["panelIdentifier"] as? String,
              panelIdentifier.count <= 80
        else { return nil }
        return (identifier, panelIdentifier)
    }

    private func webPanelBooleanAction(
        _ payload: [String: Any]
    ) -> (String, String, Bool)? {
        guard let (identifier, panelIdentifier) = webPanelIdentifiers(payload),
              let value = payload["value"] as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID()
        else { return nil }
        return (identifier, panelIdentifier, value.boolValue)
    }

    private func choosePluginForInstallation() {
        let panel = NSOpenPanel()
        panel.title = "Import a SideCord plugin"
        panel.message = "Choose a declarative SideCord JSON plugin package."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                _ = try self.pluginManager.install(data: Data(contentsOf: url), source: .local)
                self.downloadError = nil
                self.refreshCSS()
            } catch {
                self.downloadError = "Couldn’t install plugin: \(error.localizedDescription)"
            }
        }
    }

    private func updateWebViewAppearance(
        visualTheme: DiscordVisualTheme,
        themeIntensity: Double,
        colorScheme: ThemeColorScheme
    ) {
        switch colorScheme {
        case .system:
            webView.appearance = nil
        case .light:
            webView.appearance = NSAppearance(named: .aqua)
        case .dark:
            webView.appearance = NSAppearance(named: .darkAqua)
        }

        let isDark: Bool
        switch colorScheme {
        case .dark:
            isDark = true
        case .light:
            isDark = false
        case .system:
            isDark = webView.effectiveAppearance.bestMatch(
                from: [.darkAqua, .aqua]
            ) == .darkAqua
        }

        func color(_ red: Int, _ green: Int, _ blue: Int) -> NSColor {
            NSColor(
                srgbRed: CGFloat(red) / 255,
                green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255,
                alpha: 1
            )
        }

        let discordBaseline = isDark ? color(49, 51, 56) : color(255, 255, 255)
        let themeBackground: NSColor
        switch (visualTheme, isDark) {
        case (.systemGlass, true):
            themeBackground = color(20, 23, 30)
        case (.systemGlass, false):
            themeBackground = color(247, 248, 252)
        case (.oled, true):
            themeBackground = .black
        case (.oled, false):
            themeBackground = .white
        case (.soft, true):
            themeBackground = color(41, 38, 49)
        case (.soft, false):
            themeBackground = color(255, 249, 251)
        case (.discord, _):
            themeBackground = discordBaseline
        }

        let intensity = min(max(themeIntensity.isFinite ? themeIntensity : 1, 0), 1)
        webView.underPageBackgroundColor = discordBaseline.blended(
            withFraction: intensity,
            of: themeBackground
        ) ?? themeBackground
    }

    private func performRuntimeAction(_ action: String) {
        runtimeActions.enqueue(action)
        drainRuntimeActions()
    }

    func activateRailItem(id: String) {
        guard railModel.items.contains(where: { $0.id == id }),
              let url = webView.url,
              DiscordURLPolicy.isDiscordURL(url)
        else { return }

        let generation = runtimeDocumentGeneration
        webView.evaluateJavaScript(
            DiscordCSSComposer.railActivationSource(id: id)
        ) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.runtimeDocumentGeneration == generation else { return }
                guard error == nil, (result as? Bool) == true else {
                    self.refreshCSS()
                    return
                }
            }
        }
    }

    private func setOptimisticDrawerState(_ isOpen: Bool) {
        guard settings.discordLayoutOptions.navigationPresentation != .docked else { return }
        drawerExpectationGeneration += 1
        let generation = drawerExpectationGeneration
        expectedDrawerState = isOpen
        isNavigationDrawerOpen = isOpen

        guard isOpen else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self,
                  self.drawerExpectationGeneration == generation,
                  self.expectedDrawerState == true
            else { return }
            self.expectedDrawerState = nil
            self.isNavigationDrawerOpen = false
        }
    }

    private func drainRuntimeActions() {
        guard let url = webView.url,
              DiscordURLPolicy.isDiscordURL(url),
              let action = runtimeActions.beginNext()
        else { return }
        let generation = runtimeDocumentGeneration
        webView.evaluateJavaScript(
            DiscordCSSComposer.runtimeActionSource(action)
        ) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.runtimeDocumentGeneration == generation else { return }
                let succeeded = error == nil && (result as? Bool) == true
                self.runtimeActions.complete(action, succeeded: succeeded)
                if succeeded {
                    self.drainRuntimeActions()
                } else {
                    // The page may have replaced its JavaScript world without a
                    // navigation callback. Reinstall the runtime, then replay.
                    self.refreshCSS()
                }
            }
        }
    }

    private func synchronizeNavigationState() {
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        currentURL = webView.url
        updateSessionState(for: webView.url)
    }

    private func updateSessionState(for url: URL?) {
        guard let url, DiscordURLPolicy.isDiscordURL(url) else {
            sessionState = .loading
            return
        }
        let path = url.path.lowercased()
        if path == "/login" || path.hasPrefix("/register") {
            sessionState = .signedOut
        } else if integrationHealth.guildRailDetected || integrationHealth.channelListDetected {
            sessionState = .authenticated
        } else {
            sessionState = .loading
        }
    }

    private func recordNavigationFailure(_ failure: Error) {
        let nsError = failure as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled {
            synchronizeNavigationState()
            return
        }

        error = DiscordWebError(kind: .navigation, message: failure.localizedDescription)
        synchronizeNavigationState()
    }

    private func handleTopLevelURL(_ url: URL?, userInitiated: Bool) {
        switch DiscordURLPolicy.decision(for: url) {
        case .allow:
            guard userInitiated, let url else { return }
            webView.load(URLRequest(url: url))
        case .openExternally:
            guard userInitiated, let url else { return }
            NSWorkspace.shared.open(url)
        case .cancel:
            break
        }
    }

    private func authenticationPopupDidClose(id: ObjectIdentifier) {
        authenticationPopups.removeValue(forKey: id)
        if webView.url?.path == "/login" || webView.url?.path == "/app" {
            reload()
        }
    }

    private static func loadBundledCSS(named name: String, from bundle: Bundle) -> String {
        guard let url = bundle.url(forResource: name, withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8)
        else {
            return ""
        }
        return css
    }
}

extension DiscordWebController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.runtimeMessageHandlerName,
              message.webView === webView,
              message.frameInfo.isMainFrame,
              let sourceURL = message.frameInfo.request.url ?? webView.url,
              DiscordURLPolicy.isDiscordURL(sourceURL),
              let payload = message.body as? [String: Any],
              let type = payload["type"] as? String
        else { return }

        if type == "rail", let items = payload["items"] {
            railModel.receive(messageItems: items)
            attentionModel.receiveRailItems(railModel.items)
            return
        }

        if type == "incomingCall",
           let number = payload["active"] as? NSNumber,
           CFGetTypeID(number) == CFBooleanGetTypeID() {
            let active = number.boolValue
            if active {
                let identifier = payload["callID"] as? String
                    ?? IncomingCallDescriptor.generic.id
                let displayName = payload["displayName"] as? String
                    ?? IncomingCallDescriptor.generic.displayName
                attentionModel.setIncomingCall(
                    IncomingCallDescriptor(id: identifier, displayName: displayName)
                )
            } else {
                attentionModel.setIncomingCall(nil)
            }
            return
        }

        if type == "notification" {
            Self.attentionLogger.info(
                "Received a content-free Discord notification signal"
            )
            attentionModel.receiveNotification()
            return
        }

        if type == "health" {
            let previousHealth = integrationHealth
            integrationHealth = DiscordIntegrationHealth(
                runtimeReady: payload["runtime"] as? Bool ?? false,
                guildRailDetected: payload["guildRail"] as? Bool ?? false,
                channelListDetected: payload["channelList"] as? Bool ?? false,
                composerDetected: payload["composer"] as? Bool ?? false,
                incomingCallDetected: payload["incomingCall"] as? Bool ?? false,
                incomingCallControlsDetected: payload["callControls"] as? Bool ?? false,
                settingsShellDetected: previousHealth.settingsShellDetected,
                settingsCategoryInjected: previousHealth.settingsCategoryInjected
            )
            updateSessionState(for: webView.url)
            return
        }

        if type == "settingsHealth" {
            integrationHealth.settingsShellDetected = payload["shellDetected"] as? Bool ?? false
            integrationHealth.settingsCategoryInjected = payload["categoryInjected"] as? Bool ?? false
            return
        }

        if type == "settingsSet",
           let key = payload["key"] as? String,
           key.count <= 64,
           let value = payload["value"] {
            if SideCordSettingsMutation.apply(key: key, value: value, to: settings) {
                refreshCSS()
            }
            return
        }

        if type == "settingsAction" {
            handleSettingsAction(payload)
            return
        }

        guard type == "drawer", let isOpen = payload["open"] as? Bool else { return }
        if let expectedDrawerState, expectedDrawerState != isOpen { return }
        drawerExpectationGeneration += 1
        expectedDrawerState = nil
        isNavigationDrawerOpen = isOpen
    }
}

enum IncomingCallAction: String, Sendable {
    case answer
    case decline
}

extension DiscordWebController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        // Subframe resources and embeds are Discord's responsibility. SideCord's
        // allow-list applies to visible, top-level browsing only.
        if navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
            return
        }

        // A nil target frame represents a popup. WKUIDelegate routes that request
        // into this persistent view or out to the default browser.
        if navigationAction.targetFrame == nil {
            decisionHandler(.allow)
            return
        }

        switch DiscordURLPolicy.decision(for: navigationAction.request.url) {
        case .allow:
            let approvedURL = navigationAction.request.url?.absoluteString
            let wasExplicitlyApproved = approvedURL.map {
                approvedProgrammaticNavigationURLs.remove($0) != nil
            } ?? false
            let isUserInitiated = navigationAction.navigationType == .linkActivated
                || wasExplicitlyApproved
            pendingUserInitiatedMainFrameNavigation = isUserInitiated
            if navigationAction.shouldPerformDownload {
                decisionHandler(isUserInitiated ? .download : .cancel)
            } else {
                decisionHandler(.allow)
            }
        case .openExternally:
            pendingUserInitiatedMainFrameNavigation = false
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        case .cancel:
            pendingUserInitiatedMainFrameNavigation = false
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        let userInitiated = pendingUserInitiatedMainFrameNavigation
        if navigationResponse.isForMainFrame {
            pendingUserInitiatedMainFrameNavigation = false
        }
        switch DiscordDownloadPolicy.decision(
            isForMainFrame: navigationResponse.isForMainFrame,
            canShowMIMEType: navigationResponse.canShowMIMEType,
            userInitiated: userInitiated
        ) {
        case .allow:
            decisionHandler(.allow)
        case .download:
            decisionHandler(.download)
        case .cancel:
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        download.delegate = self
        pendingUserInitiatedMainFrameNavigation = false
        synchronizeNavigationState()
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.delegate = self
        pendingUserInitiatedMainFrameNavigation = false
        synchronizeNavigationState()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        drawerExpectationGeneration += 1
        expectedDrawerState = nil
        isNavigationDrawerOpen = false
        runtimeDocumentGeneration += 1
        runtimeActions.markLoading()
        railModel.reset()
        attentionModel.reset()
        integrationHealth = DiscordIntegrationHealth()
        sessionState = .loading
        error = nil
        isLoading = true
        synchronizeNavigationState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        synchronizeNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pendingUserInitiatedMainFrameNavigation = false
        attemptedProcessRecovery = false
        error = nil
        synchronizeNavigationState()
        refreshCSS()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        pendingUserInitiatedMainFrameNavigation = false
        recordNavigationFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        pendingUserInitiatedMainFrameNavigation = false
        recordNavigationFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        runtimeDocumentGeneration += 1
        runtimeActions.markLoading()
        railModel.reset()
        attentionModel.reset()
        integrationHealth = DiscordIntegrationHealth()
        sessionState = .loading
        error = DiscordWebError(
            kind: .webContentProcess,
            message: "Discord's web content stopped unexpectedly."
        )

        guard !attemptedProcessRecovery else {
            synchronizeNavigationState()
            return
        }

        attemptedProcessRecovery = true
        if webView.url == nil {
            loadDiscord()
        } else {
            webView.reload()
        }
    }
}

extension DiscordWebController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let origin = frame.securityOrigin
        guard DiscordJavaScriptDialogPolicy.allowsConfirmation(
            scheme: origin.protocol,
            host: origin.host,
            isMainFrame: frame.isMainFrame
        ) else {
            completionHandler(false)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Confirm SideCord action"
        alert.informativeText = String(message.prefix(800))
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)

        let complete: (NSApplication.ModalResponse) -> Void = { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
        if let hostWindow = webView.window {
            alert.beginSheetModal(for: hostWindow, completionHandler: complete)
        } else {
            complete(alert.runModal())
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else {
            return nil
        }

        let url = navigationAction.request.url
        guard AuthenticationPopupPolicy.shouldOpenInApp(url) else {
            if navigationAction.navigationType == .linkActivated,
               let url,
               DiscordURLPolicy.isDiscordURL(url) {
                approvedProgrammaticNavigationURLs.insert(url.absoluteString)
                self.webView.load(navigationAction.request)
                return nil
            }
            handleTopLevelURL(
                url,
                userInitiated: navigationAction.navigationType == .linkActivated
            )
            return nil
        }

        let popup = AuthenticationPopupController(configuration: configuration)
        let id = ObjectIdentifier(popup.webView)
        popup.onClose = { [weak self] in
            self?.authenticationPopupDidClose(id: id)
        }
        authenticationPopups[id] = popup
        popup.show()
        return popup.webView
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = "Choose an attachment for Discord"
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canCreateDirectories = false

        NSApp.activate(ignoringOtherApps: true)
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
        if let hostWindow = webView.window {
            panel.beginSheetModal(for: hostWindow, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        let isAllowedOrigin = origin.protocol.lowercased() == "https"
            && DiscordURLPolicy.isDiscordHost(origin.host)
        decisionHandler(isAllowedOrigin ? .prompt : .deny)
    }
}

extension DiscordWebController: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = "Save Discord Download"
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            guard result == .OK, let destination = panel.url else {
                completionHandler(nil)
                return
            }

            do {
                let temporaryURL = try DownloadFileInstaller.makeTemporaryURL(
                    for: destination
                )
                let securityScopedURL = destination.startAccessingSecurityScopedResource()
                    ? destination
                    : nil
                self?.pendingDownloads[ObjectIdentifier(download)] = PendingDownload(
                    temporaryURL: temporaryURL,
                    destinationURL: destination,
                    securityScopedURL: securityScopedURL
                )
                completionHandler(temporaryURL)
            } catch {
                self?.downloadError = error.localizedDescription
                completionHandler(nil)
            }
        }
        if let hostWindow = webView.window {
            panel.beginSheetModal(for: hostWindow, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let pending = pendingDownloads.removeValue(
            forKey: ObjectIdentifier(download)
        ) else { return }

        defer { pending.securityScopedURL?.stopAccessingSecurityScopedResource() }
        do {
            try DownloadFileInstaller.install(
                temporaryURL: pending.temporaryURL,
                at: pending.destinationURL
            )
        } catch {
            downloadError = error.localizedDescription
            try? FileManager.default.removeItem(at: pending.temporaryURL)
        }
    }

    func download(
        _ download: WKDownload,
        didFailWithError error: Error,
        resumeData: Data?
    ) {
        discardPendingDownload(for: download)
        downloadError = error.localizedDescription
    }

    private func discardPendingDownload(for download: WKDownload) {
        guard let pending = pendingDownloads.removeValue(
            forKey: ObjectIdentifier(download)
        ) else { return }
        try? FileManager.default.removeItem(at: pending.temporaryURL)
        pending.securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    private func discardAllPendingDownloads() {
        for pending in pendingDownloads.values {
            try? FileManager.default.removeItem(at: pending.temporaryURL)
            pending.securityScopedURL?.stopAccessingSecurityScopedResource()
        }
        pendingDownloads.removeAll()
    }
}

enum DownloadFileInstaller {
    static func makeTemporaryURL(
        for destinationURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let temporaryDirectory = temporaryDirectory(fileManager: fileManager)
        try fileManager.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )

        let pathExtension = destinationURL.pathExtension.isEmpty
            ? "download"
            : destinationURL.pathExtension
        return temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension)
    }

    @discardableResult
    static func removeStaleTemporaryFiles(
        olderThan maximumAge: TimeInterval = 24 * 60 * 60,
        now: Date = Date(),
        in directory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> Int {
        let directory = directory ?? temporaryDirectory(fileManager: fileManager)
        guard fileManager.fileExists(atPath: directory.path) else { return 0 }

        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        var removalCount = 0
        for file in files {
            let values = try file.resourceValues(forKeys: [.contentModificationDateKey])
            let modificationDate = values.contentModificationDate ?? .distantPast
            guard now.timeIntervalSince(modificationDate) >= max(0, maximumAge) else {
                continue
            }
            try fileManager.removeItem(at: file)
            removalCount += 1
        }
        return removalCount
    }

    static func install(
        temporaryURL: URL,
        at destinationURL: URL,
        fileManager: FileManager = .default
    ) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: temporaryURL
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    private static func temporaryDirectory(fileManager: FileManager) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("SideCordDownloads", isDirectory: true)
    }
}
