import AppKit
import WebKit

enum AuthenticationPopupPolicy {
    static func shouldOpenInApp(_ url: URL?) -> Bool {
        guard let url,
              url.scheme?.lowercased() == "https",
              let host = url.host(percentEncoded: false)?.lowercased()
        else { return false }

        let path = url.path.lowercased()
        if DiscordURLPolicy.isDiscordHost(host) {
            return path.hasPrefix("/login")
                || path.hasPrefix("/oauth2")
                || path.hasPrefix("/api/oauth2")
                || path.hasPrefix("/authorize")
        }

        switch host {
        case "accounts.google.com", "appleid.apple.com",
             "login.microsoftonline.com", "login.live.com":
            return true
        case "github.com":
            return path.hasPrefix("/login/oauth")
        case "twitter.com", "x.com":
            return path.hasPrefix("/i/oauth")
        case "id.twitch.tv":
            return path.hasPrefix("/oauth")
        case "steamcommunity.com":
            return path.hasPrefix("/openid")
        case "www.facebook.com":
            return path.hasPrefix("/dialog/oauth")
        default:
            return false
        }
    }
}

@MainActor
final class AuthenticationPopupController: NSObject {
    let webView: WKWebView
    let windowController: NSWindowController
    var onClose: (() -> Void)?

    private var hasNotifiedClose = false

    init(configuration: WKWebViewConfiguration) {
        DiscordWebConfiguration.applySafariCompatibility(to: configuration)
        webView = WKWebView(frame: .zero, configuration: configuration)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Continue signing in"
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.center()
        windowController = NSWindowController(window: window)

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        window.delegate = self
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
    }

    private func notifyClose() {
        guard !hasNotifiedClose else { return }
        hasNotifiedClose = true
        onClose?()
    }
}

extension AuthenticationPopupController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        notifyClose()
    }
}

extension AuthenticationPopupController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
            return
        }

        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let scheme = url.scheme?.lowercased()
        decisionHandler(scheme == "https" || scheme == "about" ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if let host = webView.url?.host(percentEncoded: false) {
            windowController.window?.title = "Continue on \(host)"
        }
    }
}

extension AuthenticationPopupController: WKUIDelegate {
    func webViewDidClose(_ webView: WKWebView) {
        windowController.close()
        notifyClose()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url,
              url.scheme?.lowercased() == "https"
        else { return nil }
        webView.load(URLRequest(url: url))
        return nil
    }
}
