import WebKit
import XCTest
@testable import SideCord

final class PluginWebNavigationPolicyTests: XCTestCase {
    func testAllowedNavigationUsesExactHTTPSHosts() {
        let policy = PluginWebNavigationPolicy(
            allowedHosts: ["music.youtube.com", "accounts.google.com"]
        )

        XCTAssertEqual(
            policy.decision(
                for: URL(string: "https://music.youtube.com/watch?v=1"),
                userInitiated: false
            ),
            .allow
        )
        XCTAssertEqual(
            policy.decision(
                for: URL(string: "http://music.youtube.com/"),
                userInitiated: true
            ),
            .cancel
        )
        XCTAssertEqual(
            policy.decision(
                for: URL(string: "https://sub.music.youtube.com/"),
                userInitiated: false
            ),
            .cancel
        )
    }

    func testUserClickedExternalHTTPSLinkOpensExternallyButProgrammaticNavigationCancels() {
        let policy = PluginWebNavigationPolicy(allowedHosts: ["music.youtube.com"])
        let external = URL(string: "https://example.com/help")

        XCTAssertEqual(policy.decision(for: external, userInitiated: true), .openExternally)
        XCTAssertEqual(policy.decision(for: external, userInitiated: false), .cancel)
    }
}

@MainActor
final class PluginWebPanelControllerTests: XCTestCase {
    func testCSSIsHostGeneratedAndInjectedOnlyIntoTheTopLevelPage() throws {
        let controller = makeController(customCSS: "ytmusic-nav-bar { display: none !important; }")
        let script = try XCTUnwrap(
            controller.webView.configuration.userContentController.userScripts.first
        )

        XCTAssertTrue(script.isForMainFrameOnly)
        XCTAssertTrue(script.source.contains("sidecord-plugin-style"))
        XCTAssertTrue(script.source.contains("sidecordPluginHost"))
        XCTAssertTrue(script.source.contains("location.hostname"))
        XCTAssertTrue(script.source.contains("ytmusic-nav-bar"))
        controller.shutdown()
    }

    func testDocumentLayoutIsHostGeneratedResponsiveAndMainFrameOnly() throws {
        let layout = SideCordPluginDocumentLayout(
            host: "music.youtube.com",
            mountSelector: "ytmusic-app",
            slots: [
                SideCordPluginDocumentLayoutSlot(
                    id: "content",
                    selectors: ["ytmusic-browse-response", "ytmusic-search-page"],
                    selection: .firstVisible
                ),
                SideCordPluginDocumentLayoutSlot(
                    id: "player",
                    selectors: ["ytmusic-player-bar"]
                )
            ]
        )
        let controller = makeController(documentLayouts: [layout])
        defer { controller.shutdown() }
        let scripts = controller.webView.configuration.userContentController.userScripts
        let script = try XCTUnwrap(scripts.first { $0.source.contains("sidecord-plugin-layout") })

        XCTAssertTrue(script.isForMainFrameOnly)
        XCTAssertTrue(script.source.contains("MutationObserver"))
        XCTAssertTrue(script.source.contains("ResizeObserver"))
        XCTAssertTrue(script.source.contains("firstVisible"))
        XCTAssertTrue(script.source.contains("slot.strategy === \"preserve\""))
        XCTAssertTrue(script.source.contains("sidecordWidth"))
        XCTAssertTrue(script.source.contains("sidecordHeight"))
        XCTAssertTrue(script.source.contains("slotsAndCandidates.some"))
        XCTAssertTrue(script.source.contains("shell.hidden = true"))
        XCTAssertTrue(script.source.contains("sidecordDocumentLayout = \"pending\""))
        XCTAssertTrue(script.source.contains("music.youtube.com"))
        XCTAssertFalse(script.source.contains("accounts.google.com"))
    }

