import AppKit
import QuartzCore
import SwiftUI

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
    private var intensity = 1.0

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
        update(edge: .right, color: Self.defaultColor, intensity: 1)
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
        let coreWidth = min(intensity >= 1.5 ? 4 : 2, bounds.width)
        coreLayer.frame = NSRect(
            x: edge == .left ? 0 : max(0, bounds.width - coreWidth),
            y: 0,
            width: coreWidth,
            height: bounds.height
        )
        CATransaction.commit()
    }

    func update(edge: SidebarEdge, color: NSColor, intensity: Double) {
        self.edge = edge
        let resolvedColor = color.usingColorSpace(.sRGB) ?? color
        let strength = min(max(intensity.isFinite ? intensity : 1, 0.4), 2)
        self.intensity = strength
        let middleLocation = min(0.54, 0.34 + max(0, strength - 1) * 0.22)
        let innerLocation = min(0.14, 0.08 + max(0, strength - 1) * 0.07)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bloomLayer.type = .axial
        bloomLayer.colors = [
            resolvedColor.withAlphaComponent(min(1, 0.92 * strength)).cgColor,
            resolvedColor.withAlphaComponent(min(1, 0.48 * strength)).cgColor,
            resolvedColor.withAlphaComponent(min(1, 0.14 * strength)).cgColor,
            resolvedColor.withAlphaComponent(0).cgColor
        ]
        bloomLayer.locations = [0, NSNumber(value: innerLocation), NSNumber(value: middleLocation), 1]
        bloomLayer.startPoint = CGPoint(x: edge == .left ? 0 : 1, y: 0.5)
        bloomLayer.endPoint = CGPoint(x: edge == .left ? 1 : 0, y: 0.5)
        coreLayer.backgroundColor = resolvedColor
            .withAlphaComponent(min(1, 0.95 * strength))
            .cgColor
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

@MainActor
final class IncomingCallCardPanel: NSPanel {
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
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        worksWhenModal = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class IncomingCallCardController {
    let panel = IncomingCallCardPanel()
    private(set) var displayID: String?
    private(set) var descriptor: IncomingCallDescriptor?

    func present(
        _ descriptor: IncomingCallDescriptor,
        on screen: NSScreen,
        edge: SidebarEdge,
        accent: SideCordAccent,
        colorScheme: ThemeColorScheme,
        onAnswer: @escaping () -> Void,
        onDecline: @escaping () -> Void
    ) {
        self.descriptor = descriptor
        displayID = PanelGeometry.displayID(for: screen)
        let rootView = IncomingCallCardView(
            descriptor: descriptor,
            accent: accent,
            colorScheme: colorScheme,
            onAnswer: onAnswer,
            onDecline: onDecline
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 24
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView
        panel.setFrame(
            PanelGeometry.incomingCallCardFrame(
                in: screen.visibleFrame,
                edge: edge
            ),
            display: true
        )
        panel.orderFrontRegardless()
    }

    func hide() {
        descriptor = nil
        displayID = nil
        panel.orderOut(nil)
        panel.contentView = nil
    }
}

private struct IncomingCallCardView: View {
    let descriptor: IncomingCallDescriptor
    let accent: SideCordAccent
    let colorScheme: ThemeColorScheme
    let onAnswer: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(accentColor.opacity(0.20))
                Image(systemName: "phone.arrow.down.left.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("Incoming call")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(descriptor.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDecline) {
                Image(systemName: "phone.down.fill")
                    .frame(width: 30, height: 30)
                    .background(.red, in: Circle())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Decline call")
            .accessibilityLabel("Decline call from \(descriptor.displayName)")

            Button(action: onAnswer) {
                Image(systemName: "phone.fill")
                    .frame(width: 30, height: 30)
                    .background(.green, in: Circle())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Answer call")
            .accessibilityLabel("Answer call from \(descriptor.displayName)")
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.88))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(accentColor.opacity(0.30), lineWidth: 1)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .preferredColorScheme(preferredColorScheme)
    }

    private var accentColor: Color {
        let color = accent.colorDescriptor
        return Color(red: color.redUnit, green: color.greenUnit, blue: color.blueUnit)
    }

    private var preferredColorScheme: ColorScheme? {
        switch colorScheme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
