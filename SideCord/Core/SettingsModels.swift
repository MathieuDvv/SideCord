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
            "Float navigation over the conversation and keep only essential message input."
        case .reader:
            "Hide navigation and message input for a distraction-free reading view."
        case .custom:
            "A layout assembled from the individual controls below."
        }
    }
}

enum DiscordNavigationPresentation: String, CaseIterable, Codable, Identifiable, Sendable {
    case docked
    case floating
    case hidden

    var id: Self { self }

    var title: String {
        switch self {
        case .docked: "Docked"
        case .floating: "Floating"
        case .hidden: "Hidden"
        }
    }
}

enum DiscordComposerMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case full
    case essential
    case hidden

    var id: Self { self }

    var title: String {
        switch self {
        case .full: "Full"
        case .essential: "Essential"
        case .hidden: "Hidden"
        }
    }
}

enum DiscordVisualTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case systemGlass
    case discord
    case oled
    case soft

    var id: Self { self }

    var title: String {
        switch self {
        case .systemGlass: "System Glass"
        case .discord: "Discord"
        case .oled: "OLED"
        case .soft: "Soft"
        }
    }
}

enum SideCordAccent: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic
    case blurple
    case blue
    case purple
    case pink
    case green
    case orange
    case white

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .blurple: "Blurple"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .green: "Green"
        case .orange: "Orange"
        case .white: "White"
        }
    }

    var colorDescriptor: SideCordColorDescriptor {
        switch self {
        case .automatic, .blurple: .init(red: 88, green: 101, blue: 242)
        case .blue: .init(red: 10, green: 132, blue: 255)
        case .purple: .init(red: 175, green: 82, blue: 222)
        case .pink: .init(red: 255, green: 45, blue: 85)
        case .green: .init(red: 48, green: 209, blue: 88)
        case .orange: .init(red: 255, green: 159, blue: 10)
        case .white: .init(red: 255, green: 255, blue: 255)
        }
    }
}

struct SideCordColorDescriptor: Equatable, Sendable {
    let red: Int
    let green: Int
    let blue: Int

    var redUnit: Double { Double(red) / 255 }
    var greenUnit: Double { Double(green) / 255 }
    var blueUnit: Double { Double(blue) / 255 }
    var cssHex: String { String(format: "#%02x%02x%02x", red, green, blue) }
    var cssRGB: String { "\(red) \(green) \(blue)" }
}

enum AttentionGlowColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case followTheme
    case blurple
    case blue
    case purple
    case pink
    case green
    case orange
    case white

    var id: Self { self }

    var title: String {
        switch self {
        case .followTheme: "Follow Theme"
        case .blurple: "Blurple"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .green: "Green"
        case .orange: "Orange"
        case .white: "White"
        }
    }

    func resolvedAccent(themeAccent: SideCordAccent) -> SideCordAccent {
        switch self {
        case .followTheme: themeAccent
        case .blurple: .blurple
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .green: .green
        case .orange: .orange
        case .white: .white
        }
    }
}

enum AttentionGlowStrength: String, CaseIterable, Codable, Identifiable, Sendable {
    case subtle
    case normal
    case strong

    var id: Self { self }

    var title: String {
        switch self {
        case .subtle: "Subtle"
        case .normal: "Normal"
        case .strong: "Strong"
        }
    }

    var intensity: Double {
        switch self {
        case .subtle: 0.68
        case .normal: 1
        case .strong: 1.8
        }
    }

    var glowWidth: CGFloat {
        switch self {
        case .subtle: 58
        case .normal: 72
        case .strong: 136
        }
    }
}

enum ThemeColorScheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

struct DiscordLayoutOptions: Codable, Equatable, Sendable {
    var navigationPresentation: DiscordNavigationPresentation
    var composerMode: DiscordComposerMode
    var hideMemberList: Bool
    var hideAccountDock: Bool
    var simplifyHeader: Bool
    var compactMedia: Bool
    var reduceMotion: Bool

    init(
        navigationPresentation: DiscordNavigationPresentation = .docked,
        composerMode: DiscordComposerMode = .full,
        hideMemberList: Bool = false,
        hideAccountDock: Bool = false,
        simplifyHeader: Bool = false,
        compactMedia: Bool = false,
        reduceMotion: Bool = false
    ) {
        self.navigationPresentation = navigationPresentation
        self.composerMode = composerMode
        self.hideMemberList = hideMemberList
        self.hideAccountDock = hideAccountDock
        self.simplifyHeader = simplifyHeader
        self.compactMedia = compactMedia
        self.reduceMotion = reduceMotion
    }

    static let full = DiscordLayoutOptions()

    static let focus = DiscordLayoutOptions(
        navigationPresentation: .floating,
        composerMode: .essential,
        hideMemberList: true,
        simplifyHeader: true
    )

    static let reader = DiscordLayoutOptions(
        navigationPresentation: .hidden,
        composerMode: .hidden,
        hideMemberList: true,
        hideAccountDock: true,
        simplifyHeader: true
    )

    var isFull: Bool { self == .full }

