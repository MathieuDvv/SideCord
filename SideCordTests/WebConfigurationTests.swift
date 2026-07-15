import WebKit
import XCTest
@testable import SideCord

final class WebConfigurationTests: XCTestCase {
    func testDownloadInstallerPreservesExistingFileUntilInstall() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("archive.txt")
        let temporary = directory.appendingPathComponent("incoming.txt")
        try Data("existing".utf8).write(to: destination)
        try Data("replacement".utf8).write(to: temporary)

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "existing")
        XCTAssertEqual(try String(contentsOf: temporary, encoding: .utf8), "replacement")

        try DownloadFileInstaller.install(
            temporaryURL: temporary,
            at: destination
        )

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "replacement")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
    }

    func testDownloadInstallerMovesNewFileIntoPlace() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("new.txt")
        let temporary = directory.appendingPathComponent("incoming.txt")
        try Data("download".utf8).write(to: temporary)

        try DownloadFileInstaller.install(
            temporaryURL: temporary,
            at: destination
        )

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "download")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
    }

    func testDownloadInstallerPrunesOnlyStaleTemporaryFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date(timeIntervalSince1970: 10_000)
        let stale = directory.appendingPathComponent("stale.download")
        let fresh = directory.appendingPathComponent("fresh.download")
        try Data("partial".utf8).write(to: stale)
        try Data("active".utf8).write(to: fresh)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-7_200)],
            ofItemAtPath: stale.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-30)],
            ofItemAtPath: fresh.path
        )

        let removed = try DownloadFileInstaller.removeStaleTemporaryFiles(
            olderThan: 3_600,
            now: now,
            in: directory
        )

        XCTAssertEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
    }

    @MainActor
    func testAttentionModelBaselinesExistingBadgesAndSignalsNewActivity() {
        let model = DiscordAttentionModel()
        let baseline = [
            railItem(id: "direct-messages", unread: true, mentions: 2),
            railItem(id: "server:1", unread: false, mentions: nil)
        ]

        model.receiveRailItems(baseline)
        XCTAssertEqual(model.notificationSequence, 0)

        model.receiveRailItems(baseline)
        XCTAssertEqual(model.notificationSequence, 0)

        model.receiveRailItems([
            railItem(id: "direct-messages", unread: true, mentions: 2),
            railItem(id: "server:1", unread: true, mentions: nil)
        ])
        XCTAssertEqual(model.notificationSequence, 1)

        // Every explicit delivery remains observable. Duplicate signal paths
        // merely restart the current glow instead of risking a dropped event.
        model.receiveNotification()
        XCTAssertEqual(model.notificationSequence, 2)

        model.receiveRailItems([
            railItem(id: "direct-messages", unread: true, mentions: 3),
            railItem(id: "server:1", unread: true, mentions: nil)
        ])
        XCTAssertEqual(model.notificationSequence, 3)

        model.receiveRailItems([
            railItem(id: "direct-messages", unread: true, mentions: 3),
            railItem(id: "server:1", unread: true, mentions: nil)
        ])
        XCTAssertEqual(model.notificationSequence, 3)

        model.receiveRailItems([
            railItem(id: "direct-messages", unread: true, mentions: 3),
            railItem(id: "server:2", unread: true, mentions: 4)
        ])
        XCTAssertEqual(model.notificationSequence, 3)

        model.receiveRailItems([])
        model.receiveRailItems([
            railItem(id: "direct-messages", unread: true, mentions: 8),
            railItem(id: "server:1", unread: true, mentions: nil)
        ])
        XCTAssertEqual(model.notificationSequence, 4)

        model.receiveNotification()
        XCTAssertEqual(model.notificationSequence, 5)

        model.receiveNotification()
        XCTAssertEqual(model.notificationSequence, 6)

        // Ordinary messages continue to pulse even while the server's unread
        // state remains true and its mention count does not change.
        model.receiveNotification()
        XCTAssertEqual(model.notificationSequence, 7)
    }

    @MainActor
    func testAttentionModelResetsCallAndRebaselinesAfterNavigation() {
        let model = DiscordAttentionModel()
        model.receiveRailItems([railItem(id: "server:1", unread: false, mentions: nil)])
        model.setIncomingCallActive(true)

        XCTAssertTrue(model.isIncomingCallActive)

        model.reset()
        XCTAssertFalse(model.isIncomingCallActive)

        model.receiveRailItems([railItem(id: "server:1", unread: true, mentions: 1)])
        XCTAssertEqual(model.notificationSequence, 0)
    }

    @MainActor
    func testIncomingCallDescriptorIsBoundedNormalizedAndMemoryOnly() {
        let model = DiscordAttentionModel()
        model.setIncomingCall(IncomingCallDescriptor(
            id: String(repeating: "x", count: 200),
            displayName: "  Ada   Lovelace\n"
        ))

        XCTAssertEqual(model.incomingCall?.id.count, 128)
        XCTAssertEqual(model.incomingCall?.displayName, "Ada Lovelace")
        XCTAssertTrue(model.isIncomingCallActive)

        model.reset()
        XCTAssertNil(model.incomingCall)
        XCTAssertFalse(model.isIncomingCallActive)
    }

    @MainActor
    func testRailModelValidatesAndCapsBridgePayload() throws {
        let model = DiscordRailModel()
        model.receive(messageItems: [
            [
                "id": "direct-messages",
                "title": "  Direct Messages  ",
                "icon": NSNull(),
                "kind": "directMessages",
                "selected": true,
                "unread": false,
                "mentions": NSNull()
            ],
            [
                "id": "server:123",
                "title": String(repeating: "S", count: 140),
                "icon": "https://cdn.discordapp.com/icons/123/example.png",
                "kind": "server",
                "selected": false,
                "unread": true,
                "mentions": 7
            ]
        ])

        XCTAssertEqual(model.items.count, 2)
        XCTAssertEqual(model.items[0].title, "Direct Messages")
        XCTAssertNil(model.items[0].iconURL)
        XCTAssertEqual(model.items[1].title.count, DiscordRailModel.maximumTitleLength)
        XCTAssertEqual(model.items[1].kind, .server)
        XCTAssertEqual(model.items[1].mentionCount, 7)
        XCTAssertEqual(model.items[1].iconURL?.host, "cdn.discordapp.com")

        let acceptedItems = model.items
        model.receive(messageItems: [[
            "id": "server:evil",
            "title": "External icon",
            "icon": "https://tracking.example/icon.png",
            "kind": "server",
            "selected": false,
            "unread": false,
            "mentions": NSNull()
        ]])
        XCTAssertEqual(model.items, acceptedItems)

        let oversizedPayload: [[String: Any]] = (0...DiscordRailModel.maximumItemCount).map {
            [
                "id": "server:\($0)",
                "title": "Server \($0)",
                "icon": NSNull(),
                "kind": "server",
                "selected": false,
                "unread": false,
                "mentions": NSNull()
            ]
        }
        model.receive(messageItems: oversizedPayload)
        XCTAssertEqual(model.items, acceptedItems)
    }

    @MainActor
    func testRailModelRejectsDuplicateOrMalformedIdentifiersAndUnsafeCounts() {
        let model = DiscordRailModel()
        let baseline: [[String: Any]] = [[
            "id": "action:create-server",
            "title": "Add a Server",
            "icon": "data:image/png;base64,iVBORw0KGgo=",
            "kind": "action",
            "selected": false,
            "unread": false,
            "mentions": NSNull()
        ]]
        model.receive(messageItems: baseline)
        XCTAssertEqual(model.items.first?.kind, .action)
        XCTAssertEqual(model.items.first?.iconURL?.scheme, "data")

        for invalidPayload in [
            [baseline[0], baseline[0]],
            [[
                "id": "server:1');alert(1)",
                "title": "Bad",
                "icon": NSNull(),
                "kind": "server",
                "selected": false,
                "unread": false,
                "mentions": NSNull()
            ]],
            [[
                "id": "server:1",
                "title": "Bad count",
                "icon": NSNull(),
                "kind": "server",
                "selected": false,
                "unread": true,
                "mentions": 10_000
            ]]
        ] {
            model.receive(messageItems: invalidPayload)
            XCTAssertEqual(model.items.count, 1)
            XCTAssertEqual(model.items.first?.id, "action:create-server")
        }
    }

    func testRuntimeActionQueueWaitsForReadinessAndPreservesOrder() {
        var queue = DiscordRuntimeActionQueue()
        queue.enqueue("toggleDrawer")
        queue.enqueue("toggleDrawer")
        queue.enqueue("openDrawer")

        XCTAssertNil(queue.beginNext())
        queue.markReady()

        XCTAssertEqual(queue.beginNext(), "toggleDrawer")
        queue.complete("toggleDrawer", succeeded: true)
        XCTAssertEqual(queue.beginNext(), "toggleDrawer")
        queue.complete("toggleDrawer", succeeded: true)
        XCTAssertEqual(queue.beginNext(), "openDrawer")
        queue.complete("openDrawer", succeeded: true)
        XCTAssertTrue(queue.pending.isEmpty)
    }

    func testRuntimeActionQueueRetriesAfterRuntimeFailureOrNavigationRace() {
        var queue = DiscordRuntimeActionQueue()
        queue.enqueue("openDrawer")
        queue.markReady()
        XCTAssertEqual(queue.beginNext(), "openDrawer")

        queue.markLoading()
        queue.complete("openDrawer", succeeded: true)
        XCTAssertEqual(queue.pending, ["openDrawer"])
        XCTAssertNil(queue.inFlight)

        queue.markReady()
        XCTAssertEqual(queue.beginNext(), "openDrawer")
        queue.complete("openDrawer", succeeded: false)
        XCTAssertFalse(queue.isReady)
        XCTAssertEqual(queue.pending, ["openDrawer"])

        queue.markReady()
        XCTAssertEqual(queue.beginNext(), "openDrawer")
        queue.complete("openDrawer", succeeded: true)
        XCTAssertTrue(queue.pending.isEmpty)
    }

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

    private func railItem(
        id: String,
        unread: Bool,
        mentions: Int?
    ) -> DiscordRailItem {
        DiscordRailItem(
            id: id,
            title: id,
            iconURL: nil,
            kind: id == "direct-messages" ? .directMessages : .server,
            isSelected: false,
            hasUnread: unread,
            mentionCount: mentions
        )
    }
}
