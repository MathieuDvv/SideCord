import AppKit
import Combine
import QuartzCore
import SwiftUI

enum OnboardingExperiencePhase: Equatable, Sendable {
    case introductoryGlow
    case signIn
    case configuration
    case finishing
    case completed
}

enum OnboardingSetupStep: Int, CaseIterable, Identifiable, Sendable {
    case placement
    case layout
    case appearance
    case ready

    var id: Int { rawValue }

    var eyebrow: String {
        switch self {
        case .placement: "01 · Placement"
        case .layout: "02 · Layout"
        case .appearance: "03 · Appearance"
        case .ready: "04 · Ready"
        }
    }

    var title: String {
        switch self {
        case .placement: "Choose your edge"
        case .layout: "Shape your Discord"
        case .appearance: "Make it feel yours"
        case .ready: "You’re all set"
        }
    }
}

@MainActor
final class OnboardingExperienceCoordinator: ObservableObject {
    @Published private(set) var phase: OnboardingExperiencePhase = .introductoryGlow
    @Published var draft: OnboardingDraft
    @Published private(set) var launchErrorMessage: String?
    @Published private(set) var setupStep: OnboardingSetupStep = .placement
    @Published private(set) var stepDirection = 1

    private let settings: AppSettings
    private let webController: DiscordWebController
    private let panelController: PanelController
    private let launchAtLoginController: LaunchAtLoginController
    private let onComplete: () -> Void
    private let stagePanel = OnboardingStagePanel()
    private let optionsPanel = OnboardingCompanionPanel()
    private var cancellables = Set<AnyCancellable>()
    private var animationTask: Task<Void, Never>?
    private var screen: NSScreen?

    init(
        settings: AppSettings,
        webController: DiscordWebController,
        panelController: PanelController,
        launchAtLoginController: LaunchAtLoginController,
        onComplete: @escaping () -> Void
    ) {
        self.settings = settings
        self.webController = webController
        self.panelController = panelController
        self.launchAtLoginController = launchAtLoginController
        self.onComplete = onComplete
        draft = OnboardingDraft(
            settings: settings,
            launchAtLoginEnabled: launchAtLoginController.isEnabled
                || launchAtLoginController.requiresApproval
        )

        webController.$sessionState
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self, self.phase == .signIn, state == .authenticated else { return }
                self.showConfiguration()
            }
            .store(in: &cancellables)

