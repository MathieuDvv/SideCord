import AppKit

enum FloatingPanelSpacePolicy {
    /// Present the panels in every Space without activating SideCord.
    ///
    /// The nonactivating panel style is what prevents clicking or focusing the
    /// panel from activating the app and returning to its launch Space. Keeping
    /// `canJoinAllSpaces` preserves pinned panels and full-screen overlays.
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .canJoinAllApplications,
        .fullScreenAuxiliary,
        .ignoresCycle
    ]

    static let nonactivatingStyle: NSWindow.StyleMask = .nonactivatingPanel
}

final class SidebarPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [
                .borderless,
                .resizable,
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
        // WKWebView contains several nested focusable views whose
        // needsPanelToBecomeKey values can differ during a click. Let the panel
        // acquire key status consistently so text selection does not flicker.
        becomesKeyOnlyIfNeeded = false
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
