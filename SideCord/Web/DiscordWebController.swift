import AppKit
import Combine
import Foundation
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
    static let discordAppURL = URL(string: "https://discord.com/app")!
    private static let runtimeMessageHandlerName = DiscordCSSComposer.messageHandlerName

    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var currentURL: URL?
    @Published private(set) var error: DiscordWebError?
    @Published private(set) var downloadError: String?
    @Published private(set) var isNavigationDrawerOpen = false

    let webView: WKWebView
    lazy private(set) var railModel = DiscordRailModel(controller: self)
    let attentionModel = DiscordAttentionModel()

    private let settings: AppSettings
    private let compactPresetCSS: String
    private let layoutModifiersCSS: String
    private let visualThemesCSS: String
    private var settingsCancellables = Set<AnyCancellable>()
    private var attemptedProcessRecovery = false
    private var downloadSecurityScopedURLs: [ObjectIdentifier: URL] = [:]
    private var pendingUserInitiatedMainFrameNavigation = false
    private var runtimeActions = DiscordRuntimeActionQueue()
    private var runtimeDocumentGeneration = 0
    private var expectedDrawerState: Bool?
    private var drawerExpectationGeneration = 0
    private var authenticationPopups: [ObjectIdentifier: AuthenticationPopupController] = [:]
    private var approvedProgrammaticNavigationURLs = Set<String>()
    private var isRuntimeMessageHandlerInstalled = false

    init(settings: AppSettings, resourceBundle: Bundle = .main) {
        self.settings = settings
        compactPresetCSS = Self.loadBundledCSS(named: "compact", from: resourceBundle)
        layoutModifiersCSS = Self.loadBundledCSS(named: "layout-mods", from: resourceBundle)
        visualThemesCSS = Self.loadBundledCSS(named: "visual-themes", from: resourceBundle)

        let configuration = DiscordWebConfiguration.make()
        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

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

    func shutdown() {
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
    }

    private func refreshCSS(injectIntoCurrentPage: Bool) {
        refreshCSS(
            preset: settings.cssPreset,
            layoutOptions: settings.discordLayoutOptions,
            visualTheme: settings.visualTheme,
            themeAccent: settings.themeAccent,
            themeIntensity: settings.themeIntensity,
            themeColorScheme: settings.themeColorScheme,
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
        let contentController = webView.configuration.userContentController
        contentController.removeAllUserScripts()
        contentController.addUserScript(
            WKUserScript(
                source: DiscordCSSComposer.notificationBridgeUserScriptSource(),
                injectionTime: .atDocumentStart,
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
        webView.evaluateJavaScript(source) { [weak self] _, error in
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
            attentionModel.setIncomingCallActive(active)
            return
        }

        if type == "notification" {
            attentionModel.receiveNotification()
            return
        }

        guard type == "drawer", let isOpen = payload["open"] as? Bool else { return }
        if let expectedDrawerState, expectedDrawerState != isOpen { return }
        drawerExpectationGeneration += 1
        expectedDrawerState = nil
        isNavigationDrawerOpen = isOpen
    }
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
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                if destination.startAccessingSecurityScopedResource() {
                    self?.downloadSecurityScopedURLs[ObjectIdentifier(download)] = destination
                }
                completionHandler(destination)
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
        releaseSecurityScope(for: download)
    }

    func download(
        _ download: WKDownload,
        didFailWithError error: Error,
        resumeData: Data?
    ) {
        releaseSecurityScope(for: download)
        downloadError = error.localizedDescription
    }

    private func releaseSecurityScope(for download: WKDownload) {
        downloadSecurityScopedURLs
            .removeValue(forKey: ObjectIdentifier(download))?
            .stopAccessingSecurityScopedResource()
    }
}
