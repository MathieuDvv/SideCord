import SwiftUI

struct OnboardingDraft: Equatable {
    var sidebarEdge: SidebarEdge
    var edgeHoverEnabled: Bool
    var layoutMode: DiscordLayoutMode
    var customLayoutOptions: DiscordLayoutOptions
    var floatingRailEnabled: Bool
    var visualTheme: DiscordVisualTheme
    var themeAccent: SideCordAccent
    var notificationGlowEnabled: Bool
    var launchAtLoginEnabled: Bool
    let includesCustomLayoutChoice: Bool

    @MainActor
    init(settings: AppSettings, launchAtLoginEnabled: Bool) {
        sidebarEdge = settings.sidebarEdge
        edgeHoverEnabled = settings.edgeHoverEnabled
        layoutMode = settings.discordLayoutMode
        customLayoutOptions = settings.customDiscordLayoutOptions
        floatingRailEnabled = settings.floatingRailEnabled
        visualTheme = settings.visualTheme
        themeAccent = settings.themeAccent
        notificationGlowEnabled = settings.notificationGlowEnabled
        self.launchAtLoginEnabled = launchAtLoginEnabled
        includesCustomLayoutChoice = settings.discordLayoutMode == .custom
    }

    var layoutOptions: DiscordLayoutOptions {
        switch layoutMode {
        case .full: .full
        case .focus: .focus
        case .reader: .reader
        case .custom: customLayoutOptions
        }
    }

    var floatingRailIsAvailable: Bool {
        layoutOptions.navigationPresentation != .docked
    }