    private enum CodingKeys: String, CodingKey {
        case navigationPresentation
        case composerMode
        case hideMemberList
        case hideAccountDock
        case simplifyHeader
        case compactMedia
        case reduceMotion

        // v1 keys. Decode these for migration but never encode them.
        case hideServerRail
        case hideChannelList
        case simplifyComposer
        case hideComposer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func decode<T: Decodable>(_ type: T.Type, forKey key: CodingKeys) -> T? {
            try? container.decodeIfPresent(type, forKey: key)
        }

        if let storedPresentation = decode(
            DiscordNavigationPresentation.self,
            forKey: .navigationPresentation
        ) {
            navigationPresentation = storedPresentation
        } else {
            navigationPresentation = Self.migratedNavigationPresentation(
                hideServerRail: decode(Bool.self, forKey: .hideServerRail) ?? false,
                hideChannelList: decode(Bool.self, forKey: .hideChannelList) ?? false
            )
        }

        if let storedComposerMode = decode(DiscordComposerMode.self, forKey: .composerMode) {
            composerMode = storedComposerMode
        } else {
            composerMode = Self.migratedComposerMode(
                simplifyComposer: decode(Bool.self, forKey: .simplifyComposer) ?? false,
                hideComposer: decode(Bool.self, forKey: .hideComposer) ?? false
            )
        }

        hideMemberList = decode(Bool.self, forKey: .hideMemberList) ?? false
        hideAccountDock = decode(Bool.self, forKey: .hideAccountDock) ?? false
        simplifyHeader = decode(Bool.self, forKey: .simplifyHeader) ?? false
        compactMedia = decode(Bool.self, forKey: .compactMedia) ?? false
        reduceMotion = decode(Bool.self, forKey: .reduceMotion) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(navigationPresentation, forKey: .navigationPresentation)
        try container.encode(composerMode, forKey: .composerMode)
        try container.encode(hideMemberList, forKey: .hideMemberList)
        try container.encode(hideAccountDock, forKey: .hideAccountDock)
        try container.encode(simplifyHeader, forKey: .simplifyHeader)
        try container.encode(compactMedia, forKey: .compactMedia)
        try container.encode(reduceMotion, forKey: .reduceMotion)
    }

    private static func migratedNavigationPresentation(
        hideServerRail: Bool,
        hideChannelList: Bool
    ) -> DiscordNavigationPresentation {
        switch (hideServerRail, hideChannelList) {
        case (false, false): .docked
        case (true, true): .hidden
        default: .floating
        }
    }

    private static func migratedComposerMode(
        simplifyComposer: Bool,
        hideComposer: Bool
    ) -> DiscordComposerMode {
        if hideComposer { return .hidden }
        if simplifyComposer { return .essential }
        return .full
    }

    // These projections keep v1 call sites source-compatible while UI and CSS
    // consumers move to the richer v2 enums. They are not part of persistence.
    @available(*, deprecated, message: "Use navigationPresentation")
    var hideServerRail: Bool {
        get { navigationPresentation != .docked }
        set {
            navigationPresentation = Self.migratedNavigationPresentation(
                hideServerRail: newValue,
                hideChannelList: hideChannelList
            )
        }
    }

    @available(*, deprecated, message: "Use navigationPresentation")
    var hideChannelList: Bool {
        get { navigationPresentation == .hidden }
        set {
            navigationPresentation = Self.migratedNavigationPresentation(
                hideServerRail: hideServerRail,
                hideChannelList: newValue
            )
        }
    }

    @available(*, deprecated, message: "Use composerMode")
    var simplifyComposer: Bool {
        get { composerMode == .essential }
        set {
            guard composerMode != .hidden else { return }
            composerMode = newValue ? .essential : .full
        }
    }

    @available(*, deprecated, message: "Use composerMode")
    var hideComposer: Bool {
        get { composerMode == .hidden }
        set {
            if newValue {
                composerMode = .hidden
            } else if composerMode == .hidden {
                composerMode = .full
            }
        }
    }

    @available(*, deprecated, message: "Use the v2 initializer")
    init(
        hideServerRail: Bool,
        hideChannelList: Bool,
        hideMemberList: Bool = false,
        hideAccountDock: Bool = false,
        simplifyHeader: Bool = false,
        simplifyComposer: Bool = false,
        hideComposer: Bool = false,
        compactMedia: Bool = false,
        reduceMotion: Bool = false
    ) {
        navigationPresentation = Self.migratedNavigationPresentation(
            hideServerRail: hideServerRail,
            hideChannelList: hideChannelList
        )
        composerMode = Self.migratedComposerMode(
            simplifyComposer: simplifyComposer,
            hideComposer: hideComposer
        )
        self.hideMemberList = hideMemberList
        self.hideAccountDock = hideAccountDock
        self.simplifyHeader = simplifyHeader
        self.compactMedia = compactMedia
        self.reduceMotion = reduceMotion
    }
}

struct ShortcutDefinition: Codable, Equatable, Hashable, Sendable {
    static let optionD = ShortcutDefinition(
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: UInt32(optionKey)
    )

    static let optionShiftD = ShortcutDefinition(
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: UInt32(optionKey | shiftKey)
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