        $draft
            .dropFirst()
            .sink { [weak self] draft in
                guard let self else { return }
                draft.apply(to: self.settings)
                if self.phase == .configuration {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(340))
                        self?.repositionOptions()
                    }
                }
            }
            .store(in: &cancellables)
    }

    var isPresented: Bool { stagePanel.isVisible || optionsPanel.isVisible }

    func start(on screen: NSScreen) {
        animationTask?.cancel()
        self.screen = screen
        phase = .introductoryGlow
        setupStep = .placement
        stepDirection = 1
        launchErrorMessage = nil
        draft = OnboardingDraft(
            settings: settings,
            launchAtLoginEnabled: launchAtLoginController.isEnabled
                || launchAtLoginController.requiresApproval
        )

        stagePanel.contentView = NSHostingView(
            rootView: OnboardingStageView(coordinator: self)
        )
        stagePanel.setFrame(screen.frame, display: true)
        stagePanel.orderFrontRegardless()
        panelController.beginOnboarding(on: screen)

        animationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(850))
            guard let self, !Task.isCancelled else { return }
            self.panelController.revealForOnboarding(on: screen)
            self.phase = .signIn
            if self.webController.sessionState == .authenticated {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                self.showConfiguration()
            }
        }
    }

    func skipSignIn() {
        guard phase == .signIn else { return }
        showConfiguration()
    }

    func backgroundClicked() {
        guard phase == .configuration else { return }
        finish()
    }

    func handleEscape() {
        switch phase {
        case .signIn: skipSignIn()
        case .configuration: finish()
        default: break
        }
    }

    func advanceSetup() {
        guard phase == .configuration else { return }
        guard let next = OnboardingSetupStep(rawValue: setupStep.rawValue + 1) else {
            finish()
            return
        }
        stepDirection = 1
        withAnimation(setupAnimation(forward: true)) {
            setupStep = next
        }
    }

    func retreatSetup() {
        guard phase == .configuration,
              let previous = OnboardingSetupStep(rawValue: setupStep.rawValue - 1)
        else { return }
        stepDirection = -1
        withAnimation(setupAnimation(forward: false)) {
            setupStep = previous
        }
    }

    private func setupAnimation(forward: Bool) -> Animation {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return .easeOut(duration: 0.15)
        }
        return .snappy(
            duration: forward ? 0.42 : 0.38,
            extraBounce: forward ? 0.04 : 0.02
        )
    }

    func finish() {
        guard phase == .configuration else { return }
        do {
            try launchAtLoginController.setEnabled(draft.launchAtLoginEnabled)
            launchAtLoginController.refresh()
            draft.launchAtLoginEnabled = launchAtLoginController.isEnabled
                || launchAtLoginController.requiresApproval
            draft.apply(to: settings)
        } catch {
            launchAtLoginController.refresh()
            draft.launchAtLoginEnabled = launchAtLoginController.isEnabled
                || launchAtLoginController.requiresApproval
            launchErrorMessage = error.localizedDescription
            return
        }

        phase = .finishing
        optionsPanel.orderOut(nil)
        stagePanel.orderOut(nil)
        panelController.finishOnboarding()
        onComplete()
        phase = .completed
    }

    private func showConfiguration() {
        guard phase == .signIn, let screen else { return }
        phase = .configuration
        setupStep = .placement
        stepDirection = 1
        let sidebarFrame = panelController.panel.frame
        let targetFrame = PanelGeometry.onboardingCompanionFrame(
            adjacentTo: sidebarFrame,
            in: screen.visibleFrame,
            edge: draft.sidebarEdge
        )
        var entranceFrame = targetFrame
        entranceFrame.origin.x += draft.sidebarEdge == .right ? 34 : -34
        optionsPanel.contentView = NSHostingView(
            rootView: OnboardingEssentialOptionsView(coordinator: self)
        )
        optionsPanel.setFrame(entranceFrame, display: true)
        optionsPanel.alphaValue = 0
        optionsPanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.12 : 0.46
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            optionsPanel.animator().alphaValue = 1
            optionsPanel.animator().setFrame(targetFrame, display: true)
        }
    }

    private func repositionOptions() {
        guard phase == .configuration, let screen else { return }
        optionsPanel.setFrame(
            PanelGeometry.onboardingCompanionFrame(
                adjacentTo: panelController.panel.frame,
                in: screen.visibleFrame,
                edge: draft.sidebarEdge
            ),
            display: true,
            animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }
}

@MainActor
private final class OnboardingStagePanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        collectionBehavior = FloatingPanelSpacePolicy.collectionBehavior
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class OnboardingCompanionPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [
                .borderless,
                .fullSizeContentView,
                FloatingPanelSpacePolicy.nonactivatingStyle
            ],
            backing: .buffered,
            defer: true
        )
        level = .floating
        collectionBehavior = FloatingPanelSpacePolicy.collectionBehavior
        isFloatingPanel = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .none
        contentMinSize = NSSize(width: 360, height: 480)
        contentMaxSize = PanelGeometry.onboardingCompanionSize
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct OnboardingStageView: View {
    @ObservedObject var coordinator: OnboardingExperienceCoordinator
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color.black.opacity(reduceTransparency ? 0.22 : 0.08)
                .contentShape(Rectangle())
                .onTapGesture { coordinator.backgroundClicked() }

            LinearGradient(
                colors: [.clear, Color.indigo.opacity(0.08), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .allowsHitTesting(false)

            if coordinator.phase == .signIn {
                VStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Sign in to Discord in SideCord")
                        .font(.headline)
                    Text("Your existing WebKit session is used and stays inside SideCord.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Set Up Without Signing In") { coordinator.skipSignIn() }
                        .buttonStyle(.glassProminent)
                }
                .padding(18)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 28)
            }
        }
        .background(.clear)
        .onKeyPress(.escape) {
            coordinator.handleEscape()
            return .handled
        }
    }
}

private struct OnboardingEssentialOptionsView: View {
    @ObservedObject var coordinator: OnboardingExperienceCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                ForEach(OnboardingSetupStep.allCases) { step in
                    Capsule()
                        .fill(step.rawValue <= coordinator.setupStep.rawValue
                              ? Color.accentColor
                              : Color.secondary.opacity(0.2))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 24)

