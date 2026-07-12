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
        XCTAssertEqual(settings.hoverDwellDelay, 0.25, accuracy: 0.001)
        XCTAssertEqual(settings.retractionDelay, 0.7, accuracy: 0.001)
        XCTAssertEqual(settings.sidebarWidth, 420, accuracy: 0.001)
        XCTAssertEqual(settings.sidebarInset, 16, accuracy: 0.001)
        XCTAssertEqual(settings.cssPreset, .compact)
        XCTAssertEqual(settings.discordLayoutMode, .full)
        XCTAssertEqual(settings.discordLayoutOptions, .full)
        XCTAssertEqual(settings.customCSS, "")
        XCTAssertFalse(settings.customCSSEnabled)
        XCTAssertFalse(settings.launchAtLoginEnabled)
        XCTAssertEqual(settings.shortcut, .optionD)
        XCTAssertFalse(settings.isPinned)
        XCTAssertEqual(settings.width(forDisplay: "main"), 420, accuracy: 0.001)
    }

    @MainActor
    func testChangesPersistAcrossInstances() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.sidebarEdge = .left
        settings.edgeHoverEnabled = false
        settings.hoverDwellDelay = 0.4
        settings.retractionDelay = 1.2
        settings.sidebarWidth = 512
        settings.sidebarInset = 28
        settings.cssPreset = .standard
        settings.applyDiscordLayoutMode(.reader)
        settings.setDiscordLayoutOption(\.reduceMotion, enabled: true)
        settings.customCSS = "body { color: red; }"
        settings.customCSSEnabled = true
        settings.launchAtLoginEnabled = true
        settings.shortcut = ShortcutDefinition(
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        settings.isPinned = true
        settings.setWidth(618, forDisplay: "display-1")

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.sidebarEdge, .left)
        XCTAssertFalse(restored.edgeHoverEnabled)
        XCTAssertEqual(restored.hoverDwellDelay, 0.4, accuracy: 0.001)
        XCTAssertEqual(restored.retractionDelay, 1.2, accuracy: 0.001)
        XCTAssertEqual(restored.sidebarWidth, 512, accuracy: 0.001)
        XCTAssertEqual(restored.sidebarInset, 28, accuracy: 0.001)
        XCTAssertEqual(restored.cssPreset, .standard)
        XCTAssertEqual(restored.discordLayoutMode, .custom)
        XCTAssertTrue(restored.discordLayoutOptions.hideComposer)
        XCTAssertTrue(restored.discordLayoutOptions.reduceMotion)
        XCTAssertEqual(restored.customCSS, "body { color: red; }")
        XCTAssertTrue(restored.customCSSEnabled)
        XCTAssertTrue(restored.launchAtLoginEnabled)
        XCTAssertEqual(restored.shortcut, settings.shortcut)
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
        defaults.set(999, forKey: "settings.shortcut.keyCode")
        defaults.set(0, forKey: "settings.shortcut.modifiers")

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.hoverDwellDelay, 0, accuracy: 0.001)
        XCTAssertEqual(settings.retractionDelay, 10, accuracy: 0.001)
        XCTAssertEqual(settings.sidebarWidth, AppSettings.minimumSidebarWidth, accuracy: 0.001)
        XCTAssertEqual(settings.sidebarInset, 0, accuracy: 0.001)
        XCTAssertEqual(settings.sidebarEdge, .right)
        XCTAssertEqual(settings.cssPreset, .compact)
        XCTAssertEqual(settings.discordLayoutMode, .full)
        XCTAssertEqual(settings.shortcut, .optionD)

        settings.hoverDwellDelay = .infinity
        settings.retractionDelay = -.infinity
        settings.sidebarWidth = .nan
        settings.sidebarInset = 999
        XCTAssertEqual(settings.sidebarInset, 48, accuracy: 0.001)
        settings.sidebarInset = .infinity
        settings.shortcut = ShortcutDefinition(keyCode: 1, modifiers: 0)

        XCTAssertEqual(settings.hoverDwellDelay, AppSettings.defaultHoverDwellDelay, accuracy: 0.001)
        XCTAssertEqual(settings.retractionDelay, AppSettings.defaultRetractionDelay, accuracy: 0.001)
        XCTAssertEqual(settings.sidebarWidth, AppSettings.defaultSidebarWidth, accuracy: 0.001)
        XCTAssertEqual(settings.sidebarInset, AppSettings.defaultSidebarInset, accuracy: 0.001)
        XCTAssertEqual(settings.shortcut, .optionD)

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
    }

    @MainActor
    func testLayoutModesAndFineTuning() {
        let settings = AppSettings(defaults: makeDefaults())

        XCTAssertEqual(settings.discordLayoutOptions, .full)

        settings.applyDiscordLayoutMode(.full)
        XCTAssertEqual(settings.discordLayoutOptions, .full)

        settings.setDiscordLayoutOption(\.hideMemberList, enabled: true)
        XCTAssertEqual(settings.discordLayoutMode, .custom)
        XCTAssertTrue(settings.discordLayoutOptions.hideMemberList)
        XCTAssertFalse(settings.discordLayoutOptions.hideServerRail)

        settings.applyDiscordLayoutMode(.reader)
        XCTAssertEqual(settings.discordLayoutOptions, .reader)
        XCTAssertTrue(settings.discordLayoutOptions.hideComposer)
        XCTAssertFalse(settings.discordLayoutOptions.compactMedia)
    }

    @MainActor
    func testPartialAndCorruptCustomLayoutPersistence() {
        let partialDefaults = makeDefaults()
        partialDefaults.set("custom", forKey: "settings.discordLayoutMode")
        partialDefaults.set(
            Data(#"{"hideServerRail":true}"#.utf8),
            forKey: "settings.customDiscordLayoutOptions"
        )

        let partial = AppSettings(defaults: partialDefaults)
        XCTAssertEqual(partial.discordLayoutMode, .custom)
        XCTAssertTrue(partial.discordLayoutOptions.hideServerRail)
        XCTAssertFalse(partial.discordLayoutOptions.hideChannelList)
        XCTAssertFalse(partial.discordLayoutOptions.reduceMotion)

        let corruptDefaults = makeDefaults()
        corruptDefaults.set("custom", forKey: "settings.discordLayoutMode")
        corruptDefaults.set(Data("not-json".utf8), forKey: "settings.customDiscordLayoutOptions")

        let corrupt = AppSettings(defaults: corruptDefaults)
        XCTAssertEqual(corrupt.discordLayoutMode, .full)
        XCTAssertEqual(corrupt.discordLayoutOptions, .full)
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
        settings.sidebarWidth = 800
        settings.sidebarInset = 44
        settings.cssPreset = .standard
        settings.applyDiscordLayoutMode(.reader)
        settings.customCSS = "html {}"
        settings.customCSSEnabled = true
        settings.launchAtLoginEnabled = true
        settings.isPinned = true
        settings.setWidth(700, forDisplay: "one")

        settings.resetToDefaults()

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.sidebarEdge, .right)
        XCTAssertTrue(restored.edgeHoverEnabled)
        XCTAssertEqual(restored.sidebarWidth, 420, accuracy: 0.001)
        XCTAssertEqual(restored.sidebarInset, 16, accuracy: 0.001)
        XCTAssertEqual(restored.cssPreset, .compact)
        XCTAssertEqual(restored.discordLayoutMode, .full)
        XCTAssertEqual(restored.discordLayoutOptions, .full)
        XCTAssertEqual(restored.customCSS, "")
        XCTAssertFalse(restored.customCSSEnabled)
        XCTAssertFalse(restored.launchAtLoginEnabled)
        XCTAssertFalse(restored.isPinned)
        XCTAssertTrue(restored.displayWidths.isEmpty)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.sidecord.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
