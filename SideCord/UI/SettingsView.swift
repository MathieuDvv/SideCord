import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let webController: DiscordWebController
    @ObservedObject var launchAtLoginController: LaunchAtLoginController
    let onShortcutChanged: (ShortcutDefinition) throws -> Void
    let onNavigationShortcutChanged: (ShortcutDefinition) throws -> Void
    let onShortcutsReset: () throws -> Void

    @State private var selection: SettingsSection = .general
    @State private var showingResetConfirmation = false
    @State private var shortcutDraft: ShortcutDefinition
    @State private var navigationShortcutDraft: ShortcutDefinition
    @State private var presentedError: PresentedSettingsError?

    init(
        settings: AppSettings,
        webController: DiscordWebController,
        launchAtLoginController: LaunchAtLoginController,
        onShortcutChanged: @escaping (ShortcutDefinition) throws -> Void,
        onNavigationShortcutChanged: @escaping (ShortcutDefinition) throws -> Void,
        onShortcutsReset: @escaping () throws -> Void
    ) {
        self.settings = settings
        self.webController = webController
        self.launchAtLoginController = launchAtLoginController
        self.onShortcutChanged = onShortcutChanged
        self.onNavigationShortcutChanged = onNavigationShortcutChanged
        self.onShortcutsReset = onShortcutsReset
        _shortcutDraft = State(initialValue: settings.shortcut)
        _navigationShortcutDraft = State(initialValue: settings.navigationShortcut)
    }

    var body: some View {
        NavigationSplitView {
            settingsSidebar
        } detail: {
            settingsDetail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, idealWidth: 980, minHeight: 620, idealHeight: 720)
        .tint(settings.themeAccent.settingsColor)
        .preferredColorScheme(settings.themeColorScheme.settingsColorScheme)
        .onAppear {
            launchAtLoginController.refresh()
            settings.launchAtLoginEnabled = launchAtLoginController.isEnabled
                || launchAtLoginController.requiresApproval
            shortcutDraft = settings.shortcut
            navigationShortcutDraft = settings.navigationShortcut
        }
        .confirmationDialog(
            "Reset every SideCord preference?",
            isPresented: $showingResetConfirmation
        ) {
            Button("Reset Settings", role: .destructive) {
                resetSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores the sidebar, Discord layout, themes, CSS, and shortcuts to their defaults.")
        }
        .alert(item: $presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var settingsSidebar: some View {
        List(SettingsSection.allCases, selection: $selection) { section in
            HStack(spacing: 11) {
                SettingsSymbolTile(
                    symbol: section.symbol,
                    tint: section.tint,
                    size: 28
                )

                Text(section.title)
                    .fontWeight(selection == section ? .semibold : .regular)
            }
            .padding(.vertical, 3)
            .tag(section)
            .accessibilityLabel(section.title)
        }
        .listStyle(.sidebar)
        .navigationTitle("SideCord")
        .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 250)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Private by design", systemImage: "lock.shield.fill")
                    .font(.caption.weight(.semibold))
                Text("Previews are schematic and never display Discord content.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var settingsDetail: some View {
        ZStack {
            SettingsBackdrop(tint: selection.tint)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SettingsPageHeader(
                        title: selection.title,
                        subtitle: selection.subtitle,
                        symbol: selection.symbol,
                        tint: selection.tint
                    )

                    selectedPage
                }
                .frame(maxWidth: 980, alignment: .leading)
                .padding(.horizontal, 34)
                .padding(.top, 30)
                .padding(.bottom, 44)
            }
        }
    }

    @ViewBuilder
    private var selectedPage: some View {
        switch selection {
        case .general:
            generalPage
        case .sidebar:
            sidebarPage
        case .discordLayout:
            discordLayoutPage
        case .themes:
            themesPage
        case .advanced:
            advancedPage
        case .about:
            aboutPage
        }
    }

    private var generalPage: some View {
        VStack(spacing: 18) {
            SettingsGlassCard(
                title: "At a glance",
                subtitle: "SideCord stays ready without taking over your desktop.",
                symbol: "sparkles.rectangle.stack.fill",
                tint: .indigo
            ) {
                HStack(spacing: 22) {
                    StatusPill(
                        title: settings.isPinned ? "Pinned" : "Auto-retract",
                        symbol: settings.isPinned ? "pin.fill" : "arrow.right.to.line.compact",
                        tint: settings.isPinned ? .orange : .blue
                    )
                    StatusPill(
                        title: settings.sidebarEdge.title + " edge",
                        symbol: settings.sidebarEdge == .left ? "sidebar.left" : "sidebar.right",
                        tint: .purple
                    )
                    StatusPill(
                        title: settings.discordLayoutMode.title,
                        symbol: "message.fill",
                        tint: .green
                    )
                    Spacer(minLength: 0)
                }
            }

            SettingsGlassCard(
                title: "Presence",
                subtitle: "Choose when SideCord is available and how long it stays open.",
                symbol: "menubar.rectangle",
                tint: .blue
            ) {
                SettingsToggleRow(
                    title: "Keep the sidebar visible",
                    detail: "Pin SideCord above your other windows until you dismiss it.",
                    symbol: "pin.fill",
                    tint: .orange,
                    isOn: $settings.isPinned
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "Launch at login",
                    detail: "Make SideCord available from the menu bar when you sign in.",
                    symbol: "power",
                    tint: .green,
                    isOn: launchAtLoginBinding
                )

                if launchAtLoginController.requiresApproval {
                    Label(
                        "Waiting for approval in System Settings → General → Login Items",
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
                }
            }
        }
    }

    private var sidebarPage: some View {
        VStack(spacing: 18) {
            SettingsGlassCard(
                title: "Position",
                subtitle: "The reveal zone remains on the display edge while the panel floats inside it.",
                symbol: "rectangle.inset.filled.and.person.filled",
                tint: .purple
            ) {
                LabeledContent("Screen edge") {
                    Picker("Screen edge", selection: $settings.sidebarEdge) {
                        Label("Left", systemImage: "sidebar.left").tag(SidebarEdge.left)
                        Label("Right", systemImage: "sidebar.right").tag(SidebarEdge.right)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                SettingsDivider()

                ValueSliderRow(
                    title: "Default width",
                    detail: "Changing this resets widths remembered for individual displays.",
                    value: sidebarWidthBinding,
                    range: 320 ... 900,
                    step: 20,
                    valueText: "\(Int(settings.sidebarWidth)) pt"
                )

                SettingsDivider()

                ValueSliderRow(
                    title: "Floating inset",
                    detail: "Adds breathing room and reveals the panel shadow and rounded corners.",
                    value: $settings.sidebarInset,
                    range: AppSettings.sidebarInsetRange,
                    step: 4,
                    valueText: "\(Int(settings.sidebarInset)) pt"
                )
            }

            SettingsGlassCard(
                title: "Edge reveal",
                subtitle: "Tune the gesture so it feels deliberate without slowing you down.",
                symbol: "cursorarrow.motionlines",
                tint: .cyan
            ) {
                SettingsToggleRow(
                    title: "Reveal when the pointer rests at the edge",
                    detail: "The reveal zone follows the selected screen edge on every display.",
                    symbol: "cursorarrow.rays",
                    tint: .cyan,
                    isOn: $settings.edgeHoverEnabled
                )

                SettingsDivider()

                ValueSliderRow(
                    title: "Hover dwell",
                    detail: "How long the pointer waits before revealing SideCord.",
                    value: $settings.hoverDwellDelay,
                    range: 0.1 ... 1.0,
                    step: 0.05,
                    valueText: settings.hoverDwellDelay.formatted(
                        .number.precision(.fractionLength(2))
                    ) + " s"
                )
                .disabled(!settings.edgeHoverEnabled)
                .opacity(settings.edgeHoverEnabled ? 1 : 0.55)

                SettingsDivider()

                ValueSliderRow(
                    title: "Retraction delay",
                    detail: "How long SideCord waits after you leave the panel.",
                    value: $settings.retractionDelay,
                    range: 0.2 ... 3.0,
                    step: 0.1,
                    valueText: settings.retractionDelay.formatted(
                        .number.precision(.fractionLength(1))
                    ) + " s"
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "Glow for Discord activity",
                    detail: "Pulses for new activity and breathes while an incoming call rings.",
                    symbol: "sparkles",
                    tint: .indigo,
                    isOn: $settings.notificationGlowEnabled
                )
            }
        }
    }

    private var discordLayoutPage: some View {
        VStack(spacing: 18) {
            SettingsGlassCard(
                title: "Layout presets",
                subtitle: "Start with a complete workspace, then fine-tune it below.",
                symbol: "rectangle.3.group.fill",
                tint: .indigo
            ) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 215), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(DiscordLayoutMode.allCases) { mode in
                        LayoutPresetCard(
                            mode: mode,
                            options: layoutOptions(for: mode),
                            isSelected: settings.discordLayoutMode == mode,
                            action: { settings.applyDiscordLayoutMode(mode) }
                        )
                    }
                }

                Label(
                    "These previews are abstract diagrams. SideCord never captures message content.",
                    systemImage: "eye.slash.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }

            SettingsGlassCard(
                title: "Navigation",
                subtitle: "Keep server switching outside the SideCord window and choose how channels appear.",
                symbol: "sidebar.leading",
                tint: .blue
            ) {
                FloatingRailSchematic(
                    edge: settings.sidebarEdge,
                    isEnabled: settings.floatingRailEnabled
                )
                .frame(height: 92)
                .accessibilityHidden(true)

                SettingsToggleRow(
                    title: "Floating server rail",
                    detail: "Show servers and direct messages in a separate strip beside the SideCord window. Turn this off to hide the strip completely.",
                    symbol: "rectangle.portrait.on.rectangle.portrait.angled.fill",
                    tint: .indigo,
                    isOn: $settings.floatingRailEnabled
                )

                SettingsDivider()

                Picker(
                    "Navigation presentation",
                    selection: discordLayoutBinding(\.navigationPresentation)
                ) {
                    ForEach(navigationPresentations, id: \.self) { presentation in
                        Text(presentation.settingsTitle).tag(presentation)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.discordLayoutOptions.navigationPresentation.settingsDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)

                SettingsDivider()

                SettingsToggleRow(
                    title: "Hide the member list",
                    detail: "Give messages more horizontal room in busy channels.",
                    symbol: "person.2.slash.fill",
                    tint: .blue,
                    isOn: discordLayoutBinding(\.hideMemberList)
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "Hide the account and voice dock",
                    detail: "Remove the profile and voice controls from the navigation area.",
                    symbol: "person.crop.circle.badge.minus",
                    tint: .purple,
                    isOn: discordLayoutBinding(\.hideAccountDock)
                )
            }

            SettingsGlassCard(
                title: "Messages and composer",
                subtitle: "Keep the essentials for conversation or turn the sidebar into a reader.",
                symbol: "text.bubble.fill",
                tint: .green
            ) {
                Picker("Composer", selection: discordLayoutBinding(\.composerMode)) {
                    ForEach(composerModes, id: \.self) { mode in
                        Text(mode.settingsTitle).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.discordLayoutOptions.composerMode.settingsDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)

                SettingsDivider()

                SettingsToggleRow(
                    title: "Simplify the channel header",
                    detail: "Keep the title visible while reducing secondary controls.",
                    symbol: "rectangle.topthird.inset.filled",
                    tint: .indigo,
                    isOn: discordLayoutBinding(\.simplifyHeader)
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "Limit tall message media",
                    detail: "Keep large images and videos from overwhelming a narrow panel.",
                    symbol: "photo.on.rectangle.angled",
                    tint: .orange,
                    isOn: discordLayoutBinding(\.compactMedia)
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "Reduce Discord interface motion",
                    detail: "Minimize animations inside Discord independently of SideCord.",
                    symbol: "figure.walk.motion.trianglebadge.exclamationmark",
                    tint: .mint,
                    isOn: discordLayoutBinding(\.reduceMotion)
                )
            }

            SettingsGlassCard(
                title: "Density",
                subtitle: "Compact density reduces spacing without hiding another part of Discord.",
                symbol: "arrow.up.and.down.text.horizontal",
                tint: .orange
            ) {
                Picker("Density", selection: $settings.cssPreset) {
                    Text("Discord default").tag(CSSPreset.standard)
                    Text("Compact").tag(CSSPreset.compact)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var themesPage: some View {
        VStack(spacing: 18) {
            SettingsGlassCard(
                title: "Visual theme",
                subtitle: "Choose a palette that recolors Discord itself and SideCord’s native chrome. Every preview uses fictional geometry only.",
                symbol: "paintpalette.fill",
                tint: .pink
            ) {
                GlassEffectContainer(spacing: 14) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 220), spacing: 14)],
                        spacing: 14
                    ) {
                        ForEach(visualThemes, id: \.self) { theme in
                            ThemePresetCard(
                                theme: theme,
                                isSelected: settings.visualTheme == theme,
                                action: { settings.visualTheme = theme }
                            )
                        }
                    }
                }
            }

            SettingsGlassCard(
                title: "Personalize",
                subtitle: "Accent and intensity shape Discord’s surfaces, controls, and SideCord chrome while preserving message readability.",
                symbol: "swatchpalette.fill",
                tint: .purple
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Accent")
                        .font(.headline)

                    HStack(spacing: 12) {
                        ForEach(accents, id: \.self) { accent in
                            AccentChip(
                                accent: accent,
                                isSelected: settings.themeAccent == accent,
                                action: { settings.themeAccent = accent }
                            )
                        }
                    }
                }

                SettingsDivider()

                ValueSliderRow(
                    title: "Theme surface intensity",
                    detail: "Controls how strongly the selected palette replaces Discord’s background and surface colors.",
                    value: $settings.themeIntensity,
                    range: 0 ... 1,
                    step: 0.05,
                    valueText: "\(Int((settings.themeIntensity * 100).rounded()))%"
                )

                SettingsDivider()

                LabeledContent("Appearance") {
                    Picker("Appearance", selection: $settings.themeColorScheme) {
                        ForEach(themeColorSchemes, id: \.self) { scheme in
                            Label(scheme.settingsTitle, systemImage: scheme.settingsSymbol)
                                .tag(scheme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 310)
                }

                Text("System follows your Mac. Light and Dark explicitly override Discord’s account theme inside SideCord.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var advancedPage: some View {
        VStack(spacing: 18) {
            SettingsGlassCard(
                title: "Keyboard shortcuts",
                subtitle: "Shortcuts work from any Space while SideCord is running.",
                symbol: "keyboard.fill",
                tint: .blue
            ) {
                ShortcutSettingsRow(
                    title: "Show or hide SideCord",
                    detail: "Toggle the floating panel from anywhere.",
                    symbol: "rectangle.on.rectangle.angled",
                    shortcut: shortcutBinding
                )

                SettingsDivider()

                ShortcutSettingsRow(
                    title: "Open navigation",
                    detail: "Temporarily surface Discord navigation in compact layouts.",
                    symbol: "sidebar.leading",
                    shortcut: navigationShortcutBinding
                )

                Text("Select a shortcut button, then press a key with ⌘, ⌥, ⌃, or ⇧. Press Escape to cancel recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }

            SettingsGlassCard(
                title: "Custom CSS",
                subtitle: "For advanced visual adjustments beyond SideCord’s built-in controls.",
                symbol: "curlybraces.square.fill",
                tint: .orange
            ) {
                SettingsToggleRow(
                    title: "Use custom CSS on Discord pages",
                    detail: "Stored locally and injected only into approved Discord pages.",
                    symbol: "wand.and.stars",
                    tint: .orange,
                    isOn: $settings.customCSSEnabled
                )

                TextEditor(text: $settings.customCSS)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 220)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.82))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.separator.opacity(0.7), lineWidth: 1)
                    }
                    .disabled(!settings.customCSSEnabled)
                    .opacity(settings.customCSSEnabled ? 1 : 0.58)
                    .accessibilityLabel("Custom CSS editor")
                    .padding(.top, 8)

                if let validationError = DiscordCSSComposer.validationError(for: settings.customCSS),
                   settings.customCSSEnabled {
                    Label(validationError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack {
                    Label("Remote resources and unsafe CSS syntax are blocked.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Reset") {
                        settings.customCSS = ""
                    }
                    .disabled(settings.customCSS.isEmpty)

                    Button("Apply Styles") {
                        webController.refreshCSS()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!settings.customCSSEnabled)
                }
            }
        }
    }

    private var aboutPage: some View {
        VStack(spacing: 18) {
            SettingsGlassCard {
                VStack(spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.indigo, .purple, .pink.opacity(0.9)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 92, height: 92)
                            .shadow(color: .purple.opacity(0.28), radius: 18, y: 8)

                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(spacing: 5) {
                        Text("SideCord")
                            .font(.largeTitle.bold())
                        Text("Version \(appVersion)")
                            .foregroundStyle(.secondary)
                    }

                    Text("A focused Discord sidebar made for quick conversations across every macOS Space.")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 520)

                    HStack(spacing: 14) {
                        AboutBadge(title: "Native macOS", symbol: "macwindow", tint: .blue)
                        AboutBadge(title: "Private previews", symbol: "eye.slash.fill", tint: .purple)
                        AboutBadge(title: "Local settings", symbol: "externaldrive.fill", tint: .green)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }

            SettingsGlassCard(
                title: "Independence and privacy",
                symbol: "hand.raised.fill",
                tint: .green
            ) {
                Text("SideCord is independent software and is not affiliated with Discord Inc. Layout previews are generated diagrams: the settings window never reads, captures, or displays your servers, channels, messages, or account details.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsGlassCard(
                title: "Start fresh",
                subtitle: "Restore every SideCord preference to its original value.",
                symbol: "arrow.counterclockwise.circle.fill",
                tint: .red
            ) {
                HStack {
                    Text("Your Discord account and website data are not affected.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset All Settings", role: .destructive) {
                        showingResetConfirmation = true
                    }
                }
            }
        }
    }

    private let navigationPresentations: [DiscordNavigationPresentation] = [
        .docked, .floating, .hidden
    ]

    private let composerModes: [DiscordComposerMode] = [
        .full, .essential, .hidden
    ]

    private let visualThemes: [DiscordVisualTheme] = [
        .systemGlass, .discord, .oled, .soft
    ]

    private let accents: [SideCordAccent] = [
        .automatic, .blurple, .blue, .purple, .pink, .green, .orange
    ]

    private let themeColorSchemes: [ThemeColorScheme] = [
        .system, .light, .dark
    ]

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                launchAtLoginController.isEnabled || launchAtLoginController.requiresApproval
            },
            set: { shouldEnable in
                do {
                    try launchAtLoginController.setEnabled(shouldEnable)
                    settings.launchAtLoginEnabled = launchAtLoginController.isEnabled
                        || launchAtLoginController.requiresApproval
                } catch {
                    launchAtLoginController.refresh()
                    settings.launchAtLoginEnabled = launchAtLoginController.isEnabled
                        || launchAtLoginController.requiresApproval
                    presentedError = PresentedSettingsError(
                        title: "Couldn’t update Launch at Login",
                        message: error.localizedDescription
                    )
                }
            }
        )
    }

    private var shortcutBinding: Binding<ShortcutDefinition> {
        shortcutBinding(
            draft: $shortcutDraft,
            current: { settings.shortcut },
            update: { settings.shortcut = $0 },
            register: onShortcutChanged,
            errorTitle: "Couldn’t use that sidebar shortcut"
        )
    }

    private var navigationShortcutBinding: Binding<ShortcutDefinition> {
        shortcutBinding(
            draft: $navigationShortcutDraft,
            current: { settings.navigationShortcut },
            update: { settings.navigationShortcut = $0 },
            register: onNavigationShortcutChanged,
            errorTitle: "Couldn’t use that navigation shortcut"
        )
    }

    private func shortcutBinding(
        draft: Binding<ShortcutDefinition>,
        current: @escaping () -> ShortcutDefinition,
        update: @escaping (ShortcutDefinition) -> Void,
        register: @escaping (ShortcutDefinition) throws -> Void,
        errorTitle: String
    ) -> Binding<ShortcutDefinition> {
        Binding(
            get: { draft.wrappedValue },
            set: { candidate in
                do {
                    try register(candidate)
                    update(candidate)
                    draft.wrappedValue = candidate
                } catch {
                    draft.wrappedValue = current()
                    presentedError = PresentedSettingsError(
                        title: errorTitle,
                        message: error.localizedDescription
                    )
                }
            }
        )
    }

    private var sidebarWidthBinding: Binding<CGFloat> {
        Binding(
            get: { settings.sidebarWidth },
            set: { width in
                settings.resetAllDisplayWidths()
                settings.sidebarWidth = width
            }
        )
    }

    private func discordLayoutBinding<Value>(
        _ keyPath: WritableKeyPath<DiscordLayoutOptions, Value>
    ) -> Binding<Value> {
        Binding(
            get: { settings.discordLayoutOptions[keyPath: keyPath] },
            set: { value in
                var options = settings.discordLayoutOptions
                options[keyPath: keyPath] = value
                settings.customDiscordLayoutOptions = options
                settings.discordLayoutMode = .custom
            }
        )
    }

    private func layoutOptions(for mode: DiscordLayoutMode) -> DiscordLayoutOptions {
        switch mode {
        case .full: .full
        case .focus: .focus
        case .reader: .reader
        case .custom: settings.customDiscordLayoutOptions
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0"
    }

    private func resetSettings() {
        let previousShortcut = settings.shortcut
        let previousNavigationShortcut = settings.navigationShortcut
        settings.resetToDefaults()

        do {
            try onShortcutsReset()
            shortcutDraft = settings.shortcut
            navigationShortcutDraft = settings.navigationShortcut
        } catch {
            settings.shortcut = previousShortcut
            settings.navigationShortcut = previousNavigationShortcut
            shortcutDraft = previousShortcut
            navigationShortcutDraft = previousNavigationShortcut
            presentedError = PresentedSettingsError(
                title: "Some settings were reset",
                message: "The default shortcut pair was unavailable, so SideCord kept your previous shortcuts. \(error.localizedDescription)"
            )
        }

        do {
            try launchAtLoginController.setEnabled(false)
        } catch {
            presentedError = PresentedSettingsError(
                title: "Some settings were reset",
                message: "Launch at Login could not be disabled. \(error.localizedDescription)"
            )
        }
        settings.launchAtLoginEnabled = launchAtLoginController.isEnabled
            || launchAtLoginController.requiresApproval
        webController.refreshCSS()
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case sidebar
    case discordLayout
    case themes
    case advanced
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .sidebar: "Sidebar"
        case .discordLayout: "Discord Layout"
        case .themes: "Themes"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Control how SideCord fits into your day."
        case .sidebar: "Shape the floating panel and its edge gesture."
        case .discordLayout: "Make Discord readable at any sidebar width."
        case .themes: "Choose a visual character that feels at home on your Mac."
        case .advanced: "Shortcuts and carefully contained custom styling."
        case .about: "Details, privacy, and a fresh start."
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .sidebar: "sidebar.right"
        case .discordLayout: "rectangle.3.group.fill"
        case .themes: "paintpalette.fill"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .blue
        case .sidebar: .purple
        case .discordLayout: .indigo
        case .themes: .pink
        case .advanced: .orange
        case .about: .green
        }
    }
}

private struct SettingsBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tint: Color

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [tint.opacity(0.10), .clear, Color.accentColor.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: tint.description)
    }
}

private struct SettingsPageHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 16) {
            SettingsSymbolTile(symbol: symbol, tint: tint, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.largeTitle.bold())
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsSymbolTile: View {
    let symbol: String
    let tint: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.95), tint.opacity(0.62)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: tint.opacity(0.22), radius: size * 0.16, y: size * 0.08)
        .accessibilityHidden(true)
    }
}