            ScrollView {
                ZStack(alignment: .topLeading) {
                    stepContent
                        .id(coordinator.setupStep)
                        .transition(stepTransition)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.never)
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .layoutPriority(1)

            Divider().opacity(0.55)

            HStack {
                if coordinator.setupStep != .placement {
                    Button("Back") { coordinator.retreatSetup() }
                        .buttonStyle(.plain)
                }
                Spacer()
                Text("Changes preview live")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button(coordinator.setupStep == .ready ? "Finish" : "Continue") {
                    coordinator.advanceSetup()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onKeyPress(.escape) {
            coordinator.handleEscape()
            return .handled
        }
    }

    private var stepContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(coordinator.setupStep.eyebrow.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(.secondary)
                Text(coordinator.setupStep.title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
            }

            switch coordinator.setupStep {
            case .placement: placementStep
            case .layout: layoutStep
            case .appearance: appearanceStep
            case .ready: readyStep
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: coordinator.stepDirection > 0 ? .trailing : .leading)
                .combined(with: .opacity),
            removal: .move(edge: coordinator.stepDirection > 0 ? .leading : .trailing)
                .combined(with: .opacity)
        )
    }

    private var placementStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingEdgePreview(edge: coordinator.draft.sidebarEdge)
                .frame(height: 150)
            Picker("Edge", selection: binding(\.sidebarEdge)) {
                ForEach(SidebarEdge.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            Toggle("Reveal when the pointer rests at the edge", isOn: binding(\.edgeHoverEnabled))
            Text("You can always use ⌥D instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var layoutStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Pick a starting point. Every detail remains adjustable later.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("Layout", selection: binding(\.layoutMode)) {
                ForEach(DiscordLayoutMode.quickModes) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            Toggle("Keep servers in a detached rail", isOn: binding(\.floatingRailEnabled))
                .disabled(!coordinator.draft.floatingRailIsAvailable)
            Label(
                coordinator.draft.layoutMode == .full
                    ? "Full keeps Discord’s familiar navigation."
                    : "The focused layouts give conversations more room.",
                systemImage: "rectangle.3.group"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var appearanceStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Theme", selection: binding(\.visualTheme)) {
                ForEach(DiscordVisualTheme.allCases) { Text($0.title).tag($0) }
            }
            Picker("Accent", selection: binding(\.themeAccent)) {
                ForEach(SideCordAccent.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Glow for Discord activity", isOn: binding(\.notificationGlowEnabled))
            HStack(spacing: 10) {
                Circle().fill(accentColor).frame(width: 26, height: 26)
                Text("The accent is shared by controls, themes, and glow when configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("SideCord is ready on the \(coordinator.draft.sidebarEdge.title.lowercased()) edge", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Toggle("Launch SideCord when I log in", isOn: binding(\.launchAtLoginEnabled))
            if let error = coordinator.launchErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("Hover at the edge or press ⌥D whenever you need Discord. Clicking outside this card also finishes setup.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<OnboardingDraft, Value>) -> Binding<Value> {
        Binding(
            get: { coordinator.draft[keyPath: keyPath] },
            set: { coordinator.draft[keyPath: keyPath] = $0 }
        )
    }

    private var accentColor: Color {
        let descriptor = coordinator.draft.themeAccent.colorDescriptor
        return Color(
            red: descriptor.redUnit,
            green: descriptor.greenUnit,
            blue: descriptor.blueUnit
        )
    }
}

private struct OnboardingEdgePreview: View {
    let edge: SidebarEdge

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(.secondary.opacity(0.22)).frame(width: 6, height: 6)
                        }
                        Spacer()
                    }
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.secondary.opacity(index == 0 ? 0.2 : 0.1))
                            .frame(height: index == 0 ? 12 : 8)
                    }
                    Spacer()
                }
                .padding(16)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: proxy.size.width * 0.38)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "message.fill").foregroundStyle(Color.accentColor)
                            Text("SideCord").font(.caption.bold())
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
                    .shadow(color: Color.accentColor.opacity(0.2), radius: 16)
            }
        }
        .animation(.snappy(duration: 0.4), value: edge)
    }
}
