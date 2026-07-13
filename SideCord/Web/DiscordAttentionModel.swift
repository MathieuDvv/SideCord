import Combine
import Foundation

/// Converts Discord's continuously reported UI state into small, privacy-safe
/// attention signals. It tracks only unread flags and counts; no message text,
/// sender, or notification content crosses the WebKit bridge.
@MainActor
final class DiscordAttentionModel: ObservableObject {
    @Published private(set) var notificationSequence: UInt64 = 0
    @Published private(set) var isIncomingCallActive = false

    private struct RailState: Equatable {
        let hasUnread: Bool
        let mentionCount: Int
    }

    private var previousRailState: [String: RailState]?
    private var lastNotificationTimestamp: TimeInterval?
    private let notificationCoalescingInterval: TimeInterval
    private let now: () -> TimeInterval

    init(
        notificationCoalescingInterval: TimeInterval = 0.75,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.notificationCoalescingInterval = max(0, notificationCoalescingInterval)
        self.now = now
    }

    func receiveRailItems(_ items: [DiscordRailItem]) {
        var state: [String: RailState] = [:]
        for item in items where item.kind != .action {
            state[item.id] = RailState(
                hasUnread: item.hasUnread,
                mentionCount: item.mentionCount ?? 0
            )
        }

        // Discord briefly removes its rail while logging in and while replacing
        // large parts of the app DOM. Treat the next populated report as a new
        // baseline so those rebuilds (and historical badges) never become alerts.
        guard !state.isEmpty else {
            previousRailState = nil
            return
        }
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
        guard isIncomingCallActive != isActive else { return }
        isIncomingCallActive = isActive
    }

    func receiveNotification() {
        signalNotification()
    }

    func reset() {
        previousRailState = nil
        lastNotificationTimestamp = nil
        isIncomingCallActive = false
    }

    private func signalNotification() {
        let timestamp = now()
        if let lastNotificationTimestamp,
           timestamp - lastNotificationTimestamp < notificationCoalescingInterval {
            return
        }
        lastNotificationTimestamp = timestamp
        notificationSequence &+= 1
    }
}