private struct SettingsGlassCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let title: String?
    let subtitle: String?
    let symbol: String?
    let tint: Color
    let content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        symbol: String? = nil,
        tint: Color = .accentColor,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        let card = VStack(alignment: .leading, spacing: 16) {
            if title != nil || subtitle != nil {
                HStack(alignment: .top, spacing: 12) {
                    if let symbol {
                        SettingsSymbolTile(symbol: symbol, tint: tint, size: 34)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        if let title {
                            Text(title)
                                .font(.title3.weight(.semibold))
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)

        if reduceTransparency {
            card
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.separator.opacity(0.7), lineWidth: 1)
                }
        } else {
            card
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider().opacity(0.55)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 13) {
            SettingsSymbolTile(symbol: symbol, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 18)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct ValueSliderRow<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    let title: String
    let detail: String
    @Binding var value: Value
    let range: ClosedRange<Value>
    let step: Value.Stride
    let valueText: String

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            Slider(value: $value, in: range, step: step)
                .frame(width: 210)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
            Text(valueText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
        }
    }
}

private struct StatusPill: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.callout.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct FloatingRailSchematic: View {
    let edge: SidebarEdge
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 11) {
            if edge == .left {
                panel
                rail
            } else {
                rail
                panel
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(.secondary.opacity(0.14), lineWidth: 1)
        }
    }

    private var panel: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 7) {
                Capsule().fill(.secondary.opacity(0.25)).frame(width: 34, height: 4)
                Capsule().fill(.secondary.opacity(0.16)).frame(width: 47, height: 3)
                Capsule().fill(.secondary.opacity(0.16)).frame(width: 39, height: 3)
                Spacer(minLength: 0)
            }
            .padding(9)
            .frame(width: 66)
            .background(.secondary.opacity(0.07))

            VStack(alignment: .leading, spacing: 7) {
                Capsule().fill(.secondary.opacity(0.28)).frame(width: 54, height: 4)
                ForEach(0 ..< 3, id: \.self) { index in
                    HStack(spacing: 5) {
                        Circle().fill(.secondary.opacity(0.23)).frame(width: 8, height: 8)
                        Capsule()
                            .fill(.secondary.opacity(index == 1 ? 0.26 : 0.15))
                            .frame(width: index == 1 ? 84 : 64, height: 3)
                    }
                }
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 4)
                    .fill(.secondary.opacity(0.11))
                    .frame(height: 12)
            }
            .padding(9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.secondary.opacity(0.18), lineWidth: 1)
        }
    }

    private var rail: some View {
        VStack(spacing: 5) {
            ForEach(0 ..< 4, id: \.self) { index in
                RoundedRectangle(cornerRadius: index == 1 ? 5 : 8)
                    .fill(index == 1 ? Color.indigo.opacity(0.78) : .secondary.opacity(0.24))
                    .frame(width: 17, height: 17)
            }
        }
        .padding(7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isEnabled ? Color.indigo.opacity(0.48) : Color.secondary.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1, dash: isEnabled ? [] : [3, 3])
                )
        }
        .opacity(isEnabled ? 1 : 0.28)
        .overlay {
            if !isEnabled {
                Image(systemName: "eye.slash.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .help(isEnabled ? "Separate server rail shown" : "Server rail hidden")
    }
}

private struct LayoutPresetCard: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let mode: DiscordLayoutMode
    let options: DiscordLayoutOptions
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                DiscordLayoutSchematic(options: options)
                    .frame(height: 128)
                    .accessibilityHidden(true)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.title)
                            .font(.headline)
                        Text(mode.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        reduceTransparency
                            ? Color(nsColor: .controlBackgroundColor)
                            : Color.primary.opacity(isSelected ? 0.10 : 0.045)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.18),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title) layout")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(mode.detail)
    }
}

