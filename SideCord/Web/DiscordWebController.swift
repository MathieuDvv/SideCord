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

@MainActor
final class DiscordWebController: NSObject, ObservableObject {
    static let discordAppURL = URL(string: "https://discord.com/app")!

    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var currentURL: URL?
    @Published private(set) var error: DiscordWebError?
    @Published private(set) var downloadError: String?

    let webView: WKWebView

    private let settings: AppSettings
    private let compactPresetCSS: String
    private let layoutModifiersCSS: String
    private var settingsCancellables = Set<AnyCancellable>()
    private var attemptedProcessRecovery = false
    private var downloadSecurityScopedURLs: [ObjectIdentifier: URL] = [:]
    private var pendingUserInitiatedMainFrameNavigation = false
    private var authenticationPopups: [ObjectIdentifier: AuthenticationPopupController] = [:]
    private var approvedProgrammaticNavigationURLs = Set<String>()

    init(settings: AppSettings, resourceBundle: Bundle = .main) {
        self.settings = settings
        compactPresetCSS = Self.loadBundledCSS(named: "compact", from: resourceBundle)
        layoutModifiersCSS = Self.loadBundledCSS(named: "layout-mods", from: resourceBundle)

        let configuration = DiscordWebConfiguration.make()
        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
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
            customCSS: settings.customCSS,
            customCSSEnabled: settings.customCSSEnabled,
            injectIntoCurrentPage: injectIntoCurrentPage
        )
    }

    private func refreshCSS(
        preset: CSSPreset,
        layoutOptions: DiscordLayoutOptions,
        customCSS: String,
        customCSSEnabled: Bool,
        injectIntoCurrentPage: Bool
    ) {
        let css = DiscordCSSComposer.compose(
            preset: preset,
            compactPresetCSS: compactPresetCSS,
            layoutModifiersCSS: layoutModifiersCSS,
            layoutOptions: layoutOptions,
            customCSS: customCSS,
            customCSSEnabled: customCSSEnabled
        )
        let source = DiscordCSSComposer.userScriptSource(
            css: css,
            rootAttributeNames: DiscordCSSComposer.rootAttributeNames(for: layoutOptions)
        )
        let contentController = webView.configuration.userContentController
        contentController.removeAllUserScripts()
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

        webView.evaluateJavaScript(source) { _, _ in
            // A navigation may replace the document while this is executing.
            // The registered WKUserScript will apply the same CSS to the new one.
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
