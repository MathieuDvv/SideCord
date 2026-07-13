import AppKit
import QuartzCore

@MainActor
final class AttentionGlowPanel: NSPanel {
    let glowView = AttentionGlowView()

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
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        ignoresMouseEvents = true
        animationBehavior = .none
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        worksWhenModal = true
        contentView = glowView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AttentionGlowView: NSView {
    private let bloomLayer = CAGradientLayer()
    private let coreLayer = CALayer()
    private let bloomMask = CAGradientLayer()
    private let coreMask = CAGradientLayer()
    private var edge: SidebarEdge = .right

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.masksToBounds = true
        rootLayer.opacity = 0
        layer = rootLayer

        configureVerticalMask(bloomMask)
        configureVerticalMask(coreMask)
        bloomLayer.mask = bloomMask
        coreLayer.mask = coreMask
        rootLayer.addSublayer(bloomLayer)
        rootLayer.addSublayer(coreLayer)
        update(edge: .right, color: Self.defaultColor)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bloomLayer.frame = bounds
        bloomMask.frame = bounds
        coreMask.frame = bounds
        coreLayer.frame = NSRect(
            x: edge == .left ? 0 : max(0, bounds.width - 2),
            y: 0,
            width: min(2, bounds.width),
            height: bounds.height
        )
        CATransaction.commit()
    }

    func update(edge: SidebarEdge, color: NSColor) {
        self.edge = edge
        let resolvedColor = color.usingColorSpace(.sRGB) ?? color
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bloomLayer.type = .axial
        bloomLayer.colors = [
            resolvedColor.withAlphaComponent(0.92).cgColor,
            resolvedColor.withAlphaComponent(0.48).cgColor,
            resolvedColor.withAlphaComponent(0.14).cgColor,
            resolvedColor.withAlphaComponent(0).cgColor
        ]
        bloomLayer.locations = [0, 0.08, 0.34, 1]
        bloomLayer.startPoint = CGPoint(x: edge == .left ? 0 : 1, y: 0.5)
        bloomLayer.endPoint = CGPoint(x: edge == .left ? 1 : 0, y: 0.5)
        coreLayer.backgroundColor = resolvedColor.withAlphaComponent(0.95).cgColor
        CATransaction.commit()
        needsLayout = true
    }

    private func configureVerticalMask(_ mask: CAGradientLayer) {
        mask.type = .axial
        mask.startPoint = CGPoint(x: 0.5, y: 0)
        mask.endPoint = CGPoint(x: 0.5, y: 1)
        mask.colors = [
            NSColor.white.withAlphaComponent(0).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor,
            NSColor.white.withAlphaComponent(0.28).cgColor,
            NSColor.white.withAlphaComponent(0.76).cgColor,
            NSColor.white.cgColor,
            NSColor.white.withAlphaComponent(0.76).cgColor,
            NSColor.white.withAlphaComponent(0.28).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor
        ]
        mask.locations = [0, 0.08, 0.22, 0.38, 0.5, 0.62, 0.78, 0.92, 1]
    }

    private static let defaultColor = NSColor(
        srgbRed: 88 / 255,
        green: 101 / 255,
        blue: 242 / 255,
        alpha: 1
    )
}