    func testDocumentLayoutMovesNativeElementsAndReconcilesReplacementContent() async throws {
        let controller = makeController()
        defer { controller.shutdown() }
        controller.webView.frame = NSRect(x: 0, y: 0, width: 800, height: 180)
        controller.webView.loadHTMLString(
            """
            <!doctype html><html><head><style>
            html, body, music-app { display: block; width: 100%; height: 100%; margin: 0; }
            top-bar, content-one, content-two, player-bar { display: block; height: 20px; }
            content-one { display: none; }
            </style></head><body><music-app>
            <top-bar><button id="native-button">Native</button></top-bar>
            <content-one>Hidden</content-one><content-two>Visible</content-two>
            <player-bar>Player</player-bar>
            </music-app><script>
            window.nativeClickCount = 0;
            document.getElementById("native-button").addEventListener("click", () => nativeClickCount += 1);
            </script></body></html>
            """,
            baseURL: URL(string: "https://music.youtube.com/")
        )

        try await waitForJavaScriptTrue(
            "document.querySelector('music-app') !== null",
            in: controller.webView
        )
        let hostValue = try await controller.webView.evaluateJavaScript("location.hostname")
        let host = try XCTUnwrap(hostValue as? String)
        let layout = SideCordPluginDocumentLayout(
            host: host,
            mountSelector: "music-app",
            slots: [
                SideCordPluginDocumentLayoutSlot(
                    id: "topbar",
                    selectors: ["top-bar"]
                ),
                SideCordPluginDocumentLayoutSlot(
                    id: "content",
                    selectors: ["content-one", "content-two"],
                    selection: .firstVisible
                ),
                SideCordPluginDocumentLayoutSlot(
                    id: "player",
                    selectors: ["player-bar"]
                )
            ]
        )
        _ = try await controller.webView.evaluateJavaScript(
            PluginWebPanelController.layoutInjectionSource(layouts: [layout])
        )

        try await waitForJavaScriptTrue(
            "document.querySelector('[data-sidecord-slot=content] > content-two') !== null",
            in: controller.webView
        )
        let state = try await controller.webView.evaluateJavaScript(
            "document.getElementById('sidecord-plugin-layout').dataset.sidecordWidth + ':' + document.getElementById('sidecord-plugin-layout').dataset.sidecordHeight"
        ) as? String
        XCTAssertEqual(state, "wide:standard")

        let clickCount = try await controller.webView.evaluateJavaScript(
            "document.getElementById('native-button').click(); window.nativeClickCount"
        ) as? Int
        XCTAssertEqual(clickCount, 1)

        _ = try await controller.webView.evaluateJavaScript(
            "const old = document.querySelector('content-two'); const replacement = document.createElement('content-two'); replacement.textContent = 'Replacement'; old.replaceWith(replacement);"
        )
        try await waitForJavaScriptTrue(
            "document.querySelector('[data-sidecord-slot=content] > content-two')?.textContent === 'Replacement'",
            in: controller.webView
        )
    }

    func testDocumentLayoutDoesNotReconnectStableSlotsForUnrelatedMutations() async throws {
        let controller = makeController()
        defer { controller.shutdown() }
        controller.webView.loadHTMLString(
            """
            <!doctype html><html><head><style>
            music-app, stable-content { display: block; width: 100px; height: 20px; }
            </style><script>
            window.stableConnections = 0;
            customElements.define('stable-content', class extends HTMLElement {
                connectedCallback() { window.stableConnections += 1; }
            });
            </script></head><body><music-app><stable-content>Stable</stable-content></music-app></body></html>
            """,
            baseURL: URL(string: "https://music.youtube.com/")
        )
        try await waitForJavaScriptTrue("document.querySelector('stable-content') !== null", in: controller.webView)
        let hostValue = try await controller.webView.evaluateJavaScript("location.hostname")
        let host = try XCTUnwrap(hostValue as? String)
        let layout = SideCordPluginDocumentLayout(
            host: host,
            mountSelector: "music-app",
            slots: [SideCordPluginDocumentLayoutSlot(id: "content", selectors: ["stable-content"])]
        )
        _ = try await controller.webView.evaluateJavaScript(
            PluginWebPanelController.layoutInjectionSource(layouts: [layout])
        )
        try await waitForJavaScriptTrue(
            "document.querySelector('[data-sidecord-slot=content] > stable-content') !== null",
            in: controller.webView
        )
        let connectionsAfterMountValue = try await controller.webView.evaluateJavaScript("window.stableConnections")
        let connectionsAfterMount = try XCTUnwrap(connectionsAfterMountValue as? Int)

        _ = try await controller.webView.evaluateJavaScript(
            "window.stableNode = document.querySelector('stable-content'); stableNode.style.display = 'none'; document.body.appendChild(document.createElement('aside')); void 0;"
        )
        try await Task.sleep(for: .milliseconds(100))
        let connectionsAfterMutationValue = try await controller.webView.evaluateJavaScript("window.stableConnections")
        let connectionsAfterMutation = try XCTUnwrap(connectionsAfterMutationValue as? Int)
        XCTAssertEqual(connectionsAfterMutation, connectionsAfterMount)
        let retainedStableNode = try await controller.webView.evaluateJavaScript(
            "document.querySelector('[data-sidecord-slot=content] > stable-content') === window.stableNode"
        ) as? Bool
        XCTAssertEqual(retainedStableNode, true)
    }

