import XCTest
@testable import SideCord

final class WebCSSComposerTests: XCTestCase {
    func testTrustedSheetsAndCustomCSSHaveDeterministicPrecedence() {
        let result = DiscordCSSComposer.compose(
            preset: .compact,
            compactPresetCSS: "  .compact {}  ",
            layoutModifiersCSS: "  .layout {}  ",
            visualThemesCSS: "  .theme {}  ",
            layoutOptions: .focus,
            customCSS: "  .custom {}  ",
            customCSSEnabled: true
        )

        XCTAssertEqual(
            result,
            ".compact {}\n\n.layout {}\n\n.theme {}\n\n.custom {}"
        )
    }

    func testStandardWithoutAnySheetsOrCustomCSSProducesNoStyles() {
        XCTAssertEqual(
            DiscordCSSComposer.compose(
                preset: .standard,
                compactPresetCSS: ".compact {}",
                customCSS: ".custom {}",
                customCSSEnabled: false
            ),
            ""
        )
    }

    func testRuntimeConfigurationMapsLayoutAndAppearanceToStableRootState() {
        let options = DiscordLayoutOptions(
            navigationPresentation: .floating,
            composerMode: .essential,
            hideMemberList: true,
            hideAccountDock: true,
            simplifyHeader: true,
            compactMedia: true,
            reduceMotion: true
        )

        let configuration = DiscordCSSComposer.runtimeConfiguration(
            layoutOptions: options,
            visualTheme: .systemGlass,
            themeAccent: .pink,
            themeIntensity: 0.625,
            themeColorScheme: .dark
        )

        XCTAssertEqual(configuration.navigationPresentation, "floating")
        XCTAssertEqual(configuration.composerMode, "essential")
        XCTAssertEqual(configuration.requestedColorScheme, "dark")
        XCTAssertEqual(configuration.rootAttributes["data-sidecord-navigation"], "floating")
        XCTAssertEqual(configuration.rootAttributes["data-sidecord-composer"], "essential")
        XCTAssertEqual(configuration.rootAttributes["data-sidecord-theme"], "system-glass")
        XCTAssertEqual(configuration.rootAttributes["data-sidecord-accent"], "pink")
        XCTAssertEqual(configuration.rootAttributes["data-sidecord-color-scheme"], "dark")
        XCTAssertEqual(configuration.rootAttributes["data-sidecord-hide-members"], "")
        XCTAssertEqual(configuration.rootAttributes["data-sidecord-hide-account-dock"], "")
        XCTAssertEqual(configuration.rootAttributes["data-sidecord-simplify-header"], "")
        XCTAssertEqual(configuration.rootAttributes["data-sidecord-compact-media"], "")
        XCTAssertEqual(configuration.rootAttributes["data-sidecord-reduce-motion"], "")
        XCTAssertEqual(configuration.rootVariables["--sidecord-theme-intensity"], "0.625")
        XCTAssertEqual(configuration.rootVariables["--sidecord-theme-strength"], "62.500%")
        XCTAssertEqual(configuration.rootVariables["--sidecord-accent-color"], "#ff2d55")
    }

    func testRuntimeConfigurationClampsThemeIntensityAndUsesModelFallback() {
        let high = configuration(intensity: 4)
        let low = configuration(intensity: -2)
        let invalid = configuration(intensity: .nan)

        XCTAssertEqual(high.rootVariables["--sidecord-theme-intensity"], "1.000")
        XCTAssertEqual(low.rootVariables["--sidecord-theme-intensity"], "0.000")
        XCTAssertEqual(invalid.rootVariables["--sidecord-theme-intensity"], "1.000")
    }

    func testEveryCuratedEnumCaseMapsWithoutLeakingSwiftCaseNames() {
        XCTAssertEqual(
            Set(DiscordNavigationPresentation.allCases.map {
                configuration(navigation: $0).navigationPresentation
            }),
            ["docked", "floating", "hidden"]
        )
        XCTAssertEqual(
            Set(DiscordComposerMode.allCases.map {
                configuration(composer: $0).composerMode
            }),
            ["full", "essential", "hidden"]
        )
        XCTAssertEqual(
            Set(DiscordVisualTheme.allCases.compactMap {
                configuration(theme: $0).rootAttributes["data-sidecord-theme"]
            }),
            ["system-glass", "discord", "oled", "soft"]
        )
    }

