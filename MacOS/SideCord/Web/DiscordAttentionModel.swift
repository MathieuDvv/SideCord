import Combine
import Foundation

struct IncomingCallDescriptor: Equatable, Sendable {
    static let generic = IncomingCallDescriptor(
        id: "incoming-discord-call",
        displayName: "Incoming Discord call"
    )

    let id: String
    let displayName: String

    init(id: String, displayName: String) {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = displayName
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        self.id = String((normalizedID.isEmpty ? Self.genericID : normalizedID).prefix(128))
        self.displayName = String(
            (normalizedName.isEmpty ? "Incoming Discord call" : normalizedName).prefix(120)
        )
    }

    private static let genericID = "incoming-discord-call"
}

/// Converts Discord's continuously reported UI state into small, privacy-safe
/// attention signals. It tracks only unread flags and counts; no message text,
/// sender, or notification content crosses the WebKit bridge.
@MainActor
final class DiscordAttentionModel: ObservableObject {
    @Published private(set) var notificationSequence: UInt64 = 0
    @Published private(set) var incomingCall: IncomingCallDescriptor?

    var isIncomingCallActive: Bool { incomingCall != nil }

    private struct RailState: Equatable {
        let hasUnread: Bool
        let mentionCount: Int
    }

    private var previousRailState: [String: RailState]?
    init() {}

    func receiveRailItems(_ items: [DiscordRailItem]) {
        var state: [String: RailState] = [:]
        for item in items where item.kind != .action {
            state[item.id] = RailState(
                hasUnread: item.hasUnread,
                mentionCount: item.mentionCount ?? 0
            )
        }

        // Discord briefly removes its rail while replacing app DOM. Preserve an
        // established baseline through that empty report: a notification can
        // arrive during the rebuild, and resetting here used to discard it when
        // the populated rail returned. Navigation explicitly calls reset().
        guard !state.isEmpty else { return }
        guard let previousRailState else {
            self.previousRailState = state
            return
        }

        let hasNewAttention = state.contains { id, current in
            guard let previous = previousRailState[id] else {
                // Discord virtualizes and repopulates the rail. An unseen item
                // can already have historical badges, so it is a baseline—not
                // proof that a notification was just delivered.
                return false
            }
            return (!previous.hasUnread && current.hasUnread)
                || current.mentionCount > previous.mentionCount
        }

        self.previousRailState = state
        if hasNewAttention {
            signalNotification()
        }
    }

    func setIncomingCallActive(_ isActive: Bool) {
        setIncomingCall(isActive ? .generic : nil)
    }

    func setIncomingCall(_ descriptor: IncomingCallDescriptor?) {
        guard incomingCall != descriptor else { return }
        incomingCall = descriptor
    }

    func receiveNotification() {
        signalNotification()
    }

    func reset() {
        previousRailState = nil
        incomingCall = nil
    }

    private func signalNotification() {
        // Do not time-coalesce these events. Discord can legitimately deliver
        // several notifications in one burst, and restarting the current glow
        // is preferable to silently dropping a later delivery.
        notificationSequence &+= 1
    }
}
