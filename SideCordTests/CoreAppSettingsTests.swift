import Carbon.HIToolbox
import XCTest
@testable import SideCord

final class CoreAppSettingsTests: XCTestCase {
    @MainActor
    func testDefaults() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.sidebarEdge, .right)
        XCTAssertTrue(settings.edgeHoverEnabled)
        XCTAssertTrue(settings.notificationGlowEnabled)
        XCTAssertEqual(settings.attentionGlowColor, .followTheme)
        XCTAssertEqual(settings.attentionGlowStrength, .normal)
        XCTAssertTrue(settings.incomingCallCardEnabled)
        XCTAssertEqual(settings.hoverDwellDelay, 0.25, accuracy: 0.001)
        XCTAssertEqual(settings.retractionDelay, 0.7, accuracy: 0.001)
        XCTAssertEqual(settings.sidebarWidth, 420, accuracy: 0.001)
        XCTAssertEqual(settings.sidebarInset, 16, accuracy: 0.001)
        XCTAssertEqual(settings.cssPreset, .compact)
        XCTAssertEqual(settings.discordLayoutMode, .full)
        XCTAssertEqual(settings.discordLayoutOptions, .full)
        XCTAssertTrue(settings.floatingRailEnabled)
        XCTAssertEqual(settings.visualTheme, .systemGlass)
        XCTAssertEqual(settings.themeAccent, .automatic)
        XCTAssertEqual(settings.themeIntensity, 1, accuracy: 0.001)
        XCTAssertEqual(settings.themeColorScheme, .system)
        XCTAssertEqual(settings.customCSS, "")
        XCTAssertFalse(settings.customCSSEnabled)
        XCTAssertFalse(settings.launchAtLoginEnabled)
        XCTAssertEqual(settings.shortcut, .optionD)
        XCTAssertEqual(settings.navigationShortcut, .optionShiftD)
        XCTAssertFalse(settings.isPinned)
        XCTAssertEqual(settings.width(forDisplay: "main"), 420, accuracy: 0.001)
    }

    @MainActor
    func testChangesPersistAcrossInstances() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.sidebarEdge = .left
        settings.edgeHoverEnabled = false
        settings.notificationGlowEnabled = false
        settings.attentionGlowColor = .white
        settings.attentionGlowStrength = .strong
        settings.incomingCallCardEnabled = false
        settings.hoverDwellDelay = 0.4
        settings.retractionDelay = 1.2
        settings.sidebarWidth = 512
        settings.sidebarInset = 28
        settings.cssPreset = .standard
        settings.applyDiscordLayoutMode(.reader)
        settings.setDiscordLayoutOption(\.reduceMotion, enabled: true)
        settings.floatingRailEnabled = false
        settings.visualTheme = .soft
        settings.themeAccent = .pink
        settings.themeIntensity = 0.42
        settings.themeColorScheme = .dark
        settings.customCSS = "body { color: red; }"
        settings.customCSSEnabled = true
        settings.launchAtLoginEnabled = true
        settings.shortcut = ShortcutDefinition(
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        settings.navigationShortcut = ShortcutDefinition(
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: UInt32(cmdKey | optionKey)
        )
        settings.isPinned = true
        settings.setWidth(618, forDisplay: "display-1")

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.sidebarEdge, .left)
        XCTAssertFalse(restored.edgeHoverEnabled)
        XCTAssertFalse(restored.notificationGlowEnabled)
        XCTAssertEqual(restored.attentionGlowColor, .white)
        XCTAssertEqual(restored.attentionGlowStrength, .strong)
        XCTAssertFalse(restored.incomingCallCardEnabled)
        XCTAssertEqual(restored.hoverDwellDelay, 0.4, accuracy: 0.001)
        XCTAssertEqual(restored.retractionDelay, 1.2, accuracy: 0.001)
        XCTAssertEqual(restored.sidebarWidth, 512, accuracy: 0.001)
        XCTAssertEqual(restored.sidebarInset, 28, accuracy: 0.001)
        XCTAssertEqual(restored.cssPreset, .standard)
        XCTAssertEqual(restored.discordLayoutMode, .custom)
        XCTAssertEqual(restored.discordLayoutOptions.navigationPresentation, .hidden)
        XCTAssertEqual(restored.discordLayoutOptions.composerMode, .hidden)
        XCTAssertTrue(restored.discordLayoutOptions.reduceMotion)
        XCTAssertFalse(restored.floatingRailEnabled)
        XCTAssertEqual(restored.visualTheme, .soft)
        XCTAssertEqual(restored.themeAccent, .pink)
        XCTAssertEqual(restored.themeIntensity, 0.42, accuracy: 0.001)
        XCTAssertEqual(restored.themeColorScheme, .dark)
        XCTAssertEqual(restored.customCSS, "body { color: red; }")
        XCTAssertTrue(restored.customCSSEnabled)
        XCTAssertTrue(restored.launchAtLoginEnabled)
        XCTAssertEqual(restored.shortcut, settings.shortcut)
        XCTAssertEqual(restored.navigationShortcut, settings.navigationShortcut)
        XCTAssertTrue(restored.isPinned)
        XCTAssertEqual(restored.width(forDisplay: "display-1"), 618, accuracy: 0.001)
    }

    @MainActor
    func testValuesAreValidatedOnLoadAndMutation() {
        let defaults = makeDefaults()
        defaults.set(-4.0, forKey: "settings.hoverDwellDelay")
        defaults.set(999.0, forKey: "settings.retractionDelay")
        defaults.set(12.0, forKey: "settings.sidebarWidth")
        defaults.set(-12.0, forKey: "settings.sidebarInset")
        defaults.set("invalid", forKey: "settings.sidebarEdge")
        defaults.set("invalid", forKey: "settings.cssPreset")
        defaults.set("invalid", forKey: "settings.discordLayoutMode")
        defaults.set("invalid", forKey: "settings.visualTheme")
        defaults.set("invalid", forKey: "settings.themeAccent")
        defaults.set(20.0, forKey: "settings.themeIntensity")
        defaults.set("invalid", forKey: "settings.themeColorScheme")
        defaults.set(-1, forKey: "settings.shortcut.keyCode")
        defaults.set(Int(optionKey), forKey: "settings.shortcut.modifiers")
        defaults.set(999, forKey: "settings.navigationShortcut.keyCode")
        defaults.set(0, forKey: "settings.navigationShortcut.modifiers")

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.hoverDwellDelay, 0, accuracy: 0.001)
        XCTAssertEqual(settings.retractionDelay, 10, accuracy: 0.001)
        XCTAssertEqual(settings.sidebarWidth, AppSettings.minimumSidebarWidth, accuracy: 0.001)
        XCTAssertEqual(settings.sidebarInset, 0, accuracy: 0.001)
        XCTAssertEqual(settings.sidebarEdge, .right)
        XCTAssertEqual(settings.cssPreset, .compact)
        XCTAssertEqual(settings.discordLayoutMode, .full)
        XCTAssertEqual(settings.visualTheme, .systemGlass)
        XCTAssertEqual(settings.themeAccent, .automatic)
        XCTAssertEqual(settings.themeIntensity, 1, accuracy: 0.001)
        XCTAssertEqual(settings.themeColorScheme, .system)
        XCTAssertEqual(settings.shortcut, .optionD)
        XCTAssertEqual(settings.navigationShortcut, .optionShiftD)
        XCTAssertEqual(defaults.string(forKey: "settings.visualTheme"), "systemGlass")
        XCTAssertEqual(defaults.string(forKey: "settings.themeAccent"), "automatic")
        XCTAssertEqual(defaults.double(forKey: "settings.themeIntensity"), 1, accuracy: 0.001)
        XCTAssertEqual(defaults.string(forKey: "settings.themeColorScheme"), "system")
        XCTAssertEqual(
            defaults.integer(forKey: "settings.shortcut.keyCode"),
            Int(ShortcutDefinition.optionD.keyCode)
        )
        XCTAssertEqual(
            defaults.integer(forKey: "settings.shortcut.modifiers"),
            Int(ShortcutDefinition.optionD.modifiers)
        )

        settings.hoverDwellDelay = .infinity
        settings.retractionDelay = -.infinity
        settings.sidebarWidth = .nan
        settings.sidebarInset = 999
        XCTAssertEqual(settings.sidebarInset, 48, accuracy: 0.001)
        settings.sidebarInset = .infinity
        settings.themeIntensity = -5
        XCTAssertEqual(settings.themeIntensity, 0, accuracy: 0.001)
        settings.themeIntensity = .infinity
        settings.shortcut = ShortcutDefinition(keyCode: 1, modifiers: 0)
        settings.navigationShortcut = ShortcutDefinition(keyCode: 1, modifiers: 0)

        XCTAssertEqual(settings.hoverDwellDelay, AppSettings.defaultHoverDwellDelay, accuracy: 0.001)
        XCTAssertEqual(settings.retractionDelay, AppSettings.defaultRetractionDelay, accuracy: 0.001)
        XCTAssertEqual(settings.sidebarWidth, AppSettings.defaultSidebarWidth, accuracy: 0.001)
        XCTAssertEqual(settings.sidebarInset, AppSettings.defaultSidebarInset, accuracy: 0.001)
        XCTAssertEqual(settings.themeIntensity, AppSettings.defaultThemeIntensity, accuracy: 0.001)
        XCTAssertEqual(settings.shortcut, .optionD)
        XCTAssertEqual(settings.navigationShortcut, .optionShiftD)

        let restoredAfterMutation = AppSettings(defaults: defaults)
        XCTAssertEqual(
            restoredAfterMutation.hoverDwellDelay,
            AppSettings.defaultHoverDwellDelay,
            accuracy: 0.001
        )
        XCTAssertEqual(
            restoredAfterMutation.retractionDelay,
            AppSettings.defaultRetractionDelay,
            accuracy: 0.001
        )
        XCTAssertEqual(
            restoredAfterMutation.sidebarWidth,
            AppSettings.defaultSidebarWidth,
            accuracy: 0.001
        )
        XCTAssertEqual(
            restoredAfterMutation.sidebarInset,
            AppSettings.defaultSidebarInset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            restoredAfterMutation.themeIntensity,
            AppSettings.defaultThemeIntensity,
            accuracy: 0.001
        )
    }

    @MainActor
    func testLayoutPresetsAndFineTuning() {
        let settings = AppSettings(defaults: makeDefaults())

        XCTAssertEqual(
            DiscordLayoutOptions.full,
            DiscordLayoutOptions(
                navigationPresentation: .docked,
                composerMode: .full
            )
        )
        XCTAssertEqual(
            DiscordLayoutOptions.focus,
            DiscordLayoutOptions(
                navigationPresentation: .floating,
                composerMode: .essential,
                hideMemberList: true,
                simplifyHeader: true
            )
        )
        XCTAssertEqual(
            DiscordLayoutOptions.reader,
            DiscordLayoutOptions(
                navigationPresentation: .hidden,
                composerMode: .hidden,
                hideMemberList: true,
                hideAccountDock: true,
                simplifyHeader: true
            )
        )

        settings.applyDiscordLayoutMode(.full)
        XCTAssertEqual(settings.discordLayoutOptions, .full)

        settings.setDiscordLayoutOption(\.hideMemberList, enabled: true)
        XCTAssertEqual(settings.discordLayoutMode, .custom)
        XCTAssertTrue(settings.discordLayoutOptions.hideMemberList)
        XCTAssertEqual(settings.discordLayoutOptions.navigationPresentation, .docked)

        settings.applyDiscordLayoutMode(.reader)
        XCTAssertEqual(settings.discordLayoutOptions, .reader)
        XCTAssertEqual(settings.discordLayoutOptions.navigationPresentation, .hidden)
        XCTAssertEqual(settings.discordLayoutOptions.composerMode, .hidden)
        XCTAssertFalse(settings.discordLayoutOptions.compactMedia)
    }

    @MainActor
    func testOnboardingDraftDefersAndAppliesSettingsAsOneChoiceSet() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.sidebarEdge = .right
        settings.edgeHoverEnabled = true
        settings.applyDiscordLayoutMode(.full)
        settings.floatingRailEnabled = true
        settings.visualTheme = .systemGlass
        settings.themeAccent = .automatic
        settings.notificationGlowEnabled = true
        settings.launchAtLoginEnabled = false

        var draft = OnboardingDraft(settings: settings, launchAtLoginEnabled: false)
        draft.sidebarEdge = .left
        draft.edgeHoverEnabled = false
        draft.layoutMode = .reader
        draft.floatingRailEnabled = false
        draft.visualTheme = .oled
        draft.themeAccent = .purple
        draft.notificationGlowEnabled = false
        draft.launchAtLoginEnabled = true

        XCTAssertEqual(settings.sidebarEdge, .right)
        XCTAssertTrue(settings.edgeHoverEnabled)
        XCTAssertEqual(settings.discordLayoutMode, .full)
        XCTAssertTrue(settings.floatingRailEnabled)
        XCTAssertEqual(settings.visualTheme, .systemGlass)
        XCTAssertEqual(settings.themeAccent, .automatic)
        XCTAssertTrue(settings.notificationGlowEnabled)
        XCTAssertFalse(settings.launchAtLoginEnabled)

        draft.apply(to: settings)

        XCTAssertEqual(settings.sidebarEdge, .left)
        XCTAssertFalse(settings.edgeHoverEnabled)
        XCTAssertEqual(settings.discordLayoutMode, .reader)
        XCTAssertEqual(settings.discordLayoutOptions, .reader)
        XCTAssertFalse(settings.floatingRailEnabled)
        XCTAssertEqual(settings.visualTheme, .oled)
        XCTAssertEqual(settings.themeAccent, .purple)
        XCTAssertFalse(settings.notificationGlowEnabled)
        XCTAssertTrue(settings.launchAtLoginEnabled)
    }

    @MainActor
    func testOnboardingDraftReportsFloatingRailCompatibility() {
        let settings = AppSettings(defaults: makeDefaults())
        var draft = OnboardingDraft(settings: settings, launchAtLoginEnabled: false)

        draft.layoutMode = .full
        XCTAssertFalse(draft.floatingRailIsAvailable)

        draft.layoutMode = .focus
        XCTAssertTrue(draft.floatingRailIsAvailable)

        draft.layoutMode = .reader
        XCTAssertTrue(draft.floatingRailIsAvailable)

        draft.customLayoutOptions = DiscordLayoutOptions(navigationPresentation: .docked)
        draft.layoutMode = .custom
        XCTAssertFalse(draft.floatingRailIsAvailable)
    }

    @MainActor
    func testOnboardingDraftKeepsAnExistingCustomLayoutAvailable() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.applyDiscordLayoutMode(.custom)

        var draft = OnboardingDraft(settings: settings, launchAtLoginEnabled: false)
        XCTAssertTrue(draft.includesCustomLayoutChoice)

        draft.layoutMode = .focus
        XCTAssertTrue(draft.includesCustomLayoutChoice)
    }

    @MainActor
    func testPartialAndCorruptCustomLayoutPersistence() throws {
        let partialDefaults = makeDefaults()
        partialDefaults.set("custom", forKey: "settings.discordLayoutMode")
        partialDefaults.set(
            Data(#"{"navigationPresentation":"floating","composerMode":17,"reduceMotion":true}"#.utf8),
            forKey: "settings.customDiscordLayoutOptions"
        )

        let partial = AppSettings(defaults: partialDefaults)
        XCTAssertEqual(partial.discordLayoutMode, .custom)
        XCTAssertEqual(partial.discordLayoutOptions.navigationPresentation, .floating)
        XCTAssertEqual(partial.discordLayoutOptions.composerMode, .full)
        XCTAssertTrue(partial.discordLayoutOptions.reduceMotion)
        XCTAssertFalse(partial.discordLayoutOptions.hideMemberList)

        let corruptDefaults = makeDefaults()
        corruptDefaults.set("custom", forKey: "settings.discordLayoutMode")
        corruptDefaults.set(Data("not-json".utf8), forKey: "settings.customDiscordLayoutOptions")

        let corrupt = AppSettings(defaults: corruptDefaults)
        XCTAssertEqual(corrupt.discordLayoutMode, .full)
        XCTAssertEqual(corrupt.discordLayoutOptions, .full)
        XCTAssertEqual(
            corruptDefaults.string(forKey: "settings.discordLayoutMode"),
            DiscordLayoutMode.full.rawValue
        )
        let repairedData = try XCTUnwrap(
            corruptDefaults.data(forKey: "settings.customDiscordLayoutOptions")
        )
        XCTAssertEqual(
            try JSONDecoder().decode(DiscordLayoutOptions.self, from: repairedData),
            .full
        )
    }

    @MainActor
    func testDuplicatePersistedShortcutsAreNormalizedAndRepaired() {
        let defaults = makeDefaults()
        defaults.set(Int(ShortcutDefinition.optionD.keyCode), forKey: "settings.shortcut.keyCode")
        defaults.set(
            Int(ShortcutDefinition.optionD.modifiers),
            forKey: "settings.shortcut.modifiers"
        )
        defaults.set(
            Int(ShortcutDefinition.optionD.keyCode),
            forKey: "settings.navigationShortcut.keyCode"
        )
        defaults.set(
            Int(ShortcutDefinition.optionD.modifiers),
            forKey: "settings.navigationShortcut.modifiers"
        )

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.shortcut, .optionD)
        XCTAssertEqual(settings.navigationShortcut, .optionShiftD)
        XCTAssertNotEqual(settings.navigationShortcut, settings.shortcut)
        XCTAssertEqual(
            defaults.integer(forKey: "settings.navigationShortcut.keyCode"),
            Int(ShortcutDefinition.optionShiftD.keyCode)
        )
        XCTAssertEqual(
            defaults.integer(forKey: "settings.navigationShortcut.modifiers"),
            Int(ShortcutDefinition.optionShiftD.modifiers)
        )
    }

    func testLegacyLayoutMigrationAndNewSchemaEncoding() throws {
        let legacyCases: [(String, DiscordNavigationPresentation)] = [
            (#"{"hideServerRail":false,"hideChannelList":false}"#, .docked),
            (#"{"hideServerRail":true,"hideChannelList":true}"#, .hidden),
            (#"{"hideServerRail":true,"hideChannelList":false}"#, .floating),
            (#"{"hideServerRail":false,"hideChannelList":true}"#, .floating)
        ]

        for (json, expectedPresentation) in legacyCases {
            let options = try JSONDecoder().decode(
                DiscordLayoutOptions.self,
                from: Data(json.utf8)
            )
            XCTAssertEqual(options.navigationPresentation, expectedPresentation)
        }

        let essential = try JSONDecoder().decode(
            DiscordLayoutOptions.self,
            from: Data(#"{"simplifyComposer":true}"#.utf8)
        )
        XCTAssertEqual(essential.composerMode, .essential)

        let hiddenWins = try JSONDecoder().decode(
            DiscordLayoutOptions.self,
            from: Data(#"{"simplifyComposer":true,"hideComposer":true}"#.utf8)
        )
        XCTAssertEqual(hiddenWins.composerMode, .hidden)

        let encoded = try JSONEncoder().encode(hiddenWins)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(object["navigationPresentation"] as? String, "docked")
        XCTAssertEqual(object["composerMode"] as? String, "hidden")
        XCTAssertNil(object["hideServerRail"])
        XCTAssertNil(object["hideChannelList"])
        XCTAssertNil(object["simplifyComposer"])
        XCTAssertNil(object["hideComposer"])
    }

    @MainActor
    func testThemeDefaultMigratesFreshAndUpgradedInstalls() {
        let freshDefaults = makeDefaults()
        let fresh = AppSettings(defaults: freshDefaults)
        XCTAssertEqual(fresh.visualTheme, .systemGlass)
        XCTAssertEqual(freshDefaults.string(forKey: "settings.visualTheme"), "systemGlass")

        let upgradedDefaults = makeDefaults()
        upgradedDefaults.set(true, forKey: "onboarding.completed")
        let upgraded = AppSettings(defaults: upgradedDefaults)
        XCTAssertEqual(upgraded.visualTheme, .discord)
        XCTAssertEqual(upgradedDefaults.string(forKey: "settings.visualTheme"), "discord")

        upgradedDefaults.set("oled", forKey: "settings.visualTheme")
        XCTAssertEqual(AppSettings(defaults: upgradedDefaults).visualTheme, .oled)
    }

    @MainActor
    func testPerDisplayWidthsCanBeResetIndependently() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.setWidth(500, forDisplay: "one")
        settings.setWidth(900, forDisplay: "two")
        settings.setWidth(20, forDisplay: "three")
        settings.setWidth(800, forDisplay: "")

        XCTAssertEqual(settings.width(forDisplay: "one"), 500, accuracy: 0.001)
        XCTAssertEqual(settings.width(forDisplay: "two"), 900, accuracy: 0.001)
        XCTAssertEqual(
            settings.width(forDisplay: "three"),
            AppSettings.minimumSidebarWidth,
            accuracy: 0.001
        )
        XCTAssertNil(settings.displayWidths[""])

        settings.resetWidth(forDisplay: "one")
        XCTAssertEqual(settings.width(forDisplay: "one"), settings.sidebarWidth, accuracy: 0.001)
        XCTAssertEqual(settings.width(forDisplay: "two"), 900, accuracy: 0.001)

        settings.resetAllDisplayWidths()
        XCTAssertTrue(settings.displayWidths.isEmpty)
        XCTAssertEqual(settings.width(forDisplay: "two"), settings.sidebarWidth, accuracy: 0.001)
    }

    @MainActor
    func testResetRestoresAllDefaults() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.sidebarEdge = .left
        settings.edgeHoverEnabled = false
        settings.notificationGlowEnabled = false
        settings.attentionGlowColor = .orange
        settings.attentionGlowStrength = .subtle
        settings.incomingCallCardEnabled = false
        settings.sidebarWidth = 800
        settings.sidebarInset = 44
        settings.cssPreset = .standard
        settings.applyDiscordLayoutMode(.reader)
        settings.floatingRailEnabled = false
        settings.visualTheme = .oled
        settings.themeAccent = .orange
        settings.themeIntensity = 0.25
        settings.themeColorScheme = .light
        settings.customCSS = "html {}"
        settings.customCSSEnabled = true
        settings.launchAtLoginEnabled = true
        settings.navigationShortcut = ShortcutDefinition(
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: UInt32(controlKey | optionKey)
        )
        settings.isPinned = true
        settings.setWidth(700, forDisplay: "one")

        settings.resetToDefaults()

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.sidebarEdge, .right)
        XCTAssertTrue(restored.edgeHoverEnabled)
        XCTAssertTrue(restored.notificationGlowEnabled)
        XCTAssertEqual(restored.attentionGlowColor, .followTheme)
        XCTAssertEqual(restored.attentionGlowStrength, .normal)
        XCTAssertTrue(restored.incomingCallCardEnabled)
        XCTAssertEqual(restored.sidebarWidth, 420, accuracy: 0.001)
        XCTAssertEqual(restored.sidebarInset, 16, accuracy: 0.001)
        XCTAssertEqual(restored.cssPreset, .compact)
        XCTAssertEqual(restored.discordLayoutMode, .full)
        XCTAssertEqual(restored.discordLayoutOptions, .full)
        XCTAssertTrue(restored.floatingRailEnabled)
        XCTAssertEqual(restored.visualTheme, .systemGlass)
        XCTAssertEqual(restored.themeAccent, .automatic)
        XCTAssertEqual(restored.themeIntensity, 1, accuracy: 0.001)
        XCTAssertEqual(restored.themeColorScheme, .system)
        XCTAssertEqual(restored.customCSS, "")
        XCTAssertFalse(restored.customCSSEnabled)
        XCTAssertFalse(restored.launchAtLoginEnabled)
        XCTAssertEqual(restored.navigationShortcut, .optionShiftD)
        XCTAssertFalse(restored.isPinned)
        XCTAssertTrue(restored.displayWidths.isEmpty)
    }

    @MainActor
    func testDiscordSettingsBridgeAcceptsOnlyKnownTypedValues() {
        let settings = AppSettings(defaults: makeDefaults())

        XCTAssertTrue(SideCordSettingsMutation.apply(key: "sidebarEdge", value: "left", to: settings))
        XCTAssertEqual(settings.sidebarEdge, .left)
        XCTAssertTrue(SideCordSettingsMutation.apply(key: "themeAccent", value: "white", to: settings))
        XCTAssertEqual(settings.themeAccent, .white)
        XCTAssertTrue(SideCordSettingsMutation.apply(key: "themeIntensity", value: 0.45, to: settings))
        XCTAssertEqual(settings.themeIntensity, 0.45, accuracy: 0.001)
        XCTAssertTrue(SideCordSettingsMutation.apply(key: "edgeHoverEnabled", value: false, to: settings))
        XCTAssertFalse(settings.edgeHoverEnabled)

        XCTAssertFalse(SideCordSettingsMutation.apply(key: "themeIntensity", value: 4.0, to: settings))
        XCTAssertFalse(SideCordSettingsMutation.apply(key: "edgeHoverEnabled", value: 1, to: settings))
        XCTAssertFalse(SideCordSettingsMutation.apply(key: "discordLayoutMode", value: "custom", to: settings))
        XCTAssertFalse(SideCordSettingsMutation.apply(key: "unknownSetting", value: true, to: settings))
        XCTAssertEqual(settings.themeIntensity, 0.45, accuracy: 0.001)
    }

    func testGuidedOnboardingStepsRemainSequentialAndFocused() {
        XCTAssertEqual(OnboardingSetupStep.allCases, [.placement, .layout, .appearance, .ready])
        XCTAssertEqual(OnboardingSetupStep.placement.eyebrow, "01 · Placement")
        XCTAssertEqual(OnboardingSetupStep.ready.title, "You’re all set")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.sidecord.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