    func testUserScriptInstallsUpdateableDrawerRailBridgeAndSelfHealingRuntime() {
        let script = DiscordCSSComposer.userScriptSource(
            css: ".focused {}",
            configuration: configuration(navigation: .floating, composer: .essential)
        )

        XCTAssertTrue(script.contains(DiscordCSSComposer.runtimeKey))
        XCTAssertTrue(script.contains("previousRuntime.update(nextCSS, nextConfiguration)"))
        XCTAssertTrue(script.contains("previousRuntime.version === 7"))
        XCTAssertTrue(script.contains("synchronizeDiscordTheme"))
        XCTAssertTrue(script.contains("synchronizeThemeScopes"))
        XCTAssertTrue(script.contains("clearThemeScopes"))
        XCTAssertFalse(script.contains("classList.toggle(\"theme-dark\""))
        XCTAssertTrue(script.contains("new MutationObserver"))
        XCTAssertTrue(script.contains("queueMicrotask"))
        XCTAssertTrue(script.contains("reconcileScheduled"))
        XCTAssertTrue(script.contains("requestAnimationFrame"))
        XCTAssertTrue(script.contains("setTimeout(run, 50)"))
        XCTAssertTrue(script.contains("new ResizeObserver"))
        XCTAssertTrue(script.contains("state.openDrawer"))
        XCTAssertTrue(script.contains("state.closeDrawer"))
        XCTAssertTrue(script.contains("state.toggleDrawer"))
        XCTAssertTrue(script.contains("document.addEventListener(\"pointerdown\""))
        XCTAssertTrue(script.contains("document.addEventListener(\"keydown\""))
        XCTAssertTrue(script.contains(DiscordCSSComposer.messageHandlerName))
        XCTAssertTrue(script.contains("reportDrawerState(false)"))
        XCTAssertTrue(script.contains("scheduleRailReport"))
        XCTAssertTrue(script.contains("state.activateRailItem"))
        XCTAssertTrue(script.contains("attributeFilter"))
        XCTAssertTrue(script.contains("reconcileDiscordDOM"))
        XCTAssertTrue(script.contains("style.textContent !== state.css"))
        XCTAssertFalse(script.contains("cloneNode"))
        XCTAssertFalse(script.contains("stopPropagation"))
        XCTAssertFalse(script.contains("preventDefault"))
    }

