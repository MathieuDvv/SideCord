import AppKit
import QuartzCore

struct AttentionGlowCallState: Equatable {
    private(set) var isActive = false
    private(set) var isAcknowledged = false

    var shouldPresent: Bool { isActive && !isAcknowledged }

    mutating func update(isActive: Bool, sidebarIsVisible: Bool) {
        guard isActive else {
            self.isActive = false
            isAcknowledged = false
            return
        }

        if !self.isActive {
            self.isActive = true
            isAcknowledged = sidebarIsVisible
        } else if sidebarIsVisible {
            isAcknowledged = true
        }
    }

    mutating func acknowledge() {
        if isActive { isAcknowledged = true }
    }
}

@MainActor
final class AttentionGlowController {
    enum Presentation: Equatable {
        case hidden
        case notification
        case call
    }

    private(set) var presentation: Presentation = .hidden
    private(set) var displayID: String?
    let panel = AttentionGlowPanel()

    private var completionWorkItem: DispatchWorkItem?
    private var generation: UInt64 = 0

    var isPresenting: Bool { presentation != .hidden || panel.isVisible }

    func presentNotification(
        on screen: NSScreen,
        edge: SidebarEdge,
        color: NSColor,
        strength: AttentionGlowStrength = .normal
    ) {
        let wasVisible = panel.isVisible
        configure(on: screen, edge: edge, color: color, strength: strength)
        generation &+= 1
        let currentGeneration = generation
        completionWorkItem?.cancel()
        presentation = .notification
        panel.orderFrontRegardless()

        guard let layer = panel.glowView.layer else { return }
        let presentationLayer = layer.presentation()
        let initialOpacity = wasVisible ? (presentationLayer?.opacity ?? layer.opacity) : 0
        let initialTransform = wasVisible
            ? (presentationLayer?.transform ?? layer.transform)
            : CATransform3DMakeScale(1, 0.18, 1)
        layer.removeAllAnimations()
        layer.opacity = 0
        layer.transform = CATransform3DIdentity

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = reduceMotion ? 1.8 : (strength == .strong ? 3.15 : 2.6)
        let peakOpacity: Float = strength == .subtle ? 0.82 : 1
        let sustainedOpacity: Float = strength == .strong ? 0.9 : 0.78
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [initialOpacity, peakOpacity, sustainedOpacity, 0]
        opacity.keyTimes = [0, 0.12, strength == .strong ? 0.58 : 0.48, 1]

        let group = CAAnimationGroup()
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        if reduceMotion {
            group.animations = [opacity]
        } else {
            let transform = CAKeyframeAnimation(keyPath: "transform")
            transform.values = [
                NSValue(caTransform3D: initialTransform),
                NSValue(caTransform3D: CATransform3DMakeScale(
                    1,
                    strength == .strong ? 1.12 : 1.02,
                    1
                )),
                NSValue(caTransform3D: CATransform3DIdentity),
                NSValue(caTransform3D: CATransform3DIdentity)
            ]
            transform.keyTimes = opacity.keyTimes
            group.animations = [opacity, transform]
        }
        layer.add(group, forKey: "sidecord-notification-glow")
        scheduleOrderOut(after: duration, generation: currentGeneration)
    }

    func presentCall(
        on screen: NSScreen,
        edge: SidebarEdge,
        color: NSColor,
        strength: AttentionGlowStrength = .normal
    ) {
        configure(on: screen, edge: edge, color: color, strength: strength)
        generation &+= 1
        completionWorkItem?.cancel()
        presentation = .call
        panel.orderFrontRegardless()

        guard let layer = panel.glowView.layer else { return }
        layer.removeAllAnimations()
        layer.transform = CATransform3DIdentity

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            layer.opacity = 0.68
            return
        }

        layer.opacity = 0.78
        let breathing = CABasicAnimation(keyPath: "opacity")
        breathing.fromValue = 0.44
        breathing.toValue = 0.92
        breathing.duration = 1.35
        breathing.autoreverses = true
        breathing.repeatCount = .infinity
        breathing.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(breathing, forKey: "sidecord-call-breathing")
    }

    func updateAppearance(
        on screen: NSScreen,
        edge: SidebarEdge,
        color: NSColor,
        strength: AttentionGlowStrength = .normal
    ) {
        guard isPresenting else { return }
        configure(on: screen, edge: edge, color: color, strength: strength)
    }

    func refreshAccessibilityAnimation() {
        guard presentation == .call,
              let screen = currentScreen
        else { return }
        presentCall(
            on: screen,
            edge: currentEdge,
            color: currentColor,
            strength: currentStrength
        )
    }

    func dismissSoftly() {
        guard panel.isVisible else {
            presentation = .hidden
            return
        }
        generation &+= 1
        let currentGeneration = generation
        completionWorkItem?.cancel()
        presentation = .hidden

        guard let layer = panel.glowView.layer else {
            panel.orderOut(nil)
            return
        }
        let initialOpacity = layer.presentation()?.opacity ?? layer.opacity
        layer.removeAllAnimations()
        layer.opacity = 0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = initialOpacity
        fade.toValue = 0
        fade.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.2 : 0.55
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "sidecord-glow-dismiss")
        scheduleOrderOut(after: fade.duration, generation: currentGeneration)
    }

    func hideImmediately() {
        generation &+= 1
        completionWorkItem?.cancel()
        completionWorkItem = nil
        presentation = .hidden
        panel.glowView.layer?.removeAllAnimations()
        panel.glowView.layer?.opacity = 0
        panel.orderOut(nil)
    }

    private var currentScreen: NSScreen? {
        guard let displayID else { return panel.screen }
        return NSScreen.screens.first { PanelGeometry.displayID(for: $0) == displayID }
    }

    private var currentEdge: SidebarEdge = .right
    private var currentStrength: AttentionGlowStrength = .normal
    private var currentColor = NSColor(
        srgbRed: 88 / 255,
        green: 101 / 255,
        blue: 242 / 255,
        alpha: 1
    )

    private func configure(
        on screen: NSScreen,
        edge: SidebarEdge,
        color: NSColor,
        strength: AttentionGlowStrength
    ) {
        displayID = PanelGeometry.displayID(for: screen)
        currentEdge = edge
        currentColor = color
        currentStrength = strength
        panel.setFrame(
            PanelGeometry.attentionGlowFrame(
                in: screen.frame,
                edge: edge,
                requestedWidth: strength.glowWidth
            ),
            display: false
        )
        panel.glowView.update(edge: edge, color: color, intensity: strength.intensity)
        panel.glowView.layoutSubtreeIfNeeded()
    }

    private func scheduleOrderOut(after duration: TimeInterval, generation: UInt64) {
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.panel.orderOut(nil)
                self.panel.glowView.layer?.removeAllAnimations()
                self.panel.glowView.layer?.opacity = 0
                self.presentation = .hidden
                self.completionWorkItem = nil
            }
        }
        completionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }
}
