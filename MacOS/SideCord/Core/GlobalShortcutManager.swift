import Carbon.HIToolbox
import Foundation

enum GlobalShortcutError: Error, LocalizedError, Equatable {
    case invalidShortcut
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)
    case registrationAndRecoveryFailed(registration: OSStatus, recovery: OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidShortcut:
            "Choose a shortcut that contains a modifier key."
        case let .eventHandlerInstallationFailed(status):
            "SideCord could not listen for global shortcuts (error \(status))."
        case let .registrationFailed(status):
            "That global shortcut could not be registered (error \(status))."
        case let .registrationAndRecoveryFailed(registration, recovery):
            "The new shortcut failed (error \(registration)), and SideCord could not restore the previous shortcut (error \(recovery)). Choose another shortcut or restart SideCord."
        }
    }
}

@MainActor
final class GlobalShortcutManager {
    typealias Handler = () -> Void

    private static let signature: OSType = 0x5364_4364 // "SdCd"

    private let resources = GlobalShortcutResources()
    private let identifier: UInt32
    private var handler: Handler?

    private(set) var registeredShortcut: ShortcutDefinition?

    init(identifier: UInt32 = 1, handler: Handler? = nil) {
        self.identifier = identifier
        self.handler = handler
    }

    func setHandler(_ handler: @escaping Handler) {
        self.handler = handler
    }

    func register(
        _ shortcut: ShortcutDefinition,
        handler: @escaping Handler
    ) throws {
        self.handler = handler
        try register(shortcut)
    }

    func register(_ shortcut: ShortcutDefinition) throws {
        guard shortcut.isValid else { throw GlobalShortcutError.invalidShortcut }

        if registeredShortcut == shortcut, resources.hotKeyReference != nil {
            return
        }

        try installEventHandlerIfNeeded()

        let previousShortcut = registeredShortcut
        unregisterHotKey()

        do {
            try registerHotKey(shortcut)
        } catch let registrationError {
            if let previousShortcut {
                do {
                    try registerHotKey(previousShortcut)
                } catch {
                    throw GlobalShortcutError.registrationAndRecoveryFailed(
                        registration: Self.registrationStatus(from: registrationError),
                        recovery: Self.registrationStatus(from: error)
                    )
                }
            }
            throw registrationError
        }
    }

    func unregister() {
        unregisterHotKey()
    }

    /// Carbon's hot-key APIs are main-thread-only. AppDelegate calls this while
    /// still on the main actor instead of relying on nonisolated deinitializers.
    func shutdown() {
        unregisterHotKey()
        if let eventHandlerReference = resources.eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            resources.eventHandlerReference = nil
        }
        handler = nil
    }

    private func installEventHandlerIfNeeded() throws {
        guard resources.eventHandlerReference == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installedHandler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            sideCordHotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &installedHandler
        )

        guard status == noErr, let installedHandler else {
            throw GlobalShortcutError.eventHandlerInstallationFailed(status)
        }
        resources.eventHandlerReference = installedHandler
    }

    private func registerHotKey(_ shortcut: ShortcutDefinition) throws {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: identifier
        )
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            throw GlobalShortcutError.registrationFailed(status)
        }

        resources.hotKeyReference = reference
        registeredShortcut = shortcut
    }

    private func unregisterHotKey() {
        if let hotKeyReference = resources.hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        resources.hotKeyReference = nil
        registeredShortcut = nil
    }

    private static func registrationStatus(from error: Error) -> OSStatus {
        guard let shortcutError = error as? GlobalShortcutError,
              case let .registrationFailed(status) = shortcutError
        else {
            return OSStatus(paramErr)
        }
        return status
    }

    fileprivate func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr,
              hotKeyID.signature == Self.signature,
              hotKeyID.id == identifier
        else { return OSStatus(eventNotHandledErr) }

        handler?()
        return noErr
    }
}

private func sideCordHotKeyEventHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }

    // Carbon invokes application event-target handlers on the thread where they
    // were installed. Preserve the pointer values as Sendable integers while
    // asserting the main-actor contract established by the manager.
    let eventAddress = UInt(bitPattern: event)
    let contextAddress = UInt(bitPattern: context)

    return MainActor.assumeIsolated {
        guard let event = OpaquePointer(bitPattern: eventAddress),
              let context = UnsafeMutableRawPointer(bitPattern: contextAddress)
        else { return OSStatus(eventNotHandledErr) }
        let manager = Unmanaged<GlobalShortcutManager>
            .fromOpaque(context)
            .takeUnretainedValue()
        return manager.handleHotKeyEvent(event)
    }
}

private final class GlobalShortcutResources {
    var eventHandlerReference: EventHandlerRef?
    var hotKeyReference: EventHotKeyRef?
}
