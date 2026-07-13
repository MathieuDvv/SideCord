import AppKit
import Carbon.HIToolbox
import XCTest
@testable import SideCord

final class CoreShortcutTests: XCTestCase {
    @MainActor
    func testApplicationEditMenuRoutesStandardCommandsThroughResponderChain() throws {
        let mainMenu = ApplicationMenuFactory.make()
        let editMenu = try XCTUnwrap(mainMenu.items.first?.submenu)
        let expectedCommands: [(String, String, String, NSEvent.ModifierFlags)] = [
            ("Undo", "undo:", "z", [.command]),
            ("Redo", "redo:", "z", [.command, .shift]),
            ("Cut", "cut:", "x", [.command]),
            ("Copy", "copy:", "c", [.command]),
            ("Paste", "paste:", "v", [.command]),
            ("Paste and Match Style", "pasteAsPlainText:", "v", [.command, .option, .shift]),
            ("Select All", "selectAll:", "a", [.command])
        ]

        for (title, action, key, modifiers) in expectedCommands {
            let item = try XCTUnwrap(editMenu.items.first { $0.title == title })
            XCTAssertEqual(item.action, Selector((action)), title)
            XCTAssertEqual(item.keyEquivalent, key, title)
            XCTAssertEqual(item.keyEquivalentModifierMask, modifiers, title)
            XCTAssertNil(item.target, title)
        }
    }

    func testOptionDDefinition() {
        XCTAssertEqual(ShortcutDefinition.optionD.keyCode, UInt32(kVK_ANSI_D))
        XCTAssertEqual(ShortcutDefinition.optionD.modifiers, UInt32(optionKey))
        XCTAssertEqual(ShortcutDefinition.optionD.displayName, "⌥D")
        XCTAssertTrue(ShortcutDefinition.optionD.isValid)

        XCTAssertEqual(ShortcutDefinition.optionShiftD.keyCode, UInt32(kVK_ANSI_D))
        XCTAssertEqual(
            ShortcutDefinition.optionShiftD.modifiers,
            UInt32(optionKey | shiftKey)
        )
        XCTAssertEqual(ShortcutDefinition.optionShiftD.displayName, "⌥⇧D")
        XCTAssertTrue(ShortcutDefinition.optionShiftD.isValid)
    }

    func testShortcutRequiresOnlySupportedModifiers() {
        XCTAssertFalse(ShortcutDefinition(keyCode: 2, modifiers: 0).isValid)
        XCTAssertFalse(ShortcutDefinition(keyCode: 2, modifiers: UInt32(alphaLock)).isValid)
        XCTAssertFalse(ShortcutDefinition(keyCode: 999, modifiers: UInt32(cmdKey)).isValid)
        XCTAssertTrue(
            ShortcutDefinition(
                keyCode: UInt32(kVK_ANSI_D),
                modifiers: UInt32(cmdKey | shiftKey)
            ).isValid
        )
    }

    @MainActor
    func testGlobalShortcutManagerRejectsInvalidShortcutBeforeRegistration() {
        let manager = GlobalShortcutManager()

        XCTAssertThrowsError(
            try manager.register(ShortcutDefinition(keyCode: 2, modifiers: 0))
        ) { error in
            XCTAssertEqual(error as? GlobalShortcutError, .invalidShortcut)
        }
        XCTAssertNil(manager.registeredShortcut)
    }
}
