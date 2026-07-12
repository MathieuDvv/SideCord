import AppKit

final class SidebarPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        level = .floating
        collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        minSize = NSSize(width: PanelGeometry.minimumWidth, height: 300)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        worksWhenModal = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