    func testBrowserProfilesAreStableAndIsolatedByPluginAndContribution() async throws {
        let suffix = UUID().uuidString.lowercased()
        let firstPluginIdentifier = "com.example.one-\(suffix)"
        let secondPluginIdentifier = "com.example.two-\(suffix)"
        let first = PluginWebPanelController.stableDataStoreIdentifier(
            pluginIdentifier: firstPluginIdentifier,
            contributionIdentifier: "player"
        )
        let repeated = PluginWebPanelController.stableDataStoreIdentifier(
            pluginIdentifier: firstPluginIdentifier,
            contributionIdentifier: "player"
        )
        let second = PluginWebPanelController.stableDataStoreIdentifier(
            pluginIdentifier: secondPluginIdentifier,
            contributionIdentifier: "player"
        )

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, second)

        do {
            let firstController = makeController(
                pluginIdentifier: firstPluginIdentifier,
                persistentWebsiteData: true
            )
            let secondController = makeController(
                pluginIdentifier: secondPluginIdentifier,
                persistentWebsiteData: true
            )
            XCTAssertEqual(firstController.websiteDataStore.identifier, first)
            XCTAssertEqual(secondController.websiteDataStore.identifier, second)
            XCTAssertFalse(firstController.websiteDataStore === secondController.websiteDataStore)
            firstController.shutdown()
            secondController.shutdown()
        }
        try? await removeDataStore(first)
        try? await removeDataStore(second)
    }

    func testConfigurationRequiresUserActionForMediaPlaybackAndHasNoMessageHandlers() {
        let controller = makeController()
        XCTAssertEqual(
            controller.webView.configuration.mediaTypesRequiringUserActionForPlayback,
            .all
        )
        XCTAssertTrue(
            controller.webView.configuration.userContentController.userScripts.isEmpty
        )
        controller.shutdown()
    }

    func testLayoutRuntimeIsNotMistakenForCSSThatStylesTheLayoutShell() throws {
        let layout = SideCordPluginDocumentLayout(
            host: "music.youtube.com",
            mountSelector: "ytmusic-app",
            slots: [
                SideCordPluginDocumentLayoutSlot(
                    id: "player",
                    selectors: ["ytmusic-player-bar"]
                )
            ]
        )
        let controller = makeController(
            customCSS: "#sidecord-plugin-layout { display: grid !important; }",
            documentLayouts: [layout]
        )
        let scripts = controller.webView.configuration.userContentController.userScripts

        XCTAssertEqual(scripts.count, 2)
        XCTAssertEqual(scripts.filter { $0.source.contains("sidecord-plugin-style") }.count, 1)
        XCTAssertEqual(
            scripts.filter { $0.source.contains("sidecord-document-layout-runtime-v1") }.count,
            1
        )
        controller.shutdown()
    }

    func testWebContentProcessCrashRecoversFromTheDeclaredInitialURL() {
        let controller = makeController()
        controller.recoverAfterWebContentProcessTermination()

        XCTAssertEqual(controller.recoveryCount, 1)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertEqual(controller.lastRequestedURL, controller.panel.initialURL)
        controller.shutdown()
    }

    func testBenignNavigationInterruptionsDoNotBecomePanelErrors() {
        XCTAssertTrue(PluginWebPanelController.isIgnorableNavigationError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        ))
        XCTAssertTrue(PluginWebPanelController.isIgnorableNavigationError(
            NSError(
                domain: "WebKitErrorDomain",
                code: 102
            )
        ))
        XCTAssertFalse(PluginWebPanelController.isIgnorableNavigationError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        ))
    }

    func testExternalUserClickedLinkUsesTheBrowserOpener() {
        var openedURLs: [URL] = []
        let controller = makeController { openedURLs.append($0) }
        let externalURL = URL(string: "https://example.com/help")!

        XCTAssertEqual(
            controller.handleTopLevelNavigation(to: externalURL, userInitiated: true),
            .openExternally
        )
        XCTAssertEqual(openedURLs, [externalURL])
        XCTAssertEqual(
            controller.handleTopLevelNavigation(to: externalURL, userInitiated: false),
            .cancel
        )
        XCTAssertEqual(openedURLs, [externalURL])
        controller.shutdown()
    }

    private func makeController(
        customCSS: String? = nil,
        pluginIdentifier: String = "com.example.music",
        persistentWebsiteData: Bool = false,
        documentLayouts: [SideCordPluginDocumentLayout] = [],
        externalURLOpener: @escaping @MainActor (URL) -> Void = { _ in }
    ) -> PluginWebPanelController {
        PluginWebPanelController(
            pluginIdentifier: pluginIdentifier,
            panel: SideCordPluginWebPanel(
                id: "player",
                name: "Player",
                placement: .bottom,
                initialURL: URL(string: "https://music.youtube.com/")!,
                allowedNavigationHosts: ["music.youtube.com"],
                preferredHeight: 190,
                minimumHeight: 140,
                maximumHeight: 300,
                userResizable: true,
                customCSS: customCSS,
                documentLayouts: documentLayouts
            ),
            permissions: SideCordPluginPermissions(
                networkHosts: ["music.youtube.com"],
                persistentWebsiteData: persistentWebsiteData
            ),
            automaticallyLoads: false,
            externalURLOpener: externalURLOpener
        )
    }

    private func waitForJavaScriptTrue(
        _ source: String,
        in webView: WKWebView
    ) async throws {
        for _ in 0 ..< 80 {
            if try await webView.evaluateJavaScript(source) as? Bool == true {
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for JavaScript condition: \(source)")
    }

    private func removeDataStore(_ identifier: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            WKWebsiteDataStore.remove(forIdentifier: identifier) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

final class PluginWebPanelLayoutTests: XCTestCase {
    func testCombinedCardHeightNeverChangesTheOuterSidebarHeight() throws {
        let layout = try XCTUnwrap(PluginWebPanelLayout.resolve(
            totalHeight: 900,
            requestedHeight: 190,
            manifestMinimum: 140,
            manifestMaximum: 300
        ))

        XCTAssertEqual(layout.panelHeight, 190)
        XCTAssertEqual(layout.discordHeight + layout.gap + layout.panelHeight, 900)
    }

    func testHeightIsClampedByManifestAndHostLimits() throws {
        let low = try XCTUnwrap(PluginWebPanelLayout.resolve(
            totalHeight: 900,
            requestedHeight: 20,
            manifestMinimum: 140,
            manifestMaximum: 500
        ))
        let high = try XCTUnwrap(PluginWebPanelLayout.resolve(
            totalHeight: 900,
            requestedHeight: 900,
            manifestMinimum: 20,
            manifestMaximum: 500
        ))

        XCTAssertEqual(low.panelHeight, 140)
        XCTAssertEqual(high.panelHeight, 320)
    }

    func testHeightBoundsStayValidForManifestLimitsOutsideHostRange() throws {
        let belowHostRange = PluginWebPanelLayout.heightBounds(
            manifestMinimum: 20,
            manifestMaximum: 80
        )
        let aboveHostRange = PluginWebPanelLayout.heightBounds(
            manifestMinimum: 500,
            manifestMaximum: 600
        )

        XCTAssertEqual(belowHostRange, 120 ... 120)
        XCTAssertEqual(aboveHostRange, 320 ... 320)
        XCTAssertEqual(
            PluginWebPanelLayout.clampedRequestedHeight(
                300,
                manifestMinimum: 140,
                manifestMaximum: 200
            ),
            200
        )
    }

    func testTinyDisplaysPreserveMinimumDiscordHeightByHidingPanel() {
        XCTAssertNil(PluginWebPanelLayout.resolve(
            totalHeight: 420,
            requestedHeight: 190,
            manifestMinimum: 140,
            manifestMaximum: 300
        ))
    }
}

@MainActor
final class PluginWebPanelRuntimeTests: XCTestCase {
    func testDisablingTearsDownTheWebViewAndUpdatingPreservesProfileIdentity() async throws {
        let context = try makeContext()
        defer { context.cleanup() }
        var created: [PluginWebPanelController] = []
        let runtime = PluginWebPanelRuntime(
            pluginManager: context.manager,
            defaults: context.defaults,
            controllerFactory: { identifier, panel, permissions in
                let controller = PluginWebPanelController(
                    pluginIdentifier: identifier,
                    panel: panel,
                    permissions: permissions,
                    automaticallyLoads: false
                )
                created.append(controller)
                return controller
            }
        )
        let installed = try context.install(version: "1.0.0", name: "Music")
        context.manager.setEnabled(true, identifier: installed.id)
        try await Task.sleep(for: .milliseconds(80))

        var original: PluginWebPanelController? = try XCTUnwrap(runtime.activeBottomPanel)
        let profile = try XCTUnwrap(original).websiteDataStoreIdentifier
        _ = try context.install(version: "1.1.0", name: "Music Updated")
        try await Task.sleep(for: .milliseconds(80))

        var updated: PluginWebPanelController? = try XCTUnwrap(runtime.activeBottomPanel)
        XCTAssertFalse(original === updated)
        XCTAssertEqual(updated?.websiteDataStoreIdentifier, profile)

        context.manager.setEnabled(false, identifier: installed.id)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertNil(runtime.activeBottomPanel)
        XCTAssertEqual(runtime.activeControllerCount, 0)
        XCTAssertNil(updated?.webView.navigationDelegate)
        runtime.shutdown()
        created.removeAll()
        original = nil
        updated = nil
        try await removeDataStore(profile)
    }

    func testHiddenPanelKeepsControllerAndSessionAlive() async throws {
        let context = try makeContext()
        defer { context.cleanup() }
        let runtime = PluginWebPanelRuntime(
            pluginManager: context.manager,
            defaults: context.defaults,
            controllerFactory: { identifier, panel, permissions in
                PluginWebPanelController(
                    pluginIdentifier: identifier,
                    panel: panel,
                    permissions: permissions,
                    automaticallyLoads: false
                )
            }
        )
        let installed = try context.install(version: "1.0.0", name: "Music")
        context.manager.setEnabled(true, identifier: installed.id)
        try await Task.sleep(for: .milliseconds(80))
        let panel = try XCTUnwrap(installed.manifest.contributions.webPanels.first)

        var controller: PluginWebPanelController? = try XCTUnwrap(runtime.activeBottomPanel)
        runtime.sidebarDidReveal()
        runtime.setVisible(
            false,
            pluginIdentifier: installed.id,
            contributionIdentifier: panel.id
        )

        XCTAssertNil(runtime.activeBottomPanel)
        XCTAssertEqual(runtime.activeControllerCount, 1)
        XCTAssertEqual(controller?.playbackPauseRequestCount, 1)
        runtime.shutdown()
        controller = nil
        try await removeDataStore(
            PluginWebPanelController.stableDataStoreIdentifier(
                pluginIdentifier: installed.id,
                contributionIdentifier: panel.id
            )
        )
    }

    private func makeContext() throws -> RuntimeTestContext {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "PluginWebPanelRuntimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let manager = SideCordPluginManager(
            rootURL: root,
            defaults: defaults,
            marketplaceConfiguration: nil
        )
        return RuntimeTestContext(root: root, suite: suite, defaults: defaults, manager: manager)
    }

    private func removeDataStore(_ identifier: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            WKWebsiteDataStore.remove(forIdentifier: identifier) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

@MainActor
private struct RuntimeTestContext {
    let root: URL
    let suite: String
    let defaults: UserDefaults
    let manager: SideCordPluginManager

    func install(version: String, name: String) throws -> InstalledSideCordPlugin {
        let panel = SideCordPluginWebPanel(
            id: "player",
            name: name,
            placement: .bottom,
            initialURL: URL(string: "https://music.youtube.com/")!,
            allowedNavigationHosts: ["music.youtube.com"],
            preferredHeight: 190,
            minimumHeight: 140,
            maximumHeight: 300,
            userResizable: true,
            customCSS: nil
        )
        let package = SideCordPluginPackage(manifest: SideCordPluginManifest(
            schemaVersion: 2,
            identifier: "com.example.music",
            name: name,
            version: version,
            author: "SideCord Tests",
            description: "A test web panel.",
            minimumSideCordVersion: "2.3.0",
            capabilities: [.webPanel],
            permissions: SideCordPluginPermissions(
                networkHosts: ["music.youtube.com"],
                persistentWebsiteData: true,
                backgroundAudio: true
            ),
            contributions: SideCordPluginContributions(webPanels: [panel])
        ))
        return try manager.install(data: JSONEncoder().encode(package), source: .local)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}
