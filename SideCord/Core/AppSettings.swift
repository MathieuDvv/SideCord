import Combine
import CoreGraphics
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let defaultSidebarWidth: CGFloat = 420
    static let minimumSidebarWidth: CGFloat = 320
    static let maximumStoredSidebarWidth: CGFloat = 4_096
    static let defaultSidebarInset: CGFloat = 16
    static let sidebarInsetRange: ClosedRange<CGFloat> = 0 ... 48
    static let defaultHoverDwellDelay: TimeInterval = 0.25
    static let defaultRetractionDelay: TimeInterval = 0.7
    static let defaultThemeIntensity = 1.0

    private static let hoverDwellRange: ClosedRange<TimeInterval> = 0 ... 2
    private static let retractionRange: ClosedRange<TimeInterval> = 0 ... 10
    private static let themeIntensityRange = 0.0 ... 1.0

    @Published var sidebarEdge: SidebarEdge {
        didSet { defaults.set(sidebarEdge.rawValue, forKey: Keys.sidebarEdge) }
    }

    @Published var edgeHoverEnabled: Bool {
        didSet { defaults.set(edgeHoverEnabled, forKey: Keys.edgeHoverEnabled) }
    }

    @Published var notificationGlowEnabled: Bool {
        didSet {
            defaults.set(notificationGlowEnabled, forKey: Keys.notificationGlowEnabled)
        }
    }

    @Published var attentionGlowColor: AttentionGlowColor {
        didSet { defaults.set(attentionGlowColor.rawValue, forKey: Keys.attentionGlowColor) }
    }

    @Published var attentionGlowStrength: AttentionGlowStrength {
        didSet { defaults.set(attentionGlowStrength.rawValue, forKey: Keys.attentionGlowStrength) }
    }

    @Published var incomingCallCardEnabled: Bool {
        didSet { defaults.set(incomingCallCardEnabled, forKey: Keys.incomingCallCardEnabled) }
    }

    @Published var hoverDwellDelay: TimeInterval {
        didSet {
            let validated = Self.validatedDelay(
                hoverDwellDelay,
                defaultValue: Self.defaultHoverDwellDelay,
                range: Self.hoverDwellRange
            )
            guard validated == hoverDwellDelay else {
                hoverDwellDelay = validated
                defaults.set(validated, forKey: Keys.hoverDwellDelay)
                return
            }
            defaults.set(validated, forKey: Keys.hoverDwellDelay)
        }
    }

    @Published var retractionDelay: TimeInterval {
        didSet {
            let validated = Self.validatedDelay(
                retractionDelay,
                defaultValue: Self.defaultRetractionDelay,
                range: Self.retractionRange
            )
            guard validated == retractionDelay else {
                retractionDelay = validated
                defaults.set(validated, forKey: Keys.retractionDelay)
                return
            }
            defaults.set(validated, forKey: Keys.retractionDelay)
        }
    }

    @Published var sidebarWidth: CGFloat {
        didSet {
            let validated = Self.validatedWidth(sidebarWidth)
            guard validated == sidebarWidth else {
                sidebarWidth = validated
                defaults.set(Double(validated), forKey: Keys.sidebarWidth)
                return
            }
            defaults.set(Double(validated), forKey: Keys.sidebarWidth)
        }
    }

    @Published var sidebarInset: CGFloat {
        didSet {
            let validated = Self.validatedInset(sidebarInset)
            guard validated == sidebarInset else {
                sidebarInset = validated
                defaults.set(Double(validated), forKey: Keys.sidebarInset)
                return
            }
            defaults.set(Double(validated), forKey: Keys.sidebarInset)
        }
    }

    @Published var cssPreset: CSSPreset {
        didSet { defaults.set(cssPreset.rawValue, forKey: Keys.cssPreset) }
    }

    @Published var discordLayoutMode: DiscordLayoutMode {
        didSet { defaults.set(discordLayoutMode.rawValue, forKey: Keys.discordLayoutMode) }
    }

    @Published var customDiscordLayoutOptions: DiscordLayoutOptions {
        didSet {
            if let data = try? JSONEncoder().encode(customDiscordLayoutOptions) {
                defaults.set(data, forKey: Keys.customDiscordLayoutOptions)
            }
        }
    }

    @Published var floatingRailEnabled: Bool {
        didSet { defaults.set(floatingRailEnabled, forKey: Keys.floatingRailEnabled) }
    }

    @Published var visualTheme: DiscordVisualTheme {
        didSet { defaults.set(visualTheme.rawValue, forKey: Keys.visualTheme) }
    }

    @Published var themeAccent: SideCordAccent {
        didSet { defaults.set(themeAccent.rawValue, forKey: Keys.themeAccent) }
    }

    @Published var themeIntensity: Double {
        didSet {
            let validated = Self.validatedThemeIntensity(themeIntensity)
            guard validated == themeIntensity else {
                themeIntensity = validated
                defaults.set(validated, forKey: Keys.themeIntensity)
                return
            }
            defaults.set(validated, forKey: Keys.themeIntensity)
        }
    }

    @Published var themeColorScheme: ThemeColorScheme {
        didSet { defaults.set(themeColorScheme.rawValue, forKey: Keys.themeColorScheme) }
    }

    @Published var customCSS: String {
        didSet { defaults.set(customCSS, forKey: Keys.customCSS) }
    }

    @Published var customCSSEnabled: Bool {
        didSet { defaults.set(customCSSEnabled, forKey: Keys.customCSSEnabled) }
    }

    @Published var launchAtLoginEnabled: Bool {
        didSet { defaults.set(launchAtLoginEnabled, forKey: Keys.launchAtLoginEnabled) }
    }

    @Published var shortcut: ShortcutDefinition {
        didSet {
            guard shortcut.isValid else {
                shortcut = oldValue.isValid ? oldValue : .optionD
                return
            }
            defaults.set(Int(shortcut.keyCode), forKey: Keys.shortcutKeyCode)
            defaults.set(Int(shortcut.modifiers), forKey: Keys.shortcutModifiers)
        }
    }

    @Published var navigationShortcut: ShortcutDefinition {
        didSet {
            guard navigationShortcut.isValid else {
                navigationShortcut = oldValue.isValid ? oldValue : .optionShiftD
                return
            }
            defaults.set(
                Int(navigationShortcut.keyCode),
                forKey: Keys.navigationShortcutKeyCode
            )
            defaults.set(
                Int(navigationShortcut.modifiers),
                forKey: Keys.navigationShortcutModifiers
            )
        }
    }

    @Published var isPinned: Bool {
        didSet { defaults.set(isPinned, forKey: Keys.isPinned) }
    }

    @Published private(set) var displayWidths: [String: CGFloat]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        sidebarEdge = defaults.string(forKey: Keys.sidebarEdge)
            .flatMap(SidebarEdge.init(rawValue:)) ?? .right
        edgeHoverEnabled = Self.bool(
            forKey: Keys.edgeHoverEnabled,
            in: defaults,
            defaultValue: true
        )
        notificationGlowEnabled = Self.bool(
            forKey: Keys.notificationGlowEnabled,
            in: defaults,
            defaultValue: true
        )
        attentionGlowColor = defaults.string(forKey: Keys.attentionGlowColor)
            .flatMap(AttentionGlowColor.init(rawValue:)) ?? .followTheme
        attentionGlowStrength = defaults.string(forKey: Keys.attentionGlowStrength)
            .flatMap(AttentionGlowStrength.init(rawValue:)) ?? .normal
        incomingCallCardEnabled = Self.bool(
            forKey: Keys.incomingCallCardEnabled,
            in: defaults,
            defaultValue: true
        )
        hoverDwellDelay = Self.validatedDelay(
            Self.double(forKey: Keys.hoverDwellDelay, in: defaults)
                ?? Self.defaultHoverDwellDelay,
            defaultValue: Self.defaultHoverDwellDelay,
            range: Self.hoverDwellRange
        )
        retractionDelay = Self.validatedDelay(
            Self.double(forKey: Keys.retractionDelay, in: defaults)
                ?? Self.defaultRetractionDelay,
            defaultValue: Self.defaultRetractionDelay,
            range: Self.retractionRange
        )
        sidebarWidth = Self.validatedWidth(
            Self.double(forKey: Keys.sidebarWidth, in: defaults)
                .map { CGFloat($0) } ?? Self.defaultSidebarWidth
        )
        sidebarInset = Self.validatedInset(
            Self.double(forKey: Keys.sidebarInset, in: defaults)
                .map { CGFloat($0) } ?? Self.defaultSidebarInset
        )
        cssPreset = defaults.string(forKey: Keys.cssPreset)
            .flatMap(CSSPreset.init(rawValue:)) ?? .compact
        let storedLayoutMode = defaults.string(forKey: Keys.discordLayoutMode)
            .flatMap(DiscordLayoutMode.init(rawValue:)) ?? .full
        let storedCustomLayoutOptions = defaults.data(forKey: Keys.customDiscordLayoutOptions)
            .flatMap { try? JSONDecoder().decode(DiscordLayoutOptions.self, from: $0) }
        discordLayoutMode = storedLayoutMode == .custom && storedCustomLayoutOptions == nil
            ? .full
            : storedLayoutMode
        customDiscordLayoutOptions = storedCustomLayoutOptions ?? .full
        floatingRailEnabled = Self.bool(
            forKey: Keys.floatingRailEnabled,
            in: defaults,
            defaultValue: true
        )
        if let storedTheme = defaults.string(forKey: Keys.visualTheme) {
            visualTheme = DiscordVisualTheme(rawValue: storedTheme) ?? .systemGlass
        } else {
            visualTheme = defaults.bool(forKey: OnboardingKeys.completed)
                ? .discord
                : .systemGlass
        }
        themeAccent = defaults.string(forKey: Keys.themeAccent)
            .flatMap(SideCordAccent.init(rawValue:)) ?? .automatic
        themeIntensity = Self.validatedThemeIntensity(
            Self.double(forKey: Keys.themeIntensity, in: defaults)
                ?? Self.defaultThemeIntensity
        )
        themeColorScheme = defaults.string(forKey: Keys.themeColorScheme)
            .flatMap(ThemeColorScheme.init(rawValue:)) ?? .system
        customCSS = defaults.string(forKey: Keys.customCSS) ?? ""
        customCSSEnabled = Self.bool(
            forKey: Keys.customCSSEnabled,
            in: defaults,
            defaultValue: false
        )
        launchAtLoginEnabled = Self.bool(
            forKey: Keys.launchAtLoginEnabled,
            in: defaults,
            defaultValue: false
        )

        let storedSidebarShortcut = Self.loadShortcut(
            from: defaults,
            keyCodeKey: Keys.shortcutKeyCode,
            modifiersKey: Keys.shortcutModifiers,
            fallback: .optionD
        )
        shortcut = storedSidebarShortcut
        let storedNavigationShortcut = Self.loadShortcut(
            from: defaults,
            keyCodeKey: Keys.navigationShortcutKeyCode,
            modifiersKey: Keys.navigationShortcutModifiers,
            fallback: .optionShiftD
        )
        navigationShortcut = storedNavigationShortcut == storedSidebarShortcut
            ? (storedSidebarShortcut == .optionShiftD ? .optionD : .optionShiftD)
            : storedNavigationShortcut

        isPinned = Self.bool(
            forKey: Keys.isPinned,
            in: defaults,
            defaultValue: false
        )
        displayWidths = Self.loadDisplayWidths(from: defaults)

        // Repair normalized values on load so a corrupt preference does not
        // repeatedly fall through to a different in-memory value every launch.
        defaults.set(sidebarEdge.rawValue, forKey: Keys.sidebarEdge)
        defaults.set(edgeHoverEnabled, forKey: Keys.edgeHoverEnabled)
        defaults.set(notificationGlowEnabled, forKey: Keys.notificationGlowEnabled)
        defaults.set(attentionGlowColor.rawValue, forKey: Keys.attentionGlowColor)
        defaults.set(attentionGlowStrength.rawValue, forKey: Keys.attentionGlowStrength)
        defaults.set(incomingCallCardEnabled, forKey: Keys.incomingCallCardEnabled)
        defaults.set(hoverDwellDelay, forKey: Keys.hoverDwellDelay)
        defaults.set(retractionDelay, forKey: Keys.retractionDelay)
        defaults.set(Double(sidebarWidth), forKey: Keys.sidebarWidth)
        defaults.set(Double(sidebarInset), forKey: Keys.sidebarInset)
        defaults.set(cssPreset.rawValue, forKey: Keys.cssPreset)
        defaults.set(discordLayoutMode.rawValue, forKey: Keys.discordLayoutMode)
        defaults.set(floatingRailEnabled, forKey: Keys.floatingRailEnabled)
        defaults.set(visualTheme.rawValue, forKey: Keys.visualTheme)
        defaults.set(themeAccent.rawValue, forKey: Keys.themeAccent)
        defaults.set(themeIntensity, forKey: Keys.themeIntensity)
        defaults.set(themeColorScheme.rawValue, forKey: Keys.themeColorScheme)
        Self.persist(
            shortcut,
            keyCodeKey: Keys.shortcutKeyCode,
            modifiersKey: Keys.shortcutModifiers,
            in: defaults
        )
        Self.persist(
            navigationShortcut,
            keyCodeKey: Keys.navigationShortcutKeyCode,
            modifiersKey: Keys.navigationShortcutModifiers,
            in: defaults
        )
        if storedLayoutMode == .custom, storedCustomLayoutOptions == nil {
            defaults.set(DiscordLayoutMode.full.rawValue, forKey: Keys.discordLayoutMode)
            if let repairedData = try? JSONEncoder().encode(DiscordLayoutOptions.full) {
                defaults.set(repairedData, forKey: Keys.customDiscordLayoutOptions)
            }
        }
        if let storedCustomLayoutOptions,
           let migratedData = try? JSONEncoder().encode(storedCustomLayoutOptions) {
            defaults.set(migratedData, forKey: Keys.customDiscordLayoutOptions)
        }
    }

    func width(forDisplay displayID: String) -> CGFloat {
        displayWidths[displayID] ?? sidebarWidth
    }

    var discordLayoutOptions: DiscordLayoutOptions {
        switch discordLayoutMode {
        case .full: .full
        case .focus: .focus
        case .reader: .reader
        case .custom: customDiscordLayoutOptions
        }
    }

    func applyDiscordLayoutMode(_ mode: DiscordLayoutMode) {
        discordLayoutMode = mode
    }

    func setDiscordLayoutOption(
        _ keyPath: WritableKeyPath<DiscordLayoutOptions, Bool>,
        enabled: Bool
    ) {
        var options = discordLayoutOptions
        options[keyPath: keyPath] = enabled
        customDiscordLayoutOptions = options
        discordLayoutMode = .custom
    }

    func setWidth(_ width: CGFloat, forDisplay displayID: String) {
        guard !displayID.isEmpty else { return }
        displayWidths[displayID] = Self.validatedWidth(width)
        persistDisplayWidths()
    }

    func resetWidth(forDisplay displayID: String) {
        displayWidths.removeValue(forKey: displayID)
        persistDisplayWidths()
    }

    func resetAllDisplayWidths() {
        displayWidths.removeAll()
        defaults.removeObject(forKey: Keys.displayWidths)
    }

    func resetDiscordLayoutSettings() {
        cssPreset = .compact
        discordLayoutMode = .full
        customDiscordLayoutOptions = .full
        floatingRailEnabled = true
    }

    func resetAppearanceSettings() {
        visualTheme = .systemGlass
        themeAccent = .automatic
        themeIntensity = Self.defaultThemeIntensity
        themeColorScheme = .system
    }

    func resetToDefaults() {
        sidebarEdge = .right
        edgeHoverEnabled = true
        notificationGlowEnabled = true
        attentionGlowColor = .followTheme
        attentionGlowStrength = .normal
        incomingCallCardEnabled = true
        hoverDwellDelay = Self.defaultHoverDwellDelay
        retractionDelay = Self.defaultRetractionDelay
        sidebarWidth = Self.defaultSidebarWidth
        sidebarInset = Self.defaultSidebarInset
        resetDiscordLayoutSettings()
        resetAppearanceSettings()
        customCSS = ""
        customCSSEnabled = false
        launchAtLoginEnabled = false
        shortcut = .optionD
        navigationShortcut = .optionShiftD
        isPinned = false
        resetAllDisplayWidths()
    }

    func reset() {
        resetToDefaults()
    }

    private func persistDisplayWidths() {
        defaults.set(
            displayWidths.mapValues(Double.init),
            forKey: Keys.displayWidths
        )
    }

    private static func loadDisplayWidths(from defaults: UserDefaults) -> [String: CGFloat] {
        guard let stored = defaults.dictionary(forKey: Keys.displayWidths) else { return [:] }

        return stored.reduce(into: [:]) { result, element in
            guard !element.key.isEmpty,
                  let number = element.value as? NSNumber
            else { return }
            result[element.key] = validatedWidth(CGFloat(number.doubleValue))
        }
    }

    private static func validatedWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite else { return defaultSidebarWidth }
        return min(max(width, minimumSidebarWidth), maximumStoredSidebarWidth)
    }

    private static func validatedInset(_ inset: CGFloat) -> CGFloat {
        guard inset.isFinite else { return defaultSidebarInset }
        return min(max(inset, sidebarInsetRange.lowerBound), sidebarInsetRange.upperBound)
    }

    private static func validatedThemeIntensity(_ intensity: Double) -> Double {
        guard intensity.isFinite else { return defaultThemeIntensity }
        return min(
            max(intensity, themeIntensityRange.lowerBound),
            themeIntensityRange.upperBound
        )
    }

    private static func validatedDelay(
        _ delay: TimeInterval,
        defaultValue: TimeInterval,
        range: ClosedRange<TimeInterval>
    ) -> TimeInterval {
        guard delay.isFinite else { return defaultValue }
        return min(max(delay, range.lowerBound), range.upperBound)
    }

    private static func bool(
        forKey key: String,
        in defaults: UserDefaults,
        defaultValue: Bool
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private static func double(forKey key: String, in defaults: UserDefaults) -> Double? {
        guard let number = defaults.object(forKey: key) as? NSNumber else { return nil }
        return number.doubleValue
    }

    private static func loadShortcut(
        from defaults: UserDefaults,
        keyCodeKey: String,
        modifiersKey: String,
        fallback: ShortcutDefinition
    ) -> ShortcutDefinition {
        guard let keyCodeNumber = defaults.object(forKey: keyCodeKey) as? NSNumber,
              let modifiersNumber = defaults.object(forKey: modifiersKey) as? NSNumber,
              (0 ... Int64(UInt8.max)).contains(keyCodeNumber.int64Value),
              (0 ... Int64(UInt32.max)).contains(modifiersNumber.int64Value)
        else { return fallback }

        let stored = ShortcutDefinition(
            keyCode: UInt32(keyCodeNumber.int64Value),
            modifiers: UInt32(modifiersNumber.int64Value)
        )
        return stored.isValid ? stored : fallback
    }

    private static func persist(
        _ shortcut: ShortcutDefinition,
        keyCodeKey: String,
        modifiersKey: String,
        in defaults: UserDefaults
    ) {
        defaults.set(Int(shortcut.keyCode), forKey: keyCodeKey)
        defaults.set(Int(shortcut.modifiers), forKey: modifiersKey)
    }

    private enum Keys {
        static let sidebarEdge = "settings.sidebarEdge"
        static let edgeHoverEnabled = "settings.edgeHoverEnabled"
        static let notificationGlowEnabled = "settings.notificationGlowEnabled"
        static let attentionGlowColor = "settings.attentionGlowColor"
        static let attentionGlowStrength = "settings.attentionGlowStrength"
        static let incomingCallCardEnabled = "settings.incomingCallCardEnabled"
        static let hoverDwellDelay = "settings.hoverDwellDelay"
        static let retractionDelay = "settings.retractionDelay"
        static let sidebarWidth = "settings.sidebarWidth"
        static let sidebarInset = "settings.sidebarInset"
        static let displayWidths = "settings.displayWidths"
        static let cssPreset = "settings.cssPreset"
        static let discordLayoutMode = "settings.discordLayoutMode"
        static let customDiscordLayoutOptions = "settings.customDiscordLayoutOptions"
        static let floatingRailEnabled = "settings.floatingRailEnabled"
        static let visualTheme = "settings.visualTheme"
        static let themeAccent = "settings.themeAccent"
        static let themeIntensity = "settings.themeIntensity"
        static let themeColorScheme = "settings.themeColorScheme"
        static let customCSS = "settings.customCSS"
        static let customCSSEnabled = "settings.customCSSEnabled"
        static let launchAtLoginEnabled = "settings.launchAtLoginEnabled"
        static let shortcutKeyCode = "settings.shortcut.keyCode"
        static let shortcutModifiers = "settings.shortcut.modifiers"
        static let navigationShortcutKeyCode = "settings.navigationShortcut.keyCode"
        static let navigationShortcutModifiers = "settings.navigationShortcut.modifiers"
        static let isPinned = "settings.isPinned"
    }

    private enum OnboardingKeys {
        static let completed = "onboarding.completed"
    }
}