private struct DiscordLayoutSchematic: View {
    let options: DiscordLayoutOptions

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor).opacity(0.9))

            HStack(spacing: 4) {
                if options.navigationPresentation == .docked {
                    navigationRail
                }

                messageArea

                if !options.hideMemberList {
                    VStack(spacing: 5) {
                        ForEach(0 ..< 5, id: \.self) { _ in
                            HStack(spacing: 3) {
                                Circle().fill(.secondary.opacity(0.35)).frame(width: 7, height: 7)
                                Capsule().fill(.secondary.opacity(0.20)).frame(width: 15, height: 3)
                            }
                        }
                        Spacer()
                    }
                    .frame(width: 29)
                    .padding(.top, 16)
                    .background(.primary.opacity(0.035))
                }
            }
            .padding(5)

            if options.navigationPresentation == .floating {
                navigationRail
                    .frame(width: 54)
                    .padding(9)
                    .shadow(color: .black.opacity(0.18), radius: 6, x: 2, y: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.secondary.opacity(0.18), lineWidth: 1)
        }
    }

    private var navigationRail: some View {
        HStack(spacing: 3) {
            VStack(spacing: 4) {
                ForEach(0 ..< 5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(index == 1 ? Color.indigo.opacity(0.8) : .secondary.opacity(0.24))
                        .frame(width: 10, height: 10)
                }
                Spacer(minLength: 2)
            }
            .padding(.vertical, 5)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(0 ..< 6, id: \.self) { index in
                    Capsule()
                        .fill(index == 2 ? Color.accentColor.opacity(0.52) : .secondary.opacity(0.2))
                        .frame(width: index == 2 ? 24 : 19, height: 3)
                }
                Spacer(minLength: 2)
                if !options.hideAccountDock {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.secondary.opacity(0.18))
                        .frame(width: 25, height: 10)
                }
            }
            .padding(.vertical, 5)
        }
        .padding(.horizontal, 5)
        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }

    private var messageArea: some View {
        VStack(spacing: 5) {
            HStack {
                Capsule().fill(.secondary.opacity(0.28)).frame(width: 38, height: 4)
                Spacer()
                if !options.simplifyHeader {
                    Circle().fill(.secondary.opacity(0.18)).frame(width: 7, height: 7)
                    Circle().fill(.secondary.opacity(0.18)).frame(width: 7, height: 7)
                }
            }
            .frame(height: 12)

            VStack(alignment: .leading, spacing: 7) {
                schematicMessage(widths: [0.50, 0.72])
                schematicMessage(widths: [0.65, 0.39])
                if options.compactMedia {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.orange.opacity(0.24))
                        .frame(width: 46, height: 17)
                }
                schematicMessage(widths: [0.58, 0.78])
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if options.composerMode != .hidden {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.secondary.opacity(0.14))
                    .frame(height: options.composerMode == .essential ? 12 : 19)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.secondary.opacity(0.26))
                            .frame(width: 28, height: 3)
                            .padding(.leading, 7)
                    }
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func schematicMessage(widths: [CGFloat]) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Circle().fill(.secondary.opacity(0.28)).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(widths.enumerated()), id: \.offset) { _, width in
                    GeometryReader { proxy in
                        Capsule()
                            .fill(.secondary.opacity(0.22))
                            .frame(width: proxy.size.width * width, height: 3)
                    }
                    .frame(height: 3)
                }
            }
        }
    }
}

