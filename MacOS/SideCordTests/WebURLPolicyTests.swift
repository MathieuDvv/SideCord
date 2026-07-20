import Foundation
import XCTest
@testable import SideCord

final class WebURLPolicyTests: XCTestCase {
    func testAllowsDiscordHTTPSHostsAndSubdomains() throws {
        let allowedURLs = [
            "https://discord.com/app",
            "https://canary.discord.com/channels/@me",
            "https://discordapp.com/",
            "https://cdn.discordapp.com/assets/icon.png",
            "https://discord.com./app"
        ]

        for rawURL in allowedURLs {
            let url = try XCTUnwrap(URL(string: rawURL))
            XCTAssertEqual(DiscordURLPolicy.decision(for: url), .allow, rawURL)
        }
    }

    func testOpensUnrelatedHTTPSURLsExternally() throws {
        let externalURLs = [
            "https://example.com/",
            "https://discord.com.example.com/",
            "https://discord.com@evil.example/"
        ]

        for rawURL in externalURLs {
            let url = try XCTUnwrap(URL(string: rawURL))
            XCTAssertEqual(
                DiscordURLPolicy.decision(for: url),
                .openExternally,
                rawURL
            )
        }
    }

    func testCancelsInsecureUnsupportedAndMissingURLs() throws {
        let cancelledURLs = [
            "http://discord.com/app",
            "javascript:alert(1)",
            "file:///tmp/index.html",
            "discord://channels/@me"
        ]

        for rawURL in cancelledURLs {
            let url = try XCTUnwrap(URL(string: rawURL))
            XCTAssertEqual(DiscordURLPolicy.decision(for: url), .cancel, rawURL)
        }
        XCTAssertEqual(DiscordURLPolicy.decision(for: nil), .cancel)
    }

    func testDiscordHostClassificationUsesLabelBoundaries() {
        XCTAssertTrue(DiscordURLPolicy.isDiscordHost("discord.com"))
        XCTAssertTrue(DiscordURLPolicy.isDiscordHost("CDN.DISCORDAPP.COM."))
        XCTAssertFalse(DiscordURLPolicy.isDiscordHost("discord.com.example.org"))
        XCTAssertFalse(DiscordURLPolicy.isDiscordHost("notdiscord.com"))
    }

    func testAuthenticationPopupPolicyIsNarrowlyScoped() throws {
        XCTAssertTrue(AuthenticationPopupPolicy.shouldOpenInApp(
            try XCTUnwrap(URL(string: "https://discord.com/oauth2/authorize"))
        ))
        XCTAssertTrue(AuthenticationPopupPolicy.shouldOpenInApp(
            try XCTUnwrap(URL(string: "https://accounts.google.com/o/oauth2/auth"))
        ))
        XCTAssertFalse(AuthenticationPopupPolicy.shouldOpenInApp(
            try XCTUnwrap(URL(string: "https://github.com/openai"))
        ))
        XCTAssertFalse(AuthenticationPopupPolicy.shouldOpenInApp(
            try XCTUnwrap(URL(string: "https://example.com/login"))
        ))
        XCTAssertFalse(AuthenticationPopupPolicy.shouldOpenInApp(
            try XCTUnwrap(URL(string: "https://cdn.discordapp.com/attachments/file.zip"))
        ))
    }

    func testDownloadPolicyRequiresAUserInitiatedMainFrameNavigation() {
        XCTAssertEqual(
            DiscordDownloadPolicy.decision(
                isForMainFrame: false,
                canShowMIMEType: false,
                userInitiated: true
            ),
            .allow
        )
        XCTAssertEqual(
            DiscordDownloadPolicy.decision(
                isForMainFrame: true,
                canShowMIMEType: false,
                userInitiated: false
            ),
            .cancel
        )
        XCTAssertEqual(
            DiscordDownloadPolicy.decision(
                isForMainFrame: true,
                canShowMIMEType: false,
                userInitiated: true
            ),
            .download
        )
    }

    func testJavaScriptConfirmationRequiresTopLevelDiscordHTTPSOrigin() {
        XCTAssertTrue(DiscordJavaScriptDialogPolicy.allowsConfirmation(
            scheme: "https",
            host: "discord.com",
            isMainFrame: true
        ))
        XCTAssertTrue(DiscordJavaScriptDialogPolicy.allowsConfirmation(
            scheme: "HTTPS",
            host: "canary.discord.com",
            isMainFrame: true
        ))
        XCTAssertFalse(DiscordJavaScriptDialogPolicy.allowsConfirmation(
            scheme: "http",
            host: "discord.com",
            isMainFrame: true
        ))
        XCTAssertFalse(DiscordJavaScriptDialogPolicy.allowsConfirmation(
            scheme: "https",
            host: "discord.com.example.org",
            isMainFrame: true
        ))
        XCTAssertFalse(DiscordJavaScriptDialogPolicy.allowsConfirmation(
            scheme: "https",
            host: "discord.com",
            isMainFrame: false
        ))
    }
}