    func testNotificationBridgeCoversPageAndServiceWorkerNotifications() {
        let script = DiscordCSSComposer.notificationBridgeUserScriptSource()

        XCTAssertTrue(script.contains("new Proxy(NotificationTarget"))
        XCTAssertTrue(script.contains("getRegistrations"))
        XCTAssertTrue(script.contains("getNotifications"))
        XCTAssertTrue(script.contains("knownServiceWorkerNotificationsByScope"))
        XCTAssertTrue(script.contains("usesVirtualPermission"))
        XCTAssertTrue(script.contains("previousBridge.repair?.()"))
        XCTAssertTrue(script.contains("bridge.repair?.()"))
        XCTAssertTrue(script.contains("capturesPageNotifications"))
        XCTAssertTrue(script.contains("capturesNotificationSounds"))
        XCTAssertTrue(script.contains("HTMLMediaElement"))
        XCTAssertTrue(script.contains("webpackChunkdiscord_app"))
        XCTAssertTrue(script.contains("./message1.mp3"))
        XCTAssertTrue(script.contains("./mention1.mp3"))
        XCTAssertTrue(script.contains(#"type: "notification""#))
        XCTAssertFalse(script.contains("notification.title"))
        XCTAssertFalse(script.contains("notification.body"))

        let disabledScript = DiscordCSSComposer.notificationBridgeUserScriptSource(
            isEnabled: false
        )
        XCTAssertTrue(disabledScript.contains("const nextEnabled = false"))
    }

    func testRuntimeActionsAreAllowListed() {
        XCTAssertTrue(
            DiscordCSSComposer.runtimeActionSource("toggleDrawer")
                .contains("toggleDrawer")
        )
        XCTAssertEqual(
            DiscordCSSComposer.runtimeActionSource("arbitrary();alert(1)"),
            "false;"
        )
        XCTAssertTrue(
            DiscordCSSComposer.railActivationSource(id: "server:123")
                .contains("server:123")
        )
        XCTAssertEqual(
            DiscordCSSComposer.railActivationSource(id: "');alert(1)//"),
            "false;"
        )
    }

    func testIncomingCallActionsAreNarrowlyAllowListed() {
        let answer = DiscordCSSComposer.incomingCallActionSource("answer")
        let decline = DiscordCSSComposer.incomingCallActionSource("decline")

        XCTAssertTrue(answer.contains("answerIncomingCall"))
        XCTAssertTrue(decline.contains("declineIncomingCall"))
        XCTAssertEqual(DiscordCSSComposer.incomingCallActionSource("clickAnything"), "false;")
    }

    func testWhiteAccentMapsToStableCSSValues() {
        let configuration = DiscordCSSComposer.runtimeConfiguration(
            layoutOptions: .full,
            visualTheme: .systemGlass,
            themeAccent: .white,
            themeIntensity: 1,
            themeColorScheme: .dark
        )
        XCTAssertEqual(configuration.rootVariables["--sidecord-accent-color"], "#ffffff")
        XCTAssertEqual(configuration.rootVariables["--sidecord-accent-rgb"], "255 255 255")
    }

    func testCustomCSSRejectsNetworkLoadingPrimitives() {
        let unsafeCSS = """
        @import "https://example.com/theme.css" screen;
        .avatar { background: URL(https://example.com/pixel.png); }
        .safe { color: rebeccapurple; }
        """

        XCTAssertEqual(
            DiscordCSSComposer.sanitizeCustomCSS(unsafeCSS),
            "/* SideCord blocked custom CSS containing network-capable syntax. */"
        )
    }

    func testSafeSelectorContainingURLLettersIsAllowed() {
        let css = ".curl-indicator { color: rebeccapurple; }"
        XCTAssertNil(DiscordCSSComposer.validationError(for: css))
        XCTAssertEqual(DiscordCSSComposer.sanitizeCustomCSS(css), css)
    }

    func testUserScriptUsesJSONEncodingAndDiscordHostGuard() {
        let css = "body::after { content: \"</style>\\n'${danger}\"; }"
        let script = DiscordCSSComposer.userScriptSource(
            css: css,
            configuration: configuration()
        )

        XCTAssertTrue(script.contains("discord.com"))
        XCTAssertTrue(script.contains("discordapp.com"))
        XCTAssertTrue(script.contains(DiscordCSSComposer.styleElementID))
        XCTAssertFalse(script.contains("const nextCSS = \(css);"))
    }

    func testSettingsBridgeIsUpdateableScopedAndOpenable() {
        let snapshot = SideCordSettingsSnapshot(
            sidebarEdge: "right",
            edgeHoverEnabled: true,
            sidebarWidth: 420,
            sidebarInset: 16,
            discordLayoutMode: "full",
            floatingRailEnabled: true,
            visualTheme: "systemGlass",
            themeAccent: "white",
            themeIntensity: 0.8,
            themeColorScheme: "system",
            notificationGlowEnabled: true,
            attentionGlowColor: "white",
            attentionGlowStrength: "normal",
            incomingCallCardEnabled: true,
            pluginsInstalled: 2,
            pluginsEnabled: 1
        )
        let script = DiscordCSSComposer.settingsBridgeUserScriptSource(snapshot: snapshot)

        XCTAssertTrue(script.contains(DiscordCSSComposer.settingsBridgeKey))
        XCTAssertTrue(script.contains("previous.update(nextSnapshot)"))
        XCTAssertTrue(script.contains("data-sidecord-settings-nav"))
        XCTAssertTrue(script.contains("data-sidecord-settings-page"))
        XCTAssertTrue(script.contains(#"type: "settingsSet""#))
        XCTAssertTrue(script.contains(#"type: "settingsHealth""#))
        XCTAssertTrue(script.contains("White"))
        XCTAssertTrue(DiscordCSSComposer.openSideCordSettingsSource().contains("bridge.open()"))
    }

    private func configuration(
        navigation: DiscordNavigationPresentation = .docked,
        composer: DiscordComposerMode = .full,
        theme: DiscordVisualTheme = .discord,
        intensity: Double = 1
    ) -> DiscordCSSRuntimeConfiguration {
        DiscordCSSComposer.runtimeConfiguration(
            layoutOptions: DiscordLayoutOptions(
                navigationPresentation: navigation,
                composerMode: composer
            ),
            visualTheme: theme,
            themeAccent: .automatic,
            themeIntensity: intensity,
            themeColorScheme: .system
        )
    }
}