private struct ThemePresetCard: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let theme: DiscordVisualTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                ThemeSchematic(theme: theme)
                    .frame(height: 120)
                    .accessibilityHidden(true)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(theme.settingsTitle)
                            .font(.headline)
                        Text(theme.settingsDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        reduceTransparency
                            ? Color(nsColor: .controlBackgroundColor)
                            : Color.primary.opacity(isSelected ? 0.10 : 0.045)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.18),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.settingsTitle) theme")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(theme.settingsDetail)
    }
}

private struct ThemeSchematic: View {
    let theme: DiscordVisualTheme

    var body: some View {
        let palette = theme.settingsPalette

        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.background)

            HStack(spacing: 5) {
                VStack(spacing: 5) {
                    ForEach(0 ..< 5, id: \.self) { index in
                        Circle()
                            .fill(index == 1 ? palette.accent : palette.railItem)
                            .frame(width: 11, height: 11)
                    }
                    Spacer()
                }
                .padding(7)
                .background(palette.rail)

                VStack(alignment: .leading, spacing: 7) {
                    Capsule().fill(palette.secondary).frame(width: 46, height: 5)
                    ForEach(0 ..< 3, id: \.self) { index in
                        HStack(alignment: .top, spacing: 6) {
                            Circle().fill(index == 1 ? palette.accent : palette.secondary)
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 3) {
                                Capsule().fill(palette.primary).frame(width: 58, height: 4)
                                Capsule().fill(palette.secondary).frame(width: 82, height: 3)
                            }
                        }
                    }
                    Spacer()
                    RoundedRectangle(cornerRadius: 5)
                        .fill(palette.composer)
                        .frame(height: 17)
                }
                .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        }
    }
}

