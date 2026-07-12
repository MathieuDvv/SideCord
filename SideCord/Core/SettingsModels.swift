import Carbon.HIToolbox
import Foundation

enum SidebarEdge: String, CaseIterable, Codable, Identifiable, Sendable {
    case left
    case right

    var id: Self { self }

    var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        }
    }
}

enum CSSPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case standard = "default"
    case compact

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "Default"
        case .compact: "Compact"
        }
    }
}

enum DiscordLayoutMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case full
    case focus
    case reader
    case custom

    var id: Self { self }

    static let quickModes: [Self] = [.full, .focus, .reader]

    var title: String {
        switch self {
        case .full: "Full"
        case .focus: "Focus"
        case .reader: "Reader"
        case .custom: "Custom"
        }
    }

    var detail: String {
        switch self {
        case .full:
            "Keep Discord's navigation and controls visible."
        case .focus:
            "Give the conversation the full width while keeping message input."
        case .reader:
            "A distraction-free, read-only-looking layout that hides message input."
        case .custom:
            "A layout assembled from the individual controls below."
        }
    }
}

struct DiscordLayoutOptions: Codable, Equatable, Sendable {
    var hideServerRail: Bool
    var hideChannelList: Bool
    var hideMemberList: Bool
    var hideAccountDock: Bool
    var simplifyHeader: Bool
    var simplifyComposer: Bool
    var hideComposer: Bool
    var compactMedia: Bool
    var reduceMotion: Bool

    init(
        hideServerRail: Bool = false,
        hideChannelList: Bool = false,
        hideMemberList: Bool = false,
        hideAccountDock: Bool = false,
        simplifyHeader: Bool = false,
        simplifyComposer: Bool = false,
        hideComposer: Bool = false,
        compactMedia: Bool = false,
        reduceMotion: Bool = false
    ) {
        self.hideServerRail = hideServerRail
        self.hideChannelList = hideChannelList
        self.hideMemberList = hideMemberList
        self.hideAccountDock = hideAccountDock
        self.simplifyHeader = simplifyHeader
        self.simplifyComposer = simplifyComposer
        self.hideComposer = hideComposer
        self.compactMedia = compactMedia
        self.reduceMotion = reduceMotion
    }

    static let full = DiscordLayoutOptions()

    static let focus = DiscordLayoutOptions(
        hideServerRail: true,
        hideChannelList: true,
        hideMemberList: true,
        simplifyHeader: true,
        simplifyComposer: true
    )

    static let reader = DiscordLayoutOptions(
        hideServerRail: true,
        hideChannelList: true,
        hideMemberList: true,
        hideAccountDock: true,
        simplifyHeader: true,
        simplifyComposer: true,
        hideComposer: true
    )

    var isFull: Bool { self == .full }

    private enum CodingKeys: String, CodingKey {
        case hideServerRail
        case hideChannelList
        case hideMemberList
        case hideAccountDock
        case simplifyHeader
        case simplifyComposer
        case hideComposer
        case compactMedia
        case reduceMotion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hideServerRail = try container.decodeIfPresent(Bool.self, forKey: .hideServerRail) ?? false
        hideChannelList = try container.decodeIfPresent(Bool.self, forKey: .hideChannelList) ?? false
        hideMemberList = try container.decodeIfPresent(Bool.self, forKey: .hideMemberList) ?? false
        hideAccountDock = try container.decodeIfPresent(Bool.self, forKey: .hideAccountDock) ?? false
        simplifyHeader = try container.decodeIfPresent(Bool.self, forKey: .simplifyHeader) ?? false
        simplifyComposer = try container.decodeIfPresent(Bool.self, forKey: .simplifyComposer) ?? false
        hideComposer = try container.decodeIfPresent(Bool.self, forKey: .hideComposer) ?? false
        compactMedia = try container.decodeIfPresent(Bool.self, forKey: .compactMedia) ?? false
        reduceMotion = try container.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hideServerRail, forKey: .hideServerRail)
        try container.encode(hideChannelList, forKey: .hideChannelList)
        try container.encode(hideMemberList, forKey: .hideMemberList)
        try container.encode(hideAccountDock, forKey: .hideAccountDock)
        try container.encode(simplifyHeader, forKey: .simplifyHeader)
        try container.encode(simplifyComposer, forKey: .simplifyComposer)
        try container.encode(hideComposer, forKey: .hideComposer)
        try container.encode(compactMedia, forKey: .compactMedia)
        try container.encode(reduceMotion, forKey: .reduceMotion)
    }
}

struct ShortcutDefinition: Codable, Equatable, Hashable, Sendable {
    static let optionD = ShortcutDefinition(
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: UInt32(optionKey)
    )

    /// A hardware-independent Carbon virtual key code.
    var keyCode: UInt32

    /// Carbon modifier flags (`cmdKey`, `optionKey`, `controlKey`, and `shiftKey`).
    var modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    var isValid: Bool {
        let supportedModifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        return keyCode <= UInt32(UInt8.max)
            && modifiers & supportedModifiers != 0
            && modifiers & ~supportedModifiers == 0
    }

    var displayName: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += Self.keyLabel(for: keyCode)
        return result
    }

    private static func keyLabel(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: "A"
        case kVK_ANSI_B: "B"
        case kVK_ANSI_C: "C"
        case kVK_ANSI_D: "D"
        case kVK_ANSI_E: "E"
        case kVK_ANSI_F: "F"
        case kVK_ANSI_G: "G"
        case kVK_ANSI_H: "H"
        case kVK_ANSI_I: "I"
        case kVK_ANSI_J: "J"
        case kVK_ANSI_K: "K"
        case kVK_ANSI_L: "L"
        case kVK_ANSI_M: "M"
        case kVK_ANSI_N: "N"
        case kVK_ANSI_O: "O"
        case kVK_ANSI_P: "P"
        case kVK_ANSI_Q: "Q"
        case kVK_ANSI_R: "R"
        case kVK_ANSI_S: "S"
        case kVK_ANSI_T: "T"
        case kVK_ANSI_U: "U"
        case kVK_ANSI_V: "V"
        case kVK_ANSI_W: "W"
        case kVK_ANSI_X: "X"
        case kVK_ANSI_Y: "Y"
        case kVK_ANSI_Z: "Z"
        case kVK_ANSI_0: "0"
        case kVK_ANSI_1: "1"
        case kVK_ANSI_2: "2"
        case kVK_ANSI_3: "3"
        case kVK_ANSI_4: "4"
        case kVK_ANSI_5: "5"
        case kVK_ANSI_6: "6"
        case kVK_ANSI_7: "7"
        case kVK_ANSI_8: "8"
        case kVK_ANSI_9: "9"
        case kVK_Space: "Space"
        case kVK_Return: "Return"
        case kVK_Tab: "Tab"
        default: "Key \(keyCode)"
        }
    }
}