    @MainActor
    func apply(to settings: AppSettings) {
        settings.sidebarEdge = sidebarEdge
        settings.edgeHoverEnabled = edgeHoverEnabled
        settings.customDiscordLayoutOptions = customLayoutOptions
        settings.applyDiscordLayoutMode(layoutMode)
        settings.floatingRailEnabled = floatingRailEnabled
        settings.visualTheme = visualTheme
        settings.themeAccent = themeAccent
        settings.notificationGlowEnabled = notificationGlowEnabled
        settings.launchAtLoginEnabled = launchAtLoginEnabled
    }
}

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject var settings: AppSettings
    let launchAtLoginController: LaunchAtLoginController
    let onPreviewGlow: (SidebarEdge, SideCordAccent) -> Void
    let onFinish: () -> Void

    @State private var step: OnboardingStep = .reveal
    @State private var draft: OnboardingDraft
    @State private var launchErrorMessage: String?

    init(
        settings: AppSettings,
        launchAtLoginController: LaunchAtLoginController,
        onPreviewGlow: @escaping (SidebarEdge, SideCordAccent) -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.settings = settings
        self.launchAtLoginController = launchAtLoginController
        self.onPreviewGlow = onPreviewGlow
        self.onFinish = onFinish
        _draft = State(initialValue: OnboardingDraft(
            settings: settings,
            launchAtLoginEnabled: launchAtLoginController.isEnabled
                || launchAtLoginController.requiresApproval
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            onboardingHeader
            Divider()
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 34)
                .padding(.vertical, 28)
                .id(step)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            Divider()
            onboardingFooter
        }
        .frame(width: 760, height: 660)
        .background {
            OnboardingBackdrop(accent: draft.themeAccent.onboardingColor)
        }
        .tint(draft.themeAccent.onboardingColor)
        .alert("Couldn’t update Launch at Login", isPresented: Binding(
            get: { launchErrorMessage != nil },
            set: { if !$0 { launchErrorMessage = nil } }
        )) {
            Button("OK") { launchErrorMessage = nil }
        } message: {
            Text(launchErrorMessage ?? "Unknown error")
        }
    }

    private var onboardingHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(draft.themeAccent.onboardingColor.gradient)
                Image(systemName: step.symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)
            .shadow(color: draft.themeAccent.onboardingColor.opacity(0.22), radius: 12, y: 5)

            VStack(alignment: .leading, spacing: 3) {
                Text("Welcome to SideCord")
                    .font(.title2.weight(.bold))
                Text(step.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases) { item in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(item.rawValue <= step.rawValue
                                ? draft.themeAccent.onboardingColor
                                : Color.secondary.opacity(0.2))
                            .frame(width: 8, height: 8)
                        Text(item.shortTitle)
                            .font(.caption2.weight(item == step ? .semibold : .regular))
                            .foregroundStyle(item == step ? .primary : .secondary)
                    }
                    .frame(width: 68)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Step \(item.rawValue + 1), \(item.shortTitle)")
                    .accessibilityValue(item == step ? "Current" : item.rawValue < step.rawValue ? "Completed" : "Upcoming")
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .reveal:
            revealStep
        case .workspace:
            workspaceStep
        case .appearance:
            appearanceStep
        }
    }

    private var revealStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepIntroduction(
                title: "Keep Discord one edge away",
                detail: "Choose where SideCord waits and how you want to bring it forward."
            )

            OnboardingCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Screen edge")
                        .font(.headline)

                    Picker("Screen edge", selection: $draft.sidebarEdge) {
                        ForEach(SidebarEdge.allCases) { edge in
                            Label(
                                edge.title,
                                systemImage: edge == .left ? "sidebar.left" : "sidebar.right"
                            )
                            .tag(edge)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    Divider()

                    Toggle(isOn: $draft.edgeHoverEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Reveal when the pointer rests at the edge")
                                .font(.headline)
                            Text("The reveal zone follows the selected edge on every display.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }

            OnboardingCard {
                HStack(spacing: 16) {
                    Image(systemName: "command.square.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(draft.themeAccent.onboardingColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your global shortcut")
                            .font(.headline)
                        Text("Press it now to verify SideCord responds, even while another app is active.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(settings.shortcut.displayName)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .accessibilityLabel("SideCord shortcut: \(settings.shortcut.displayName)")
                }
            }
        }
    }

    private var workspaceStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepIntroduction(
                title: "Shape your workspace",
                detail: "Start with a complete Discord layout. You can fine-tune every part later in Settings."
            )

            HStack(spacing: 12) {
                ForEach(availableLayoutModes) { mode in
                    OnboardingChoiceCard(
                        title: mode == .custom ? "Your Custom" : mode.title,
                        detail: mode.onboardingDetail,
                        symbol: mode.onboardingSymbol,
                        isSelected: draft.layoutMode == mode,
                        accent: draft.themeAccent.onboardingColor
                    ) {
                        draft.layoutMode = mode
                    }
                }
            }

            OnboardingCard {
                Toggle(isOn: $draft.floatingRailEnabled) {
                    HStack(spacing: 14) {
                        Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled.fill")
                            .font(.title2)
                            .foregroundStyle(.indigo)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Floating server rail")
                                .font(.headline)
                            Text(floatingRailDetail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .toggleStyle(.switch)
                .disabled(!draft.floatingRailIsAvailable)
                .opacity(draft.floatingRailIsAvailable ? 1 : 0.6)
            }

            Label(
                "Layout previews use abstract geometry; SideCord never reads or captures your messages.",
                systemImage: "eye.slash.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var appearanceStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepIntroduction(
                title: "Make it feel at home",
                detail: "Choose a visual character and decide how Discord activity gets your attention."
            )

            HStack(spacing: 10) {
                ForEach(DiscordVisualTheme.allCases) { theme in
                    OnboardingChoiceCard(
                        title: theme.title,
                        detail: theme.onboardingDetail,
                        symbol: theme.onboardingSymbol,
                        isSelected: draft.visualTheme == theme,
                        accent: draft.themeAccent.onboardingColor
                    ) {
                        draft.visualTheme = theme
                    }
                }
            }

            OnboardingCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Accent")
                        .font(.headline)

                    HStack(spacing: 14) {
                        ForEach(SideCordAccent.allCases) { accent in
                            AccentSelectionButton(
                                accent: accent,
                                isSelected: draft.themeAccent == accent
                            ) {
                                draft.themeAccent = accent
                            }
                        }
                    }

                    Divider()

                    HStack(spacing: 14) {
                        Toggle(isOn: $draft.notificationGlowEnabled) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Glow for Discord activity")
                                    .font(.headline)
                                Text("A soft edge pulse for messages; incoming calls breathe until acknowledged.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)

                        Button("Preview Glow") {
                            onPreviewGlow(draft.sidebarEdge, draft.themeAccent)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!draft.notificationGlowEnabled)
                    }

                    Divider()

                    Toggle("Launch SideCord when I log in", isOn: $draft.launchAtLoginEnabled)
                        .toggleStyle(.switch)
                }
            }
        }
    }

    private var onboardingFooter: some View {
        HStack {
            if step != .reveal {
                Button("Back") { move(to: step.previous) }
            }

            Spacer()

            Text("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if step == .appearance {
                Button("Get Started") { completeOnboarding() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { move(to: step.next) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var availableLayoutModes: [DiscordLayoutMode] {
        DiscordLayoutMode.quickModes
            + (draft.includesCustomLayoutChoice ? [.custom] : [])
    }

    private var floatingRailDetail: String {
        if draft.floatingRailIsAvailable {
            return "Keep servers and direct messages in a separate strip beside SideCord."
        }
        return "The Full layout already keeps Discord’s server navigation inside the window."
    }

    private func move(to destination: OnboardingStep?) {
        guard let destination else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            step = destination
        }
    }

    private func completeOnboarding() {
        do {
            try launchAtLoginController.setEnabled(draft.launchAtLoginEnabled)
            draft.launchAtLoginEnabled = launchAtLoginController.isEnabled
                || launchAtLoginController.requiresApproval
            draft.apply(to: settings)
            onFinish()
        } catch {
            launchAtLoginController.refresh()
            draft.launchAtLoginEnabled = launchAtLoginController.isEnabled
                || launchAtLoginController.requiresApproval
            launchErrorMessage = error.localizedDescription
        }
    }
}

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case reveal
    case workspace
    case appearance

    var id: Self { self }

    var shortTitle: String {
        switch self {
        case .reveal: "Reveal"
        case .workspace: "Workspace"
        case .appearance: "Appearance"
        }
    }

    var subtitle: String {
        switch self {
        case .reveal: "Choose how SideCord appears."
        case .workspace: "Pick the Discord view that suits you."
        case .appearance: "Add the finishing touches."
        }
    }

    var symbol: String {
        switch self {
        case .reveal: "cursorarrow.rays"
        case .workspace: "rectangle.3.group.fill"
        case .appearance: "paintpalette.fill"
        }
    }

    var previous: Self? { Self(rawValue: rawValue - 1) }
    var next: Self? { Self(rawValue: rawValue + 1) }
}

private struct StepIntroduction: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title.weight(.bold))
            Text(detail)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

private struct OnboardingCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct OnboardingChoiceCard: View {
    let title: String
    let detail: String
    let symbol: String
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(isSelected ? accent : .secondary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? accent : .secondary.opacity(0.5))
                }

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(
                isSelected ? accent.opacity(0.11) : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? accent : Color.secondary.opacity(0.16), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(detail)
    }
}

private struct AccentSelectionButton: View {
    let accent: SideCordAccent
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(accent.onboardingColor)
                        .frame(width: 30, height: 30)
                        .overlay { Circle().stroke(.white.opacity(0.35), lineWidth: 1) }
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(accent == .white ? .black : .white)
                    }
                }
                Text(accent.title)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accent.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct OnboardingBackdrop: View {
    let accent: Color

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [accent.opacity(0.09), .clear, Color.blue.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private extension DiscordLayoutMode {
    var onboardingDetail: String {
        switch self {
        case .custom: "Keep your existing fine-tuned Discord layout unchanged."
        default: detail
        }
    }

    var onboardingSymbol: String {
        switch self {
        case .full: "rectangle.split.3x1.fill"
        case .focus: "scope"
        case .reader: "text.page.fill"
        case .custom: "slider.horizontal.3"
        }
    }
}

private extension DiscordVisualTheme {
    var onboardingDetail: String {
        switch self {
        case .systemGlass: "Translucent surfaces that blend with macOS."
        case .discord: "Discord’s familiar color foundation."
        case .oled: "Deep black surfaces with crisp contrast."
        case .soft: "Warm, quiet surfaces for long reading."
        }
    }

    var onboardingSymbol: String {
        switch self {
        case .systemGlass: "circle.hexagongrid.fill"
        case .discord: "message.fill"
        case .oled: "moon.stars.fill"
        case .soft: "cloud.fill"
        }
    }
}

private extension SideCordAccent {
    var onboardingColor: Color {
        let descriptor = colorDescriptor
        return Color(
            red: descriptor.redUnit,
            green: descriptor.greenUnit,
            blue: descriptor.blueUnit
        )
    }
}
