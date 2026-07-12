import WebKit
import XCTest
@testable import SideCord

final class WebConfigurationTests: XCTestCase {
    @MainActor
    func testDiscordConfigurationAddsSafariIdentityBeforeNavigation() async throws {
        let configuration = DiscordWebConfiguration.make()
        XCTAssertEqual(
            configuration.applicationNameForUserAgent,
            DiscordWebConfiguration.safariUserAgentSuffix
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let userAgent = try await webView.evaluateJavaScript("navigator.userAgent") as! String

        XCTAssertTrue(userAgent.contains("AppleWebKit/"))
        XCTAssertTrue(userAgent.contains("Version/26.0"))
        XCTAssertTrue(userAgent.contains("Safari/605.1.15"))
        XCTAssertFalse(userAgent.contains("Chrome"))
        XCTAssertFalse(userAgent.contains("Chromium"))
        XCTAssertFalse(userAgent.contains("Edg/"))
    }

    @MainActor
    func testPopupConfigurationReceivesTheSameSafariIdentity() {
        let configuration = WKWebViewConfiguration()

        DiscordWebConfiguration.applySafariCompatibility(to: configuration)

        XCTAssertEqual(
            configuration.applicationNameForUserAgent,
            DiscordWebConfiguration.safariUserAgentSuffix
        )
    }
}
