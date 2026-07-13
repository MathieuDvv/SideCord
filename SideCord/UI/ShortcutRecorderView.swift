import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
protocol ShortcutRecordingParticipant: AnyObject {
    func cancelShortcutRecording()
}

@MainActor
final class ShortcutRecordingSession: ObservableObject {
    private weak var activeRecorder: (any ShortcutRecordingParticipant)?

    var hasActiveRecorder: Bool {
        activeRecorder != nil
    }

    func activate(_ recorder: any ShortcutRecordingParticipant) {
        guard activeRecorder !== recorder else { return }
        activeRecorder?.cancelShortcutRecording()
        activeRecorder = recorder
    }

    func deactivate(_ recorder: any ShortcutRecordingParticipant) {
        guard activeRecorder === recorder else { return }
        activeRecorder = nil
    }

    func cancel() {
        let recorder = activeRecorder
        activeRecorder = nil
        recorder?.cancelShortcutRecording()
    }
}

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: ShortcutDefinition
    let recordingSession: ShortcutRecordingSession

    func makeCoordinator() -> Coordinator {
        Coordinator(shortcut: $shortcut, recordingSession: recordingSession)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = ShortcutRecorderButton(
            title: shortcut.displayName,
            target: context.coordinator,
            action: #selector(Coordinator.beginRecording(_:))
        )
        button.bezelStyle = .rounded
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.hostWindowDidChange(to: window)
        }
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
        coordinator.stopObservingHostWindow()
    }

    @MainActor
    final class Coordinator: NSObject {
        var shortcut: Binding<ShortcutDefinition>
        weak var button: NSButton?
        private let recordingSession: ShortcutRecordingSession
        private var eventMonitor: Any?
        private weak var observedWindow: NSWindow?
        private(set) var isRecording = false

        init(
            shortcut: Binding<ShortcutDefinition>,
            recordingSession: ShortcutRecordingSession
        ) {
            self.shortcut = shortcut
            self.recordingSession = recordingSession
        }

        @objc func beginRecording(_ sender: NSButton) {
            stopRecording()
            recordingSession.activate(self)
            isRecording = true
            sender.title = "Type shortcut…"
            sender.bezelColor = .controlAccentColor

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
            recordingSession.deactivate(self)
            button?.bezelColor = nil
            button?.title = shortcut.wrappedValue.displayName
        }

        func hostWindowDidChange(to window: NSWindow?) {
            guard observedWindow !== window else { return }
            stopRecording()
            stopObservingHostWindow()
            observedWindow = window

            guard let window else { return }
            let center = NotificationCenter.default
            center.addObserver(
                self,
                selector: #selector(hostWindowDidEndInteraction(_:)),
                name: NSWindow.didResignKeyNotification,
                object: window
            )
            center.addObserver(
                self,
                selector: #selector(hostWindowDidEndInteraction(_:)),
                name: NSWindow.willCloseNotification,
                object: window
            )
        }

        func stopObservingHostWindow() {
            guard let observedWindow else { return }
            let center = NotificationCenter.default
            center.removeObserver(
                self,
                name: NSWindow.didResignKeyNotification,
                object: observedWindow
            )
            center.removeObserver(
                self,
                name: NSWindow.willCloseNotification,
                object: observedWindow
            )
            self.observedWindow = nil
        }

        @objc private func hostWindowDidEndInteraction(_ notification: Notification) {
            stopRecording()
        }
    }
}

extension ShortcutRecorderView.Coordinator: ShortcutRecordingParticipant {
    func cancelShortcutRecording() {
        stopRecording()
    }
}

private final class ShortcutRecorderButton: NSButton {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
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
