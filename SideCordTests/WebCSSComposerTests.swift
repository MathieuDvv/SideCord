import XCTest
@testable import SideCord

final class WebCSSComposerTests: XCTestCase {
    func testStandardPresetWithoutCustomCSSProducesNoStyles() {
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

    func testCompactAndCustomStylesAreComposed() {
        let result = DiscordCSSComposer.compose(
            preset: .compact,
            compactPresetCSS: "  .compact { width: 10px; }  ",
            customCSS: "\n.custom { color: red; }\n",
            customCSSEnabled: true
        )

        XCTAssertEqual(
            result,
            ".compact { width: 10px; }\n\n.custom { color: red; }"
        )
    }

    func testLayoutModifiersAreIncludedOnlyWhenEnabled() {
        let enabled = DiscordCSSComposer.compose(
            preset: .standard,
            compactPresetCSS: ".compact {}",
            layoutModifiersCSS: "  .modifiers {}  ",
            layoutOptions: .focus,
            customCSS: "",
            customCSSEnabled: false
        )
        let disabled = DiscordCSSComposer.compose(
            preset: .standard,
            compactPresetCSS: ".compact {}",
            layoutModifiersCSS: ".modifiers {}",
            layoutOptions: .full,
            customCSS: "",
            customCSSEnabled: false
        )

        XCTAssertEqual(enabled, ".modifiers {}")
        XCTAssertEqual(disabled, "")
    }

    func testFocusAndReaderRootAttributes() {
        let focusAttributes = DiscordCSSComposer.rootAttributeNames(for: .focus)
        let readerAttributes = DiscordCSSComposer.rootAttributeNames(for: .reader)

        XCTAssertTrue(focusAttributes.contains("data-sidecord-hide-servers"))
        XCTAssertTrue(focusAttributes.contains("data-sidecord-hide-channels"))
        XCTAssertTrue(focusAttributes.contains("data-sidecord-hide-members"))
        XCTAssertTrue(focusAttributes.contains("data-sidecord-simplify-composer"))
        XCTAssertFalse(focusAttributes.contains("data-sidecord-hide-composer"))
        XCTAssertTrue(readerAttributes.contains("data-sidecord-hide-composer"))
        XCTAssertFalse(readerAttributes.contains("data-sidecord-compact-media"))
    }

    func testEveryLayoutOptionMapsToExactlyOneManagedClass() {
        let allOptions = DiscordLayoutOptions(
            hideServerRail: true,
            hideChannelList: true,
            hideMemberList: true,
            hideAccountDock: true,
            simplifyHeader: true,
            simplifyComposer: true,
            hideComposer: true,
            compactMedia: true,
            reduceMotion: true
        )

        XCTAssertEqual(
            Set(DiscordCSSComposer.rootAttributeNames(for: allOptions)),
            Set(DiscordCSSComposer.managedRootAttributeNames)
        )
        XCTAssertEqual(DiscordCSSComposer.rootAttributeNames(for: .full), [])
    }

    func testEmptyStylesStillRemoveEveryManagedRootAttribute() {
        let script = DiscordCSSComposer.userScriptSource(css: "")

        for attributeName in DiscordCSSComposer.managedRootAttributeNames {
            XCTAssertTrue(script.contains(attributeName))
        }
        XCTAssertTrue(script.contains("root.removeAttribute(name)"))
        XCTAssertTrue(script.contains("if (!state.css && state.enabledAttributes.size === 0) return"))
    }

    func testUserScriptInstallsOneSelfHealingRuntime() {
        let script = DiscordCSSComposer.userScriptSource(
            css: ".focused {}",
            rootAttributeNames: ["data-sidecord-hide-servers"]
        )

        XCTAssertTrue(script.contains(DiscordCSSComposer.runtimeKey))
        XCTAssertTrue(script.contains("previousRuntime.dispose()"))
        XCTAssertEqual(script.components(separatedBy: "new MutationObserver").count - 1, 1)
        XCTAssertTrue(script.contains("observer.disconnect()"))
        XCTAssertTrue(script.contains("root.toggleAttribute(name"))
        XCTAssertTrue(script.contains("repairScheduled"))
        XCTAssertTrue(script.contains("queueMicrotask"))
        XCTAssertTrue(script.contains("style.textContent !== state.css"))
        XCTAssertTrue(script.contains("observer.observe(document, { childList: true })"))
        XCTAssertFalse(script.contains("observer.observe(document, { childList: true, subtree: true })"))

        let hostGuard = script.range(of: "if (window.location.protocol")!.lowerBound
        let runtimeCreation = script.range(of: "const previousRuntime")!.lowerBound
        XCTAssertLessThan(hostGuard, runtimeCreation)
    }

    func testCustomCSSRejectsNetworkLoadingPrimitives() {
        let unsafeCSS = """
        @import "https://example.com/theme.css" screen;
        .avatar { background: URL(https://example.com/pixel.png); }
        .safe { color: rebeccapurple; }
        """

        let result = DiscordCSSComposer.sanitizeCustomCSS(unsafeCSS)

        XCTAssertEqual(
            result,
            "/* SideCord blocked custom CSS containing network-capable syntax. */"
        )
    }

    func testEscapedImportIsRejected() {
        let escapedImport = #"@\69mport "https://example.com/theme.css";"#

        XCTAssertNotNil(DiscordCSSComposer.validationError(for: escapedImport))
        XCTAssertFalse(DiscordCSSComposer.sanitizeCustomCSS(escapedImport).contains("example.com"))
    }

    func testSafeSelectorContainingURLLettersIsAllowed() {
        let css = ".curl-indicator { color: rebeccapurple; }"

        XCTAssertNil(DiscordCSSComposer.validationError(for: css))
        XCTAssertEqual(DiscordCSSComposer.sanitizeCustomCSS(css), css)
    }

    func testUserScriptUsesJSONStringEncodingAndDiscordHostGuard() {
        let css = "body::after { content: \"</style>\\n'${danger}\"; }"
        let script = DiscordCSSComposer.userScriptSource(
            css: css,
            rootAttributeNames: ["data-sidecord-hide-servers"]
        )

        XCTAssertTrue(script.contains("discord.com"))
        XCTAssertTrue(script.contains("discordapp.com"))
        XCTAssertTrue(script.contains(DiscordCSSComposer.styleElementID))
        XCTAssertTrue(script.contains("style.textContent = state.css"))
        XCTAssertTrue(script.contains("root.toggleAttribute"))
        XCTAssertTrue(script.contains("data-sidecord-hide-servers"))
        XCTAssertFalse(script.contains("const css = \(css);"))
    }
}
