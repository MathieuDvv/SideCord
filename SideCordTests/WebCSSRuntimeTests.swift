import WebKit
import XCTest
@testable import SideCord

@MainActor
final class WebCSSRuntimeTests: XCTestCase {
    func testRuntimeRepairsDiscordInteractionAndUsesLatestConfiguration() async throws {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let loaded = expectation(description: "Local Discord fixture loaded")
        let navigationWaiter = NavigationWaiter { loaded.fulfill() }
        webView.navigationDelegate = navigationWaiter
        webView.loadHTMLString(
            "<html><head></head><body><main>Fixture</main></body></html>",
            baseURL: URL(string: "https://discord.com/app")!
        )
        await fulfillment(of: [loaded], timeout: 5)

        let host = try await webView.evaluateJavaScript("window.location.hostname") as! String
        XCTAssertEqual(host, "discord.com")

        let firstSource = DiscordCSSComposer.userScriptSource(
            css: "body { color: red; }",
            rootAttributeNames: ["data-sidecord-hide-servers"]
        )
        _ = try await webView.evaluateJavaScript(firstSource)
        try await assertRuntime(
            in: webView,
            enabledAttribute: "data-sidecord-hide-servers",
            css: "body { color: red; }"
        )

        _ = try await webView.evaluateJavaScript(
            """
            document.documentElement.removeAttribute('data-sidecord-hide-servers');
            document.getElementById('sidecord-injected-css').remove();
            """
        )
        try await Task.sleep(for: .milliseconds(100))
        try await assertRuntime(
            in: webView,
            enabledAttribute: "data-sidecord-hide-servers",
            css: "body { color: red; }"
        )

        let secondSource = DiscordCSSComposer.userScriptSource(
            css: "body { color: blue; }",
            rootAttributeNames: ["data-sidecord-hide-channels"]
        )
        _ = try await webView.evaluateJavaScript(secondSource)
        let oldAttribute = try await webView.evaluateJavaScript(
            "document.documentElement.hasAttribute('data-sidecord-hide-servers')"
        ) as! Bool
        XCTAssertFalse(oldAttribute)

        _ = try await webView.evaluateJavaScript(
            """
            document.documentElement.removeAttribute('data-sidecord-hide-channels');
            document.getElementById('sidecord-injected-css').textContent = 'stale';
            """
        )
        try await Task.sleep(for: .milliseconds(100))
        try await assertRuntime(
            in: webView,
            enabledAttribute: "data-sidecord-hide-channels",
            css: "body { color: blue; }"
        )

        let disabledSource = DiscordCSSComposer.userScriptSource(css: "")
        _ = try await webView.evaluateJavaScript(disabledSource)
        let isClean = try await webView.evaluateJavaScript(
            """
            !document.querySelector('[data-sidecord-hide-servers], [data-sidecord-hide-channels]') &&
            !document.getElementById('sidecord-injected-css')
            """
        ) as! Bool
        XCTAssertTrue(isClean)
    }

    private func assertRuntime(
        in webView: WKWebView,
        enabledAttribute: String,
        css: String
    ) async throws {
        let attributeIsPresent = try await webView.evaluateJavaScript(
            "document.documentElement.hasAttribute('\(enabledAttribute)')"
        ) as! Bool
        let injectedCSS = try await webView.evaluateJavaScript(
            "document.getElementById('sidecord-injected-css')?.textContent || ''"
        ) as! String

        XCTAssertTrue(attributeIsPresent)
        XCTAssertEqual(injectedCSS, css)
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish()
    }
}
