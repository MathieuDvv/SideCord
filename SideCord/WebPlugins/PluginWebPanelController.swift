import AppKit
import Combine
import CryptoKit
import Foundation
import WebKit

@MainActor
final class PluginWebPanelController: NSObject, ObservableObject {
    nonisolated private static let frameLoadInterruptedErrorDomain = "WebKitErrorDomain"
    nonisolated private static let frameLoadInterruptedErrorCode = 102
    nonisolated private static let layoutRuntimeMarker = "sidecord-document-layout-runtime-v1"

    @Published private(set) var isLoading = false
    @Published private(set) var currentURL: URL?
    @Published private(set) var lastRequestedURL: URL?
    @Published private(set) var errorMessage: String?
    @Published private(set) var recoveryCount = 0
    private(set) var playbackPauseRequestCount = 0

    let pluginIdentifier: String
    let panel: SideCordPluginWebPanel
    let permissions: SideCordPluginPermissions
    let websiteDataStoreIdentifier: UUID
    let websiteDataStore: WKWebsiteDataStore
    let webView: WKWebView

    private let navigationPolicy: PluginWebNavigationPolicy
    private let automaticallyLoads: Bool
    private let externalURLOpener: @MainActor (URL) -> Void
    private var isShutDown = false
    private var didBeginInitialLoad = false
    private var authenticationPopups: [ObjectIdentifier: AuthenticationPopupController] = [:]

    init(
        pluginIdentifier: String,
        panel: SideCordPluginWebPanel,
        permissions: SideCordPluginPermissions,
        automaticallyLoads: Bool = true,
        externalURLOpener: @escaping @MainActor (URL) -> Void = {
            NSWorkspace.shared.open($0)
        }
    ) {
        self.pluginIdentifier = pluginIdentifier
        self.panel = panel
        self.permissions = permissions
        self.automaticallyLoads = automaticallyLoads
        self.externalURLOpener = externalURLOpener
        navigationPolicy = PluginWebNavigationPolicy(
            allowedHosts: panel.allowedNavigationHosts
        )
        websiteDataStoreIdentifier = Self.stableDataStoreIdentifier(
            pluginIdentifier: pluginIdentifier,
            contributionIdentifier: panel.id
        )
        websiteDataStore = permissions.persistentWebsiteData
            ? WKWebsiteDataStore(forIdentifier: websiteDataStoreIdentifier)
            : .nonPersistent()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        DiscordWebConfiguration.applySafariCompatibility(to: configuration)

        Self.installStyleScript(panel.customCSS, in: configuration)
        Self.installLayoutScript(panel.documentLayouts, in: configuration)

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = true
    }

    func startLoadingIfNeeded() {
        guard automaticallyLoads, !didBeginInitialLoad, !isShutDown else { return }
        didBeginInitialLoad = true
        loadInitialURL()
    }

    func loadInitialURL() {
        guard !isShutDown else { return }
        errorMessage = nil
        lastRequestedURL = panel.initialURL
        if automaticallyLoads {
            isLoading = true
            webView.load(URLRequest(url: panel.initialURL))
        }
    }

    func reload() {
        guard !isShutDown else { return }
        errorMessage = nil
        if webView.url == nil {
            loadInitialURL()
        } else {
            webView.reload()
        }
    }

    func openInBrowser() {
        let url = currentURL ?? webView.url ?? panel.initialURL
        guard navigationPolicy.decision(for: url, userInitiated: true) == .allow else {
            return
        }
        externalURLOpener(url)
    }

    func pausePlayback() {
        guard !isShutDown else { return }
        playbackPauseRequestCount += 1
        guard webView.url != nil else { return }
        webView.pauseAllMediaPlayback(completionHandler: {})
    }

    func clearWebsiteData() async {
        guard !isShutDown else { return }
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        await withCheckedContinuation { continuation in
            websiteDataStore.removeData(
                ofTypes: dataTypes,
                modifiedSince: .distantPast
            ) {
                continuation.resume()
            }
        }
        loadInitialURL()
    }

    func recoverAfterWebContentProcessTermination() {
        guard !isShutDown else { return }
        recoveryCount += 1
        loadInitialURL()
        errorMessage = "The web panel stopped unexpectedly and was reloaded."
    }

