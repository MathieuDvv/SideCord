import Combine
import Foundation

struct DiscordRailItem: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case directMessages
        case server
        case action
    }

    let id: String
    let title: String
    let iconURL: URL?
    let kind: Kind
    let isSelected: Bool
    let hasUnread: Bool
    let mentionCount: Int?
}

@MainActor
final class DiscordRailModel: ObservableObject {
    nonisolated static let maximumItemCount = 200
    nonisolated static let maximumIDLength = 128
    nonisolated static let maximumTitleLength = 120
    nonisolated static let maximumIconSourceLength = 256 * 1_024
    nonisolated static let maximumMentionCount = 9_999

    @Published private(set) var items: [DiscordRailItem]

    private weak var controller: DiscordWebController?

    init(controller: DiscordWebController? = nil, items: [DiscordRailItem] = []) {
        self.controller = controller
        self.items = Array(items.prefix(Self.maximumItemCount))
    }

    func activate(id: String) {
        guard items.contains(where: { $0.id == id }) else { return }
        controller?.activateRailItem(id: id)
    }

    func receive(messageItems: Any) {
        guard let decodedItems = Self.decode(messageItems) else { return }
        if items != decodedItems {
            items = decodedItems
        }
    }

    func reset() {
        if !items.isEmpty { items = [] }
    }

    static func decode(_ value: Any) -> [DiscordRailItem]? {
        guard let payload = value as? [Any],
              payload.count <= maximumItemCount
        else { return nil }

        var decodedItems: [DiscordRailItem] = []
        var identifiers = Set<String>()
        decodedItems.reserveCapacity(payload.count)

        for rawItem in payload {
            guard let dictionary = rawItem as? [String: Any],
                  let id = validatedID(dictionary["id"]),
                  identifiers.insert(id).inserted,
                  let title = validatedTitle(dictionary["title"]),
                  let kindValue = dictionary["kind"] as? String,
                  let kind = DiscordRailItem.Kind(rawValue: kindValue),
                  let isSelected = strictBoolean(dictionary["selected"]),
                  let hasUnread = strictBoolean(dictionary["unread"]),
                  let mentionCount = validatedMentionCount(dictionary["mentions"]),
                  let iconURL = validatedIconURL(dictionary["icon"])
            else { return nil }

            decodedItems.append(
                DiscordRailItem(
                    id: id,
                    title: title,
                    iconURL: iconURL,
                    kind: kind,
                    isSelected: isSelected,
                    hasUnread: hasUnread,
                    mentionCount: mentionCount
                )
            )
        }
        return decodedItems
    }

    private static func validatedID(_ value: Any?) -> String? {
        guard let id = value as? String,
              !id.isEmpty,
              id.count <= maximumIDLength,
              id.range(
                of: #"^[A-Za-z0-9:@._-]+$"#,
                options: .regularExpression
              ) != nil
        else { return nil }
        return id
    }

    private static func validatedTitle(_ value: Any?) -> String? {
        guard let rawTitle = value as? String else { return nil }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return String(title.prefix(maximumTitleLength))
    }

    private static func strictBoolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID()
        else { return nil }
        return number.boolValue
    }

    /// Returns a double optional so a missing/null icon is valid while an
    /// unsafe or malformed supplied icon rejects the message.
    private static func validatedIconURL(_ value: Any?) -> URL?? {
        guard let value, !(value is NSNull) else { return .some(nil) }
        guard let source = value as? String,
              !source.isEmpty,
              source.utf8.count <= maximumIconSourceLength,
              let url = URL(string: source)
        else { return nil }

        if url.scheme?.lowercased() == "data" {
            let lowercased = source.lowercased()
            let allowedPrefixes = [
                "data:image/png;base64,",
                "data:image/jpeg;base64,",
                "data:image/webp;base64,",
                "data:image/gif;base64,"
            ]
            return allowedPrefixes.contains(where: lowercased.hasPrefix)
                ? .some(url)
                : nil
        }

        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              let host = url.host?.lowercased(),
              isAllowedDiscordAssetHost(host)
        else { return nil }
        return .some(url)
    }

    /// Returns a double optional so null is distinct from an invalid value.
    private static func validatedMentionCount(_ value: Any?) -> Int?? {
        guard let value, !(value is NSNull) else { return .some(nil) }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        let doubleValue = number.doubleValue
        guard doubleValue.isFinite,
              doubleValue.rounded(.towardZero) == doubleValue,
              doubleValue > 0,
              doubleValue <= Double(maximumMentionCount)
        else { return nil }
        return .some(Int(doubleValue))
    }

    private static func isAllowedDiscordAssetHost(_ host: String) -> Bool {
        let allowedSuffixes = [
            "discord.com",
            "discordapp.com",
            "discordapp.net"
        ]
        return allowedSuffixes.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}
