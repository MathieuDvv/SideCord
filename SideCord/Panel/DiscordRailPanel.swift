import AppKit
import SwiftUI

@MainActor
final class DiscordRailPanel: NSPanel {
    init(settings: AppSettings, railModel: DiscordRailModel) {
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
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        worksWhenModal = true

        let hostingView = NSHostingView(
            rootView: DiscordRailView(settings: settings, railModel: railModel)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 28
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        contentView = hostingView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
