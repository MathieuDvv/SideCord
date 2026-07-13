import WebKit
import XCTest
@testable import SideCord

@MainActor
final class WebCSSRuntimeTests: XCTestCase {
    func testFloatingRailBridgeUsesLiveDiscordNodesAndSurvivesRerenders() async throws {
        let recorder = RuntimeMessageRecorder()
        let (webView, navigationWaiter) = try await loadFixture(messageRecorder: recorder)
        _ = navigationWaiter
        let configuration = makeConfiguration(
            navigation: .floating,
            composer: .essential,
            theme: .soft,
            accent: .pink,
            intensity: 0.7,
            colorScheme: .dark
        )
        let source = DiscordCSSComposer.userScriptSource(
            css: try runtimeCSS(customCSS: ""),
            configuration: configuration
        )

        _ = try await webView.evaluateJavaScript(source)
        try await waitForRuntime()

        let initialState = try await webView.evaluateJavaScript(
            """
            ({
              guildRole: document.getElementById('guilds').dataset.sidecordRole,
              channelRole: document.getElementById('channels').dataset.sidecordRole,
              accountRole: document.getElementById('account').dataset.sidecordRole,
              originalGuildCount: document.querySelectorAll('#guilds').length,
              guildDisplay: getComputedStyle(document.getElementById('guilds')).display,
              messageLeft: document.getElementById('messages').getBoundingClientRect().left,
              navigationLayoutCount: document.querySelectorAll(
                '[data-sidecord-role="navigation-layout"], ' +
                '[data-sidecord-role="main-surface"], ' +
                '[data-sidecord-navigation-ancestor]'
              ).length,
              navigation: document.documentElement.dataset.sidecordNavigation,
              theme: document.documentElement.dataset.sidecordTheme,
              accent: document.documentElement.dataset.sidecordAccent,
              scheme: document.documentElement.dataset.sidecordResolvedColorScheme,
              intensity: document.documentElement.style.getPropertyValue('--sidecord-theme-intensity')
            })
            """
        ) as! [String: Any]
        XCTAssertEqual(initialState["guildRole"] as? String, "guild-rail")
        XCTAssertEqual(initialState["channelRole"] as? String, "channel-list")
        XCTAssertEqual(initialState["accountRole"] as? String, "account-dock")
        XCTAssertEqual(initialState["originalGuildCount"] as? Int, 1)
        XCTAssertEqual(initialState["guildDisplay"] as? String, "none")
        XCTAssertEqual(initialState["messageLeft"] as! Double, 0, accuracy: 0.5)
        XCTAssertEqual(initialState["navigationLayoutCount"] as? Int, 0)
        XCTAssertEqual(initialState["navigation"] as? String, "floating")
        XCTAssertEqual(initialState["theme"] as? String, "soft")
        XCTAssertEqual(initialState["accent"] as? String, "pink")
        XCTAssertEqual(initialState["scheme"] as? String, "dark")
        XCTAssertEqual(initialState["intensity"] as? String, "0.700")

        let initialRailItems = try XCTUnwrap(recorder.latestRailItems)
        XCTAssertEqual(initialRailItems.count, 3)
        XCTAssertEqual(initialRailItems[0]["id"] as? String, "direct-messages")
        XCTAssertEqual(initialRailItems[0]["kind"] as? String, "directMessages")
        XCTAssertEqual(initialRailItems[1]["id"] as? String, "server:1")
        XCTAssertEqual(initialRailItems[1]["title"] as? String, "Fixture Server")
        XCTAssertEqual(initialRailItems[1]["selected"] as? Bool, true)
        XCTAssertEqual(initialRailItems[1]["unread"] as? Bool, true)
        XCTAssertEqual(initialRailItems[1]["mentions"] as? Int, 3)
        XCTAssertEqual(initialRailItems[2]["id"] as? String, "action:create-server")

        let drawerGeometryIsReserved = try await webView.evaluateJavaScript(
            """
            (() => {
              const channels = document.getElementById('channels').getBoundingClientRect();
              const account = document.getElementById('account').getBoundingClientRect();
              return channels.bottom <= account.top;
            })()
            """
        ) as! Bool
        XCTAssertTrue(drawerGeometryIsReserved)

        let activationResult = try await webView.evaluateJavaScript(
            DiscordCSSComposer.railActivationSource(id: "server:1")
        ) as! Bool
        XCTAssertTrue(activationResult)
        try await waitForRuntime()
        var drawerOpen = try await drawerIsOpen(in: webView)
        XCTAssertTrue(drawerOpen)
        let activationCount = try await webView.evaluateJavaScript(
            "window.fixtureServerActivationCount"
        ) as! Int
        XCTAssertEqual(activationCount, 1)

        let drawerGeometry = try await webView.evaluateJavaScript(
            "document.getElementById('channels').getBoundingClientRect().left"
        ) as! Double
        XCTAssertEqual(drawerGeometry, 12, accuracy: 0.5)

        _ = try await webView.evaluateJavaScript("document.getElementById('channel').click()")
        try await waitForRuntime()
        drawerOpen = try await drawerIsOpen(in: webView)
        XCTAssertFalse(drawerOpen)

        _ = try await webView.evaluateJavaScript("document.getElementById('add-server').click()")
        try await waitForRuntime()
        drawerOpen = try await drawerIsOpen(in: webView)
        XCTAssertFalse(drawerOpen)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.runtimeActionSource("openDrawer")
        )
        drawerOpen = try await drawerIsOpen(in: webView)
        XCTAssertTrue(drawerOpen)
        _ = try await webView.evaluateJavaScript(
            """
            document.getElementById('messages').dispatchEvent(
              new PointerEvent('pointerdown', { bubbles: true })
            )
            """
        )
        drawerOpen = try await drawerIsOpen(in: webView)
        XCTAssertFalse(drawerOpen)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.runtimeActionSource("openDrawer")
        )
        _ = try await webView.evaluateJavaScript(
            "document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))"
        )
        drawerOpen = try await drawerIsOpen(in: webView)
        XCTAssertFalse(drawerOpen)

        _ = try await webView.evaluateJavaScript(
            """
            document.getElementById('guilds').outerHTML = `
              <nav id="guilds-v2" class="guilds_rerendered">
                <a id="server-v2" href="/channels/2/20"
                   data-list-item-id="guildsnav___2"
                   aria-label="Server two">Server two</a>
              </nav>`;
            document.getElementById('channels').outerHTML = `
              <nav id="channels-v2" class="sidebarList_rerendered">
                <a id="channel-v2" href="#/channels/2/21">Channel two</a>
              </nav>`;
            """
        )
        try await waitForRuntime()

        let rerendered = try await webView.evaluateJavaScript(
            """
            document.getElementById('guilds-v2').dataset.sidecordRole === 'guild-rail' &&
            document.getElementById('channels-v2').dataset.sidecordRole === 'channel-list' &&
            !document.getElementById('guilds') && !document.getElementById('channels')
            """
        ) as! Bool
        XCTAssertTrue(rerendered)
        XCTAssertEqual(recorder.latestRailItems?.count, 1)
        XCTAssertEqual(recorder.latestRailItems?.first?["id"] as? String, "server:2")
        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.railActivationSource(id: "server:2")
        )
        try await waitForRuntime()
        drawerOpen = try await drawerIsOpen(in: webView)
        XCTAssertTrue(drawerOpen)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.userScriptSource(
                css: try runtimeCSS(customCSS: ""),
                configuration: makeConfiguration(navigation: .hidden, composer: .essential)
            )
        )
        try await waitForRuntime()
        let modeChangeClosedDrawer = try await webView.evaluateJavaScript(
            """
            document.documentElement.dataset.sidecordNavigation === 'hidden' &&
            !document.documentElement.hasAttribute('data-sidecord-drawer-open')
            """
        ) as! Bool
        XCTAssertTrue(modeChangeClosedDrawer)
    }

    func testComposerEssentialRetainsCoreControlsAndModeChangesInPlace() async throws {
        let (webView, navigationWaiter) = try await loadFixture()
        _ = navigationWaiter
        let essential = makeConfiguration(navigation: .floating, composer: .essential)
        let source = DiscordCSSComposer.userScriptSource(
            css: try runtimeCSS(customCSS: ""),
            configuration: essential
        )
        _ = try await webView.evaluateJavaScript(source)
        try await waitForRuntime()

        let essentialVisibility = try await controlVisibility(in: webView)
        XCTAssertNotEqual(essentialVisibility["attachment"], "none")
        XCTAssertNotEqual(essentialVisibility["gif"], "none")
        XCTAssertNotEqual(essentialVisibility["emoji"], "none")
        XCTAssertEqual(essentialVisibility["gift"], "none")
        XCTAssertEqual(essentialVisibility["sticker"], "none")
        XCTAssertEqual(essentialVisibility["apps"], "none")

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.userScriptSource(
                css: try runtimeCSS(customCSS: ""),
                configuration: makeConfiguration(navigation: .docked, composer: .full)
            )
        )
        try await waitForRuntime()

        let fullVisibility = try await controlVisibility(in: webView)
        for control in ["attachment", "gif", "emoji", "gift", "sticker", "apps"] {
            XCTAssertNotEqual(fullVisibility[control], "none", control)
        }
        let runtimeStillExists = try await webView.evaluateJavaScript(
            "window['\(DiscordCSSComposer.runtimeKey)']?.version === 3"
        ) as! Bool
        XCTAssertTrue(runtimeStillExists)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.userScriptSource(
                css: try runtimeCSS(customCSS: ""),
                configuration: makeConfiguration(navigation: .hidden, composer: .hidden)
            )
        )
        try await waitForRuntime()
        let hiddenState = try await webView.evaluateJavaScript(
            """
            ({
              guild: getComputedStyle(document.getElementById('guilds')).display,
              channels: getComputedStyle(document.getElementById('channels')).display,
              composer: getComputedStyle(document.getElementById('composer-form')).display,
              drawer: document.documentElement.hasAttribute('data-sidecord-drawer-open')
            })
            """
        ) as! [String: Any]
        XCTAssertEqual(hiddenState["guild"] as? String, "none")
        XCTAssertEqual(hiddenState["channels"] as? String, "none")
        XCTAssertEqual(hiddenState["composer"] as? String, "none")
        XCTAssertEqual(hiddenState["drawer"] as? Bool, false)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.runtimeActionSource("openDrawer")
        )
        try await waitForRuntime()
        let transientReveal = try await webView.evaluateJavaScript(
            """
            document.documentElement.dataset.sidecordNavigation === 'floating' &&
            document.documentElement.hasAttribute('data-sidecord-drawer-open') &&
            getComputedStyle(document.getElementById('guilds')).display === 'none' &&
            getComputedStyle(document.getElementById('channels')).display !== 'none'
            """
        ) as! Bool
        XCTAssertTrue(transientReveal)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.runtimeActionSource("closeDrawer")
        )
        try await waitForRuntime()
        let returnedToHidden = try await webView.evaluateJavaScript(
            """
            document.documentElement.dataset.sidecordNavigation === 'hidden' &&
            !document.documentElement.hasAttribute('data-sidecord-drawer-open')
            """
        ) as! Bool
        XCTAssertTrue(returnedToHidden)
    }

    func testThemeStateSelfHealsAndCustomCSSIsLast() async throws {
        let (webView, navigationWaiter) = try await loadFixture()
        _ = navigationWaiter
        let customCSS = "body { --sidecord-precedence-check: custom; }"
        let css = try runtimeCSS(customCSS: customCSS)
        XCTAssertTrue(css.hasSuffix(customCSS))

        let source = DiscordCSSComposer.userScriptSource(
            css: css,
            configuration: makeConfiguration(
                navigation: .docked,
                composer: .full,
                theme: .oled,
                accent: .green,
                intensity: 0.45,
                colorScheme: .light
            )
        )
        _ = try await webView.evaluateJavaScript(source)
        try await waitForRuntime()

        let initial = try await webView.evaluateJavaScript(
            """
            ({
              theme: document.documentElement.dataset.sidecordTheme,
              accent: document.documentElement.dataset.sidecordAccent,
              requested: document.documentElement.dataset.sidecordColorScheme,
              resolved: document.documentElement.dataset.sidecordResolvedColorScheme,
              intensity: document.documentElement.style.getPropertyValue('--sidecord-theme-intensity'),
              strength: document.documentElement.style.getPropertyValue('--sidecord-theme-strength'),
              custom: getComputedStyle(document.body).getPropertyValue('--sidecord-precedence-check').trim()
            })
            """
        ) as! [String: Any]
        XCTAssertEqual(initial["theme"] as? String, "oled")
        XCTAssertEqual(initial["accent"] as? String, "green")
        XCTAssertEqual(initial["requested"] as? String, "light")
        XCTAssertEqual(initial["resolved"] as? String, "light")
        XCTAssertEqual(initial["intensity"] as? String, "0.450")
        XCTAssertEqual(initial["strength"] as? String, "45.000%")
        XCTAssertEqual(initial["custom"] as? String, "custom")

        _ = try await webView.evaluateJavaScript(
            """
            document.documentElement.removeAttribute('data-sidecord-theme');
            document.documentElement.style.removeProperty('--sidecord-theme-intensity');
            document.getElementById('\(DiscordCSSComposer.styleElementID)').remove();
            """
        )
        try await waitForRuntime()

        let repaired = try await webView.evaluateJavaScript(
            """
            document.documentElement.dataset.sidecordTheme === 'oled' &&
            document.documentElement.style.getPropertyValue('--sidecord-theme-intensity') === '0.450' &&
            !!document.getElementById('\(DiscordCSSComposer.styleElementID)')
            """
        ) as! Bool
        XCTAssertTrue(repaired)
    }

    func testVisualThemeSheetContainsNoLayoutOrVisibilityDeclarations() throws {
        let css = try resource(named: "visual-themes")
        let forbiddenDeclaration = #"(?im)^\s*(display|position|top|right|bottom|left|inset|width|min-width|max-width|height|min-height|max-height|margin|padding|transform|visibility|overflow|pointer-events|z-index)\s*:"#
        XCTAssertNil(css.range(of: forbiddenDeclaration, options: .regularExpression))
        XCTAssertTrue(css.contains("data-sidecord-resolved-color-scheme=\"dark\""))
        XCTAssertTrue(css.contains("data-sidecord-resolved-color-scheme=\"light\""))
        XCTAssertTrue(css.contains("data-sidecord-theme=\"discord\"][data-sidecord-color-scheme=\"dark\"]"))
        XCTAssertTrue(css.contains("data-sidecord-theme=\"discord\"][data-sidecord-color-scheme=\"light\"]"))
        XCTAssertFalse(css.contains("data-sidecord-theme=\"discord\"][data-sidecord-color-scheme=\"system\"]"))
        XCTAssertTrue(css.contains("--text-normal:"))
        XCTAssertTrue(css.contains("--interactive-normal:"))
        XCTAssertTrue(css.contains("--channels-default:"))
        XCTAssertTrue(css.contains("--background-primary:"))
        XCTAssertTrue(css.contains("--channeltextarea-background:"))
    }

    private func makeConfiguration(
        navigation: DiscordNavigationPresentation,
        composer: DiscordComposerMode,
        theme: DiscordVisualTheme = .discord,
        accent: SideCordAccent = .automatic,
        intensity: Double = 1,
        colorScheme: ThemeColorScheme = .system
    ) -> DiscordCSSRuntimeConfiguration {
        DiscordCSSComposer.runtimeConfiguration(
            layoutOptions: DiscordLayoutOptions(
                navigationPresentation: navigation,
                composerMode: composer
            ),
            visualTheme: theme,
            themeAccent: accent,
            themeIntensity: intensity,
            themeColorScheme: colorScheme
        )
    }

    private func runtimeCSS(customCSS: String) throws -> String {
        DiscordCSSComposer.compose(
            preset: .standard,
            compactPresetCSS: "",
            layoutModifiersCSS: try resource(named: "layout-mods"),
            visualThemesCSS: try resource(named: "visual-themes"),
            layoutOptions: .focus,
            customCSS: customCSS,
            customCSSEnabled: !customCSS.isEmpty
        )
    }

    private func resource(named name: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("SideCord/Resources/\(name).css"),
            encoding: .utf8
        )
    }

    private func loadFixture(
        messageRecorder: RuntimeMessageRecorder? = nil
    ) async throws -> (WKWebView, RuntimeNavigationWaiter) {
        let configuration = WKWebViewConfiguration()
        if let messageRecorder {
            configuration.userContentController.add(
                messageRecorder,
                name: DiscordCSSComposer.messageHandlerName
            )
        }
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 700),
            configuration: configuration
        )
        let loaded = expectation(description: "Local Discord fixture loaded")
        let navigationWaiter = RuntimeNavigationWaiter { loaded.fulfill() }
        webView.navigationDelegate = navigationWaiter
        webView.loadHTMLString(Self.fixtureHTML, baseURL: URL(string: "https://discord.com/app")!)
        await fulfillment(of: [loaded], timeout: 5)
        return (webView, navigationWaiter)
    }

    private func drawerIsOpen(in webView: WKWebView) async throws -> Bool {
        try await webView.evaluateJavaScript(
            "document.documentElement.hasAttribute('data-sidecord-drawer-open')"
        ) as! Bool
    }

    private func controlVisibility(in webView: WKWebView) async throws -> [String: String] {
        try await webView.evaluateJavaScript(
            """
            Object.fromEntries(
              ['attachment', 'gif', 'emoji', 'gift', 'sticker', 'apps'].map(id =>
                [id, getComputedStyle(document.getElementById(id)).display]
              )
            )
            """
        ) as! [String: String]
    }

    private func waitForRuntime() async throws {
        try await Task.sleep(for: .milliseconds(120))
    }

    private static let fixtureHTML = """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <style>
          html, body { margin: 0; width: 100%; height: 100%; }
          #app-mount { display: flex; width: 100%; height: 100%; }
          #sidebar {
            display: flex;
            flex: 0 0 0;
            min-width: 0;
            height: 420px;
            overflow: hidden;
            transform: translate3d(0, 0, 0);
          }
          #guilds { flex: 0 0 72px; }
          #channels { flex: 0 0 240px; }
          #messages { flex: 1 1 auto; min-width: 0; }
        </style>
      </head>
      <body>
        <div id="app-mount">
          <aside id="sidebar">
            <nav id="guilds" class="guilds_fixture">
              <a id="home" href="/channels/@me"
                 data-list-item-id="guildsnav___home"
                 aria-label="Direct Messages">
                <img alt="Direct Messages"
                     src="data:image/png;base64,iVBORw0KGgo=">
              </a>
              <a id="server" href="/channels/1/10"
                 data-list-item-id="guildsnav___1"
                 aria-label="Fixture Server"
                 aria-selected="true"
                 class="selected_fixture unread_fixture">
                <img alt="Fixture Server"
                     src="https://cdn.discordapp.com/icons/1/example.png">
                <span class="numberBadge_fixture">3</span>
              </a>
              <button id="add-server" data-list-item-id="guildsnav___create-join-button">
                Add server
              </button>
            </nav>
            <nav id="channels" class="sidebarList_fixture">
              <a id="channel" href="#/channels/1/11">Channel</a>
            </nav>
            <section id="account" class="panels_fixture">Account and voice</section>
          </aside>
          <main id="messages">
            <form id="composer-form" class="form_fixture">
              <div id="composer" class="channelTextArea_fixture">
                <button id="attachment" aria-label="Upload a file">+</button>
                <button id="gif" aria-label="Open GIF picker">GIF</button>
                <button id="emoji" aria-label="Select emoji">Emoji</button>
                <button id="gift" aria-label="Send a gift">Gift</button>
                <button id="sticker" aria-label="Open sticker picker">Sticker</button>
                <div id="apps" class="channelAppLauncher_fixture">Apps</div>
              </div>
            </form>
          </main>
        </div>
        <script>
          window.fixtureServerActivationCount = 0;
          document.addEventListener('click', event => {
            if (event.target.closest('a')) event.preventDefault();
            if (event.target.closest('#server')) window.fixtureServerActivationCount += 1;
          });
        </script>
      </body>
    </html>
    """
}

@MainActor
private final class RuntimeMessageRecorder: NSObject, WKScriptMessageHandler {
    private(set) var messages: [[String: Any]] = []

    var latestRailItems: [[String: Any]]? {
        messages.reversed().first(where: { $0["type"] as? String == "rail" })?["items"]
            as? [[String: Any]]
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == DiscordCSSComposer.messageHandlerName,
              message.frameInfo.isMainFrame,
              let payload = message.body as? [String: Any]
        else { return }
        messages.append(payload)
    }
}

@MainActor
private final class RuntimeNavigationWaiter: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish()
    }
}