    @discardableResult
    func handleTopLevelNavigation(
        to url: URL?,
        userInitiated: Bool
    ) -> PluginWebNavigationDecision {
        let decision = navigationPolicy.decision(
            for: url,
            userInitiated: userInitiated
        )
        if decision == .openExternally, let url {
            externalURLOpener(url)
        }
        return decision
    }

    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        for popup in authenticationPopups.values {
            popup.onClose = nil
            popup.windowController.close()
        }
        authenticationPopups.removeAll()
        webView.stopLoading()
        webView.pauseAllMediaPlayback(completionHandler: {})
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    private func authenticationPopupDidClose(id: ObjectIdentifier) {
        authenticationPopups.removeValue(forKey: id)
        guard !isShutDown else { return }
        reload()
    }

    static func stableDataStoreIdentifier(
        pluginIdentifier: String,
        contributionIdentifier: String
    ) -> UUID {
        let identity = "sidecord.web-panel.v1\u{0}\(pluginIdentifier)\u{0}\(contributionIdentifier)"
        let digest = SHA256.hash(data: Data(identity.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    static func styleInjectionSource(css: String) -> String {
        let encoded = (try? JSONEncoder().encode(css)) ?? Data("\"\"".utf8)
        let escapedCSS = String(decoding: encoded, as: UTF8.self)
        return """
        (() => {
            const css = \(escapedCSS);
            document.documentElement.dataset.sidecordPluginHost = location.hostname.toLowerCase();
            let style = document.getElementById("sidecord-plugin-style");
            if (!style) {
                style = document.createElement("style");
                style.id = "sidecord-plugin-style";
                document.documentElement.appendChild(style);
            }
            style.textContent = css;
        })();
        """
    }

    static func layoutInjectionSource(
        layouts: [SideCordPluginDocumentLayout]
    ) -> String {
        let encoded = (try? JSONEncoder().encode(layouts)) ?? Data("[]".utf8)
        let layoutJSON = String(decoding: encoded, as: UTF8.self)
        return """
        (() => {
            const runtimeMarker = "\(layoutRuntimeMarker)";
            const definitions = \(layoutJSON);
            const host = location.hostname.toLowerCase();
            const definition = definitions.find(item => item.host === host);
            if (!definition) return;

            const shellID = "sidecord-plugin-layout";
            const records = new Map();
            let observer = null;
            let resizeObserver = null;
            let observedShell = null;
            let activeShell = null;
            let scheduled = false;

            const isVisible = element => {
                if (!(element instanceof Element)) return false;
                for (let current = element; current; current = current.parentElement) {
                    const style = getComputedStyle(current);
                    if (style.display === "none" || style.visibility === "hidden") return false;
                }
                return element.getClientRects().length > 0;
            };

            const updateResponsiveState = shell => {
                const width = Math.max(document.documentElement.clientWidth, 0);
                const height = Math.max(document.documentElement.clientHeight, 0);
                const widthState = width < 420 ? "narrow" : width < 700 ? "regular" : "wide";
                const heightState = height < 150 ? "compact" : height < 220 ? "standard" : "tall";
                const widthValue = `${Math.round(width)}px`;
                const heightValue = `${Math.round(height)}px`;
                if (shell.dataset.sidecordWidth !== widthState) shell.dataset.sidecordWidth = widthState;
                if (shell.dataset.sidecordHeight !== heightState) shell.dataset.sidecordHeight = heightState;
                if (shell.style.getPropertyValue("--sidecord-panel-width") !== widthValue) {
                    shell.style.setProperty("--sidecord-panel-width", widthValue);
                }
                if (shell.style.getPropertyValue("--sidecord-panel-height") !== heightValue) {
                    shell.style.setProperty("--sidecord-panel-height", heightValue);
                }
            };

            const ensureShell = mount => {
                let shell = document.getElementById(shellID);
                if (!shell) {
                    shell = document.createElement("div");
                    shell.id = shellID;
                }
                if (shell.parentElement !== mount) mount.appendChild(shell);
                shell.dataset.sidecordLayoutHost = host;

                const expected = new Set(definition.slots.map(slot => slot.id));
                for (const child of Array.from(shell.children)) {
                    const id = child.getAttribute("data-sidecord-slot");
                    if (id && !expected.has(id)) child.remove();
                }
                for (const slot of definition.slots) {
                    let wrapper = Array.from(shell.children).find(child =>
                        child.getAttribute("data-sidecord-slot") === slot.id
                    );
                    if (!wrapper) {
                        wrapper = document.createElement("section");
                        wrapper.setAttribute("data-sidecord-slot", slot.id);
                        shell.appendChild(wrapper);
                    }
                }
                updateResponsiveState(shell);
                return shell;
            };

            const findCandidate = (slot, shell, wrapper) => {
                for (const selector of slot.selectors) {
                    let matches = [];
                    try {
                        matches = Array.from(document.querySelectorAll(selector));
                    } catch (_) {
                        continue;
                    }
                    for (const match of matches) {
                        if (match === shell) continue;
                        if (shell.contains(match) && !wrapper.contains(match)) continue;
                        if (slot.selection === "first" || isVisible(match)) return match;
                    }
                }
                return null;
            };

            const observe = () => {
                if (!document.documentElement) return;
                observer.observe(document.documentElement, {
                    subtree: true,
                    childList: true,
                    attributes: true,
                    attributeFilter: ["class", "hidden", "style"]
                });
            };

            const reconcile = () => {
                scheduled = false;
                observer.disconnect();
                document.documentElement.dataset.sidecordDocumentLayout = "reconciling";

                let mount = null;
                try {
                    mount = document.querySelector(definition.mountSelector);
                } catch (_) {
                    observe();
                    return;
                }
                if (!mount) {
                    observe();
                    return;
                }

                const shell = ensureShell(mount);
                activeShell = shell;
                const slotsAndCandidates = definition.slots.map(slot => {
                    const wrapper = Array.from(shell.children).find(child =>
                        child.getAttribute("data-sidecord-slot") === slot.id
                    );
                    const existing = records.get(slot.id);
                    const canReuseExisting = existing?.node.isConnected && (
                        existing.preserved || (
                            existing.node.parentElement === wrapper &&
                            existing.marker?.isConnected
                        )
                    );
                    const node = canReuseExisting
                        ? existing.node
                        : findCandidate(slot, shell, wrapper);
                    return { slot, wrapper, node };
                });
                if (records.size === 0 && slotsAndCandidates.some(item => !item.node)) {
                    shell.hidden = true;
                    shell.style.setProperty("display", "none", "important");
                    for (const { wrapper } of slotsAndCandidates) {
                        wrapper.dataset.sidecordEmpty = "true";
                    }
                    document.documentElement.dataset.sidecordDocumentLayout = "pending";
                    observe();
                    return;
                }
                shell.hidden = false;
                shell.style.removeProperty("display");
                for (const { slot, wrapper, node } of slotsAndCandidates) {
                    const existing = records.get(slot.id);
                    if (slot.strategy === "preserve") {
                        if (node?.isConnected) {
                            records.set(slot.id, { node, marker: null, preserved: true });
                            wrapper.dataset.sidecordEmpty = "false";
                        } else {
                            records.delete(slot.id);
                            wrapper.dataset.sidecordEmpty = "true";
                        }
                        continue;
                    }
                    if (node === existing?.node && node.isConnected && node.parentElement === wrapper) {
                        wrapper.dataset.sidecordEmpty = "false";
                    } else if (node && node.parentNode) {
                        let marker = existing?.marker ?? null;
                        if (existing && existing.node !== node) {
                            if (existing.marker.parentNode) {
                                existing.marker.parentNode.replaceChild(existing.node, existing.marker);
                            } else {
                                existing.node.remove();
                            }
                        }
                        if (node.parentElement !== wrapper) {
                            marker = document.createComment(`sidecord-slot:${slot.id}`);
                            node.parentNode.insertBefore(marker, node);
                            wrapper.appendChild(node);
                        }
                        records.set(slot.id, { node, marker, preserved: false });
                        wrapper.dataset.sidecordEmpty = "false";
                    } else {
                        if (existing) {
                            if (!existing.preserved) {
                                if (existing.marker?.parentNode) existing.marker.remove();
                                existing.node.remove();
                            }
                            records.delete(slot.id);
                        }
                        wrapper.dataset.sidecordEmpty = "true";
                    }
                }

                if (!resizeObserver || observedShell !== shell) {
                    if (resizeObserver) resizeObserver.disconnect();
                    resizeObserver = new ResizeObserver(() => updateResponsiveState(shell));
                    resizeObserver.observe(document.documentElement);
                    resizeObserver.observe(shell);
                    observedShell = shell;
                }
                document.documentElement.dataset.sidecordDocumentLayout = "active";
                observe();
            };

            const schedule = () => {
                if (scheduled) return;
                scheduled = true;
                setTimeout(reconcile, 16);
            };

            observer = new MutationObserver(mutations => {
                const onlyRuntimeAttributes = activeShell && mutations.every(mutation =>
                    mutation.type === "attributes" && activeShell.contains(mutation.target)
                );
                if (!onlyRuntimeAttributes) schedule();
            });
            document.documentElement.dataset.sidecordPluginHost = host;
            document.documentElement.dataset.sidecordDocumentLayout = "pending";
            observe();
            if (document.readyState === "loading") {
                document.addEventListener("DOMContentLoaded", schedule, { once: true });
            }
            schedule();
        })();
        """
    }

    private static func installStyleScript(
        _ css: String?,
        in configuration: WKWebViewConfiguration
    ) {
        guard let css, !css.isEmpty,
              !configuration.userContentController.userScripts.contains(where: {
                  $0.source.contains("sidecord-plugin-style")
              })
        else { return }
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: styleInjectionSource(css: css),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
    }

    private static func installLayoutScript(
        _ layouts: [SideCordPluginDocumentLayout],
        in configuration: WKWebViewConfiguration
    ) {
        guard !layouts.isEmpty,
              !configuration.userContentController.userScripts.contains(where: {
                  $0.source.contains(layoutRuntimeMarker)
              })
        else { return }
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: layoutInjectionSource(layouts: layouts),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
    }

    nonisolated static func isIgnorableNavigationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled {
            return true
        }
        return nsError.domain == frameLoadInterruptedErrorDomain
            && nsError.code == frameLoadInterruptedErrorCode
    }
}

extension PluginWebPanelController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.cancel)
            return
        }

        let isTopLevel = navigationAction.targetFrame?.isMainFrame != false
        guard isTopLevel else {
            decisionHandler(.allow)
            return
        }
        let userInitiated = navigationAction.navigationType == .linkActivated
        switch handleTopLevelNavigation(
            to: navigationAction.request.url,
            userInitiated: userInitiated
        ) {
        case .allow:
            decisionHandler(.allow)
        case .openExternally:
            decisionHandler(.cancel)
        case .cancel:
            isLoading = false
            if let host = navigationAction.request.url?.host(percentEncoded: false) {
                errorMessage = "Navigation to \(host) was blocked because the plugin does not declare that host."
            } else {
                errorMessage = "The plugin blocked an invalid navigation request."
            }
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        isLoading = true
        errorMessage = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        isLoading = false
        currentURL = webView.url
        errorMessage = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: Error
    ) {
        recordNavigationFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        recordNavigationFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        recoverAfterWebContentProcessTermination()
    }

    private func recordNavigationFailure(_ error: Error) {
        guard !Self.isIgnorableNavigationError(error) else { return }
        isLoading = false
        errorMessage = error.localizedDescription
    }
}

extension PluginWebPanelController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        let userInitiated = navigationAction.navigationType == .linkActivated
        switch handleTopLevelNavigation(
            to: navigationAction.request.url,
            userInitiated: userInitiated
        ) {
        case .allow:
            Self.installStyleScript(panel.customCSS, in: configuration)
            Self.installLayoutScript(panel.documentLayouts, in: configuration)
            let popup = AuthenticationPopupController(
                configuration: configuration,
                allowedHosts: navigationPolicy.allowedHosts
            )
            let id = ObjectIdentifier(popup.webView)
            popup.onClose = { [weak self] in
                self?.authenticationPopupDidClose(id: id)
            }
            authenticationPopups[id] = popup
            popup.show()
            return popup.webView
        case .openExternally:
            break
        case .cancel:
            break
        }
        return nil
    }
}