private struct ThemePreviewPalette {
    let background: Color
    let rail: Color
    let railItem: Color
    let primary: Color
    let secondary: Color
    let composer: Color
    let accent: Color
    let border: Color
}

private struct AccentChip: View {
    let accent: SideCordAccent
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(accent.settingsColor)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Circle().stroke(.white.opacity(0.32), lineWidth: 1)
                    }

                if accent == .automatic {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(3)
            .background {
                Circle()
                    .stroke(isSelected ? Color.primary : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .help(accent.settingsTitle)
        .accessibilityLabel(accent.settingsTitle + " accent")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct ShortcutSettingsRow: View {
    let title: String
    let detail: String
    let symbol: String
    @Binding var shortcut: ShortcutDefinition

    var body: some View {
        HStack(spacing: 13) {
            SettingsSymbolTile(symbol: symbol, tint: .blue, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 18)
            ShortcutRecorderView(shortcut: $shortcut)
                .accessibilityLabel(title)
        }
    }
}

private struct AboutBadge: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct PresentedSettingsError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private extension DiscordNavigationPresentation {
    var settingsTitle: String {
        switch self {
        case .docked: "Docked"
        case .floating: "Floating"
        case .hidden: "Hidden"
        }
    }

    var settingsDetail: String {
        switch self {
        case .docked: "Keep Discord navigation attached beside the conversation."
        case .floating: "Use a compact navigation drawer over messages when you need it."
        case .hidden: "Hide navigation until you invoke the navigation shortcut."
        }
    }
}

private extension DiscordComposerMode {
    var settingsTitle: String {
        switch self {
        case .full: "Full"
        case .essential: "Essential"
        case .hidden: "Hidden"
        }
    }

    var settingsDetail: String {
        switch self {
        case .full: "Keep Discord’s complete composer and attachment controls."
        case .essential: "Retain message input while trimming secondary actions."
        case .hidden: "Hide message input for a distraction-free reader layout."
        }
    }
}

private extension DiscordVisualTheme {
    var settingsTitle: String {
        switch self {
        case .systemGlass: "System Glass"
        case .discord: "Discord"
        case .oled: "OLED"
        case .soft: "Soft"
        }
    }

    var settingsDetail: String {
        switch self {
        case .systemGlass: "Translucent materials that blend with macOS."
        case .discord: "The familiar Discord color foundation."
        case .oled: "Deep black surfaces with crisp contrast."
        case .soft: "Warmer, quieter surfaces for long reading."
        }
    }

    var settingsPalette: ThemePreviewPalette {
        switch self {
        case .systemGlass:
            ThemePreviewPalette(
                background: Color(red: 0.82, green: 0.87, blue: 0.94),
                rail: .white.opacity(0.34),
                railItem: .white.opacity(0.68),
                primary: .white.opacity(0.88),
                secondary: .white.opacity(0.58),
                composer: .white.opacity(0.40),
                accent: .blue.opacity(0.88),
                border: .white.opacity(0.55)
            )
        case .discord:
            ThemePreviewPalette(
                background: Color(red: 0.19, green: 0.20, blue: 0.23),
                rail: Color(red: 0.13, green: 0.14, blue: 0.16),
                railItem: .white.opacity(0.22),
                primary: .white.opacity(0.78),
                secondary: .white.opacity(0.27),
                composer: .white.opacity(0.10),
                accent: Color(red: 0.35, green: 0.40, blue: 0.95),
                border: .white.opacity(0.12)
            )
        case .oled:
            ThemePreviewPalette(
                background: .black,
                rail: Color(white: 0.035),
                railItem: .white.opacity(0.17),
                primary: .white.opacity(0.88),
                secondary: .white.opacity(0.25),
                composer: .white.opacity(0.075),
                accent: .purple,
                border: .white.opacity(0.12)
            )
        case .soft:
            ThemePreviewPalette(
                background: Color(red: 0.91, green: 0.88, blue: 0.85),
                rail: Color(red: 0.80, green: 0.75, blue: 0.73),
                railItem: .white.opacity(0.58),
                primary: Color.brown.opacity(0.58),
                secondary: Color.brown.opacity(0.25),
                composer: .white.opacity(0.42),
                accent: Color(red: 0.78, green: 0.43, blue: 0.53),
                border: Color.brown.opacity(0.16)
            )
        }
    }
}

private extension SideCordAccent {
    var settingsTitle: String {
        switch self {
        case .automatic: "Automatic"
        case .blurple: "Blurple"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .green: "Green"
        case .orange: "Orange"
        }
    }

    var settingsColor: Color {
        switch self {
        case .automatic: Color(red: 0.35, green: 0.40, blue: 0.95)
        case .blurple: Color(red: 0.35, green: 0.40, blue: 0.95)
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .green: .green
        case .orange: .orange
        }
    }
}

private extension ThemeColorScheme {
    var settingsTitle: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var settingsSymbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var settingsColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
