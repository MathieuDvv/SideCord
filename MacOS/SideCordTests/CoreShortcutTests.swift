import AppKit
import Carbon.HIToolbox
import SwiftUI
import XCTest
@testable import SideCord

final class CoreShortcutTests: XCTestCase {
    @MainActor
    func testApplicationEditMenuRoutesStandardCommandsThroughResponderChain() throws {
        let mainMenu = ApplicationMenuFactory.make(appName: "SideCord")
        let editMenu = try XCTUnwrap(
            mainMenu.items.first { $0.title == "Edit" }?.submenu
        )
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

    @MainActor
    func testApplicationMenuContainsStandardAppCommands() throws {
        let settingsTarget = ApplicationMenuSettingsTargetSpy()
        let mainMenu = ApplicationMenuFactory.make(
            appName: "SideCord",
            settingsTarget: settingsTarget
        )
        XCTAssertEqual(mainMenu.items.map(\.title), ["SideCord", "Edit", "Window"])

        let appMenu = try XCTUnwrap(
            mainMenu.items.first { $0.title == "SideCord" }?.submenu
        )
        let expectedCommands: [(String, String, String, NSEvent.ModifierFlags)] = [
            ("About SideCord", "orderFrontStandardAboutPanel:", "", []),
            ("Hide SideCord", "hide:", "h", [.command]),
            ("Hide Others", "hideOtherApplications:", "h", [.command, .option]),
            ("Show All", "unhideAllApplications:", "", []),
            ("Quit SideCord", "terminate:", "q", [.command])
        ]

        for (title, action, key, modifiers) in expectedCommands {
            let item = try XCTUnwrap(appMenu.items.first { $0.title == title })
            XCTAssertEqual(item.action, Selector((action)), title)
            XCTAssertEqual(item.keyEquivalent, key, title)
            XCTAssertEqual(item.keyEquivalentModifierMask, modifiers, title)
            XCTAssertNil(item.target, title)
        }

        let settingsItem = try XCTUnwrap(
            appMenu.items.first { $0.title == "Settings…" }
        )
        XCTAssertEqual(settingsItem.action, #selector(ApplicationMenuSettingsTargetSpy.showSettings(_:)))
        XCTAssertEqual(settingsItem.keyEquivalent, ",")
        XCTAssertEqual(settingsItem.keyEquivalentModifierMask, [.command])
        XCTAssertTrue(settingsItem.target === settingsTarget)

        XCTAssertNotNil(appMenu.items.first { $0.title == "Services" }?.submenu)
    }

    @MainActor
    func testApplicationWindowMenuRoutesWindowCommandsThroughResponderChain() throws {
        let mainMenu = ApplicationMenuFactory.make(appName: "SideCord")
        let windowMenu = try XCTUnwrap(
            mainMenu.items.first { $0.title == "Window" }?.submenu
        )
        let expectedCommands: [(String, String, String)] = [
            ("Close", "performClose:", "w"),
            ("Minimize", "performMiniaturize:", "m")
        ]

        for (title, action, key) in expectedCommands {
            let item = try XCTUnwrap(windowMenu.items.first { $0.title == title })
            XCTAssertEqual(item.action, Selector((action)), title)
            XCTAssertEqual(item.keyEquivalent, key, title)
            XCTAssertEqual(item.keyEquivalentModifierMask, [.command], title)
            XCTAssertNil(item.target, title)
        }
    }

    @MainActor
    func testShortcutRecordingSessionKeepsOnlyOneRecorderActive() {
        let session = ShortcutRecordingSession()
        let first = ShortcutRecordingParticipantSpy()
        let second = ShortcutRecordingParticipantSpy()

        session.activate(first)
        session.activate(first)
        XCTAssertTrue(session.hasActiveRecorder)
        XCTAssertEqual(first.cancellationCount, 0)

        session.activate(second)
        XCTAssertEqual(first.cancellationCount, 1)
        XCTAssertTrue(session.hasActiveRecorder)

        session.deactivate(first)
        XCTAssertTrue(session.hasActiveRecorder)

        session.cancel()
        XCTAssertEqual(second.cancellationCount, 1)
        XCTAssertFalse(session.hasActiveRecorder)
    }

    @MainActor
    func testShortcutRecorderStopsWhenSettingsWindowLosesFocusOrCloses() {
        let session = ShortcutRecordingSession()
        let coordinator = ShortcutRecorderView.Coordinator(
            shortcut: .constant(.optionD),
            recordingSession: session
        )
        let button = NSButton(title: "⌥D", target: nil, action: nil)
        let window = NSWindow()
        coordinator.button = button
        coordinator.hostWindowDidChange(to: window)
        defer {
            coordinator.cancelShortcutRecording()
            coordinator.stopObservingHostWindow()
        }

        for notificationName in [
            NSWindow.didResignKeyNotification,
            NSWindow.willCloseNotification
        ] {
            coordinator.beginRecording(button)
            XCTAssertTrue(coordinator.isRecording)
            XCTAssertTrue(session.hasActiveRecorder)

            NotificationCenter.default.post(name: notificationName, object: window)

            XCTAssertFalse(coordinator.isRecording)
            XCTAssertFalse(session.hasActiveRecorder)
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

@MainActor
private final class ShortcutRecordingParticipantSpy: ShortcutRecordingParticipant {
    private(set) var cancellationCount = 0

    func cancelShortcutRecording() {
        cancellationCount += 1
    }
}

@MainActor
private final class ApplicationMenuSettingsTargetSpy: NSObject {
    @objc func showSettings(_ sender: Any?) {}
}
