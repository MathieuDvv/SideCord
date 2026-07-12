import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: ShortcutDefinition

    func makeCoordinator() -> Coordinator {
        Coordinator(shortcut: $shortcut)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: shortcut.displayName,
            target: context.coordinator,
            action: #selector(Coordinator.beginRecording(_:))
        )
        button.bezelStyle = .rounded
        button.setContentHuggingPriority(.required, for: .horizontal)
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.shortcut = $shortcut
        if !context.coordinator.isRecording {
            button.title = shortcut.displayName
        }
    }

    static func dismantleNSView(_ nsView: NSButton, coordinator: Coordinator) {
        coordinator.stopRecording()
    }

    @MainActor
    final class Coordinator: NSObject {
        var shortcut: Binding<ShortcutDefinition>
        weak var button: NSButton?
        private var eventMonitor: Any?
        fileprivate var isRecording = false

        init(shortcut: Binding<ShortcutDefinition>) {
            self.shortcut = shortcut
        }

        @objc func beginRecording(_ sender: NSButton) {
            stopRecording()
            isRecording = true
            sender.title = "Type shortcut…"
            sender.highlight(true)

            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let carbonModifiers = modifiers.carbonHotKeyModifiers
            guard carbonModifiers != 0 else {
                NSSound.beep()
                button?.title = "Include ⌘, ⌥, ⌃, or ⇧"
                return nil
            }

            shortcut.wrappedValue = ShortcutDefinition(
                keyCode: UInt32(event.keyCode),
                modifiers: carbonModifiers
            )
            stopRecording()
            return nil
        }

        fileprivate func stopRecording() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            isRecording = false
            button?.highlight(false)
            button?.title = shortcut.wrappedValue.displayName
        }
    }
}

private extension NSEvent.ModifierFlags {
    var carbonHotKeyModifiers: UInt32 {
        var result: UInt32 = 0
        if contains(.command) { result |= UInt32(cmdKey) }
        if contains(.option) { result |= UInt32(optionKey) }
        if contains(.control) { result |= UInt32(controlKey) }
        if contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
