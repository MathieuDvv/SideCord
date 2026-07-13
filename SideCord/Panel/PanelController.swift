import AppKit
import Combine
import QuartzCore

@MainActor
final class PanelController: NSObject, ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var isMaximized = false

    let panel: SidebarPanel
    let railPanel: DiscordRailPanel

    private let settings: AppSettings
    private let webController: DiscordWebController
    private lazy var edgeMonitor = EdgeMonitor(
        settings: settings,
        isSuppressed: { [weak self] in
            guard let self else { return true }
            return self.isVisible || !self.canPresentPanel
        },
        onTrigger: { [weak self] screen in self?.reveal(on: screen, activate: false) }
    )

    private var activeDisplayID: String?
    private var retractionTimer: Timer?
    private var pointerTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var notificationTokens: [NSObjectProtocol] = []
    private var workspaceNotificationTokens: [NSObjectProtocol] = []
    private var isAnimating = false
    private var isAdjustingFrame = false
    private var animationGeneration = UUID()
    private var sessionIsActive = true
    private var screensAreAwake = true
    private var requiresExplicitDismissal = false
    private var restoreAfterSystemInterruption = false
    private var restoreExplicitDismissalAfterSystemInterruption = false

    init(
        settings: AppSettings,
        webController: DiscordWebController,
        railModel: DiscordRailModel
    ) {
        self.settings = settings
        self.webController = webController
        panel = SidebarPanel()
        railPanel = DiscordRailPanel(settings: settings, railModel: railModel)
        super.init()
        panel.delegate = self
        observeSettings()
        observeSystemEvents()
    }

    func setContentView(_ contentView: NSView) {
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 16
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true
        panel.contentView = contentView
        updatePanelAppearance(maximized: false)
    }

    func start() {
        edgeMonitor.start()
        guard pointerTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluateAutomaticRetraction()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    func stop() {
        edgeMonitor.stop()
        pointerTimer?.invalidate()
        pointerTimer = nil
        cancelAutomaticRetraction()
        panel.orderOut(nil)
        railPanel.orderOut(nil)
        isVisible = false
        panel.contentView = nil
        railPanel.contentView = nil
        panel.delegate = nil
        cancellables.removeAll()

        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens.removeAll()
        for token in workspaceNotificationTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceNotificationTokens.removeAll()
        restoreAfterSystemInterruption = false
        restoreExplicitDismissalAfterSystemInterruption = false
    }

    func toggle() {
        if isVisible {
            retract()
        } else {
            reveal(activate: true)
        }
    }

    func reveal() {
        reveal(activate: false)
    }

    func reveal(activate: Bool) {
        let screen = PanelGeometry.screen(containing: NSEvent.mouseLocation, from: NSScreen.screens)
            ?? NSScreen.main
        guard let screen else { return }
        reveal(on: screen, activate: activate)
    }

    func revealForDevelopment() {
        requiresExplicitDismissal = true
        reveal(activate: true)
    }

    func retract() {
        performRetraction(force: true)
    }

    func togglePin() {
        settings.isPinned.toggle()
        if settings.isPinned {
            cancelAutomaticRetraction()
        } else {
            evaluateAutomaticRetraction()
        }
    }

    func toggleMaximize() {
        guard let screen = activeScreen
                ?? PanelGeometry.screen(containing: NSEvent.mouseLocation, from: NSScreen.screens)
                ?? NSScreen.main
        else { return }

        if !isVisible {
            reveal(on: screen, activate: true)
        }

        isMaximized.toggle()
        setPanelResizable(!isMaximized)
        let targetFrame = isMaximized
            ? screen.visibleFrame
            : normalFrame(for: screen)
        updatePanelAppearance(maximized: isMaximized)
        animatePanel(to: targetFrame, alpha: 1, orderOutWhenComplete: false)
    }

    private var activeScreen: NSScreen? {
        guard let activeDisplayID else { return panel.screen }
        return NSScreen.screens.first {
            PanelGeometry.displayID(for: $0) == activeDisplayID
        }
    }

    private func reveal(on screen: NSScreen, activate: Bool) {
        guard canPresentPanel else { return }
        cancelAutomaticRetraction()
        let displayID = PanelGeometry.displayID(for: screen)

        if isVisible, activeDisplayID == displayID {
            repositionForCurrentSettings()
            if activate {
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.orderFrontRegardless()
            }
            return
        }

        activeDisplayID = displayID
        isMaximized = false
        setPanelResizable(true)
        updatePanelAppearance(maximized: false)

        let targetFrame = normalFrame(for: screen)
        let hiddenFrame = PanelGeometry.hiddenFrame(
            from: targetFrame,
            screenFrame: screen.frame,
            edge: settings.sidebarEdge
        )

        panel.setFrame(hiddenFrame, display: false)
        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.82
        panel.orderFrontRegardless()
        isVisible = true

        animatePanel(to: targetFrame, alpha: 1, orderOutWhenComplete: false)
        if activate {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func performRetraction(force: Bool) {
        guard isVisible, force || !settings.isPinned else { return }
        if force {
            requiresExplicitDismissal = false
        }
        cancelAutomaticRetraction()
        guard let screen = activeScreen ?? panel.screen else {
            panel.orderOut(nil)
            railPanel.orderOut(nil)
            isVisible = false
            return
        }

        isMaximized = false
        setPanelResizable(true)
        updatePanelAppearance(maximized: false)
        isVisible = false

        let hiddenFrame = PanelGeometry.hiddenFrame(
            from: panel.frame,
            screenFrame: screen.frame,
            edge: settings.sidebarEdge
        )
        let targetAlpha: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.75
        animatePanel(to: hiddenFrame, alpha: targetAlpha, orderOutWhenComplete: true)
    }

    private func normalFrame(for screen: NSScreen) -> NSRect {
        let displayID = PanelGeometry.displayID(for: screen)
        return PanelGeometry.sidebarFrame(
            in: screen.visibleFrame,
            edge: settings.sidebarEdge,
            requestedWidth: settings.width(forDisplay: displayID),
            inset: settings.sidebarInset
        )
    }

    private func animatePanel(
        to targetFrame: NSRect,
        alpha: CGFloat,
        orderOutWhenComplete: Bool
    ) {
        animationGeneration = UUID()
        let generation = animationGeneration
        isAnimating = true

        let screen = activeScreen ?? panel.screen
        let targetRailFrame = orderOutWhenComplete || isMaximized
            ? nil
            : screen.flatMap { railFrame(adjacentTo: targetFrame, on: $0) }
        var railAnimationTarget: NSRect?

        if let targetRailFrame, let screen {
            if !railPanel.isVisible {
                let hiddenRailFrame = PanelGeometry.hiddenFrame(
                    from: targetRailFrame,
                    screenFrame: screen.frame,
                    edge: settings.sidebarEdge
                )
                railPanel.setFrame(hiddenRailFrame, display: false)
                railPanel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                    ? 1
                    : 0.78
                railPanel.orderFrontRegardless()
            }
            railAnimationTarget = targetRailFrame
        } else if railPanel.isVisible, let screen {
            railAnimationTarget = PanelGeometry.hiddenFrame(
                from: railPanel.frame,
                screenFrame: screen.frame,
                edge: settings.sidebarEdge
            )
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            panel.setFrame(targetFrame, display: true)
            if let railAnimationTarget {
                railPanel.setFrame(railAnimationTarget, display: true)
            }
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.12 : 0.28
            context.timingFunction = reduceMotion
                ? CAMediaTimingFunction(name: .linear)
                : CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            if !reduceMotion {
                panel.animator().setFrame(targetFrame, display: true)
                if let railAnimationTarget {
                    railPanel.animator().setFrame(railAnimationTarget, display: true)
                }
            }
            panel.animator().alphaValue = alpha
            railPanel.animator().alphaValue = targetRailFrame == nil ? 0 : alpha
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.animationGeneration == generation else { return }
                self.isAnimating = false
                if orderOutWhenComplete, !self.isVisible {
                    self.panel.orderOut(nil)
                }
                if targetRailFrame == nil {
                    self.railPanel.orderOut(nil)
                    self.railPanel.alphaValue = 1
                }
            }
        }
    }

    private func evaluateAutomaticRetraction() {
        guard isVisible,
              !settings.isPinned,
              !requiresExplicitDismissal,
              !isAnimating
        else {
            if settings.isPinned { cancelAutomaticRetraction() }
            return
        }

        if isPointerEngaged(at: NSEvent.mouseLocation)
            || panel.isKeyWindow
            || railPanel.isKeyWindow
            || panel.attachedSheet != nil
            || railPanel.attachedSheet != nil {
            cancelAutomaticRetraction()
        } else {
            scheduleAutomaticRetraction()
        }
    }

    private func isPointerEngaged(at point: NSPoint) -> Bool {
        var engagementFrame = panel.frame
        if railPanel.isVisible {
            engagementFrame = engagementFrame.union(railPanel.frame)
        }
        if engagementFrame.insetBy(dx: -2, dy: -2).contains(point) {
            return true
        }

        guard let screen = activeScreen ?? panel.screen else { return false }
        let verticalFrame = screen.visibleFrame.insetBy(dx: 0, dy: -2)
        let bridgeFrame: NSRect

        switch settings.sidebarEdge {
        case .left:
            let minX = screen.frame.minX - 2
            bridgeFrame = NSRect(
                x: minX,
                y: verticalFrame.minY,
                width: max(0, panel.frame.minX + 2 - minX),
                height: verticalFrame.height
            )
        case .right:
            let minX = panel.frame.maxX - 2
            bridgeFrame = NSRect(
                x: minX,
                y: verticalFrame.minY,
                width: max(0, screen.frame.maxX + 2 - minX),
                height: verticalFrame.height
            )
        }

        return bridgeFrame.contains(point)
    }

    private func scheduleAutomaticRetraction() {
        guard retractionTimer == nil else { return }
        let timer = Timer(timeInterval: settings.retractionDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.retractionTimer = nil
                guard !self.isPointerEngaged(at: NSEvent.mouseLocation),
                      !self.panel.isKeyWindow,
                      !self.railPanel.isKeyWindow,
                      self.panel.attachedSheet == nil,
                      self.railPanel.attachedSheet == nil,
                      !self.settings.isPinned
                else { return }
                self.performRetraction(force: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        retractionTimer = timer
    }

    private func cancelAutomaticRetraction() {
        retractionTimer?.invalidate()
        retractionTimer = nil
    }

    private func persistCurrentWidth(on screen: NSScreen) {
        let constrained = PanelGeometry.constrainedWidth(
            panel.frame.width,
            in: screen.visibleFrame,
            inset: settings.sidebarInset
        )
        settings.setWidth(constrained, forDisplay: PanelGeometry.displayID(for: screen))
    }

    private func repositionForCurrentSettings() {
        guard isVisible, let screen = activeScreen ?? panel.screen else { return }
        updatePanelAppearance(maximized: isMaximized)
        let target = isMaximized ? screen.visibleFrame : normalFrame(for: screen)
        animatePanel(to: target, alpha: 1, orderOutWhenComplete: false)
    }

    private var shouldPresentRail: Bool {
        guard settings.floatingRailEnabled else { return false }
        let navigation = settings.discordLayoutOptions.navigationPresentation
        return navigation == .floating
            || (navigation == .hidden && webController.isNavigationDrawerOpen)
    }

    private func railFrame(adjacentTo sidebarFrame: NSRect, on screen: NSScreen) -> NSRect? {
        guard shouldPresentRail, !isMaximized else { return nil }
        return PanelGeometry.railFrame(
            adjacentTo: sidebarFrame,
            in: screen.visibleFrame,
            edge: settings.sidebarEdge
        )
    }

    private func updatePanelAppearance(maximized: Bool) {
        panel.contentView?.layer?.cornerRadius = maximized ? 0 : 16
        panel.contentView?.layer?.masksToBounds = true
        panel.hasShadow = !maximized
        panel.minSize = NSSize(
            width: PanelGeometry.minimumWidth,
            height: 300
        )
    }

    private var canPresentPanel: Bool {
        sessionIsActive && screensAreAwake
    }

    private func setPanelResizable(_ isResizable: Bool) {
        if isResizable {
            panel.styleMask.insert(.resizable)
        } else {
            panel.styleMask.remove(.resizable)
        }
    }

    private func observeSettings() {
        settings.$sidebarEdge
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.repositionForCurrentSettings()
                }
            }
            .store(in: &cancellables)

        settings.$sidebarWidth
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.isMaximized else { return }
                    self.repositionForCurrentSettings()
                }
            }
            .store(in: &cancellables)

        settings.$sidebarInset
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.isMaximized else { return }
                    self.repositionForCurrentSettings()
                }
            }
            .store(in: &cancellables)

        Publishers.Merge(
            settings.$discordLayoutMode.dropFirst().map { _ in () },
            settings.$customDiscordLayoutOptions.dropFirst().map { _ in () }
        )
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updatePanelAppearance(maximized: self.isMaximized)
                if !self.isMaximized {
                    self.repositionForCurrentSettings()
                }
            }
        }
            .store(in: &cancellables)

        settings.$floatingRailEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.isVisible, !self.isMaximized {
                        self.repositionForCurrentSettings()
                    } else if !self.shouldPresentRail {
                        self.railPanel.orderOut(nil)
                    }
                }
            }
            .store(in: &cancellables)

        webController.$isNavigationDrawerOpen
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.updatePanelAppearance(maximized: self.isMaximized)
                    if !self.isMaximized {
                        self.repositionForCurrentSettings()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func observeSystemEvents() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleScreenConfigurationChange()
            }
        })

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observeWorkspaceNotification(
            NSWorkspace.sessionDidResignActiveNotification,
            in: workspaceCenter
        ) { controller in
            controller.sessionIsActive = false
            controller.suspendPresentationForSystemInterruption()
        }
        observeWorkspaceNotification(
            NSWorkspace.sessionDidBecomeActiveNotification,
            in: workspaceCenter
        ) { controller in
            controller.sessionIsActive = true
            controller.restorePresentationAfterSystemInterruptionIfNeeded()
        }
        observeWorkspaceNotification(
            NSWorkspace.screensDidSleepNotification,
            in: workspaceCenter
        ) { controller in
            controller.screensAreAwake = false
            controller.suspendPresentationForSystemInterruption()
        }
        observeWorkspaceNotification(
            NSWorkspace.screensDidWakeNotification,
            in: workspaceCenter
        ) { controller in
            controller.screensAreAwake = true
            controller.restorePresentationAfterSystemInterruptionIfNeeded()
        }
    }

    private func suspendPresentationForSystemInterruption() {
        if isVisible {
            restoreAfterSystemInterruption = true
            restoreExplicitDismissalAfterSystemInterruption = requiresExplicitDismissal
        }
        performRetraction(force: true)
    }

    private func restorePresentationAfterSystemInterruptionIfNeeded() {
        guard canPresentPanel, restoreAfterSystemInterruption else { return }

        let restoreExplicitDismissal = restoreExplicitDismissalAfterSystemInterruption
        restoreAfterSystemInterruption = false
        restoreExplicitDismissalAfterSystemInterruption = false
        requiresExplicitDismissal = restoreExplicitDismissal
        reveal(activate: false)
    }

    private func observeWorkspaceNotification(
        _ name: Notification.Name,
        in center: NotificationCenter,
        handler: @escaping @MainActor (PanelController) -> Void
    ) {
        workspaceNotificationTokens.append(center.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        })
    }

    private func handleScreenConfigurationChange() {
        guard isVisible else { return }
        let screen = activeScreen
            ?? PanelGeometry.screen(containing: NSEvent.mouseLocation, from: NSScreen.screens)
            ?? NSScreen.main
        guard let screen else {
            performRetraction(force: true)
            return
        }
        activeDisplayID = PanelGeometry.displayID(for: screen)
        repositionForCurrentSettings()
    }
}

extension PanelController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        guard isVisible,
              !isMaximized,
              !isAnimating,
              !isAdjustingFrame,
              let screen = activeScreen ?? panel.screen
        else { return }

        isAdjustingFrame = true
        let correctedFrame = PanelGeometry.sidebarFrame(
            in: screen.visibleFrame,
            edge: settings.sidebarEdge,
            requestedWidth: panel.frame.width,
            inset: settings.sidebarInset
        )
        if !NSEqualRects(panel.frame, correctedFrame) {
            panel.setFrame(correctedFrame, display: true)
        }
        if let railFrame = railFrame(adjacentTo: correctedFrame, on: screen) {
            railPanel.setFrame(railFrame, display: true)
            if !railPanel.isVisible { railPanel.orderFrontRegardless() }
        } else {
            railPanel.orderOut(nil)
        }
        isAdjustingFrame = false
        persistCurrentWidth(on: screen)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        cancelAutomaticRetraction()
    }

    func windowDidResignKey(_ notification: Notification) {
        evaluateAutomaticRetraction()
    }
}
