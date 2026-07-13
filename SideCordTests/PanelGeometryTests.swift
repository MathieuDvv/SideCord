import AppKit
import XCTest
@testable import SideCord

final class PanelGeometryTests: XCTestCase {
    func testFloatingPanelsJoinEverySpaceWithoutMovingSpaceOwnership() {
        let behavior = FloatingPanelSpacePolicy.collectionBehavior

        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(behavior.contains(.moveToActiveSpace))
        XCTAssertTrue(behavior.contains(.canJoinAllApplications))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behavior.contains(.ignoresCycle))
        XCTAssertTrue(
            FloatingPanelSpacePolicy.nonactivatingStyle.contains(.nonactivatingPanel)
        )
    }

    @MainActor
    func testSidebarPanelTakesKeyStatusConsistentlyForWebInputs() {
        let panel = SidebarPanel()

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.becomesKeyOnlyIfNeeded)
    }

    @MainActor
    func testAttentionGlowPanelIsClickThroughAndNeverTakesFocus() {
        let panel = AttentionGlowPanel()

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertEqual(panel.collectionBehavior, FloatingPanelSpacePolicy.collectionBehavior)
    }

    func testAttentionCallIsAcknowledgedUntilThatCallEnds() {
        var state = AttentionGlowCallState()

        state.update(isActive: true, sidebarIsVisible: false)
        XCTAssertTrue(state.shouldPresent)

        state.acknowledge()
        XCTAssertFalse(state.shouldPresent)

        state.update(isActive: true, sidebarIsVisible: false)
        XCTAssertFalse(state.shouldPresent)

        state.update(isActive: false, sidebarIsVisible: false)
        state.update(isActive: true, sidebarIsVisible: false)
        XCTAssertTrue(state.shouldPresent)
    }

    func testCallBeginningWhileSidebarIsVisibleStartsAcknowledged() {
        var state = AttentionGlowCallState()

        state.update(isActive: true, sidebarIsVisible: true)

        XCTAssertTrue(state.isActive)
        XCTAssertTrue(state.isAcknowledged)
        XCTAssertFalse(state.shouldPresent)
    }

    func testRightSidebarAnchorsToUsableFrame() {
        let usable = NSRect(x: 0, y: 40, width: 1_440, height: 860)
        let frame = PanelGeometry.sidebarFrame(
            in: usable,
            edge: .right,
            requestedWidth: 420
        )

        XCTAssertEqual(frame, NSRect(x: 1_020, y: 40, width: 420, height: 860))
    }

    func testLeftSidebarAnchorsToUsableFrame() {
        let usable = NSRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        let frame = PanelGeometry.sidebarFrame(
            in: usable,
            edge: .left,
            requestedWidth: 500
        )

        XCTAssertEqual(frame, NSRect(x: -1_920, y: 0, width: 500, height: 1_080))
    }

    func testWidthIsLimitedToEightyPercentOfDisplay() {
        let usable = NSRect(x: 0, y: 0, width: 1_000, height: 700)
        XCTAssertEqual(PanelGeometry.constrainedWidth(2_000, in: usable), 800)
    }

    func testRailSitsLeftOfRightEdgeSidebarTowardScreenCenter() throws {
        let usable = NSRect(x: 0, y: 40, width: 1_440, height: 860)
        let sidebar = PanelGeometry.sidebarFrame(
            in: usable,
            edge: .right,
            requestedWidth: 420,
            inset: 16
        )
        let rail = try XCTUnwrap(PanelGeometry.railFrame(
            adjacentTo: sidebar,
            in: usable,
            edge: .right
        ))

        XCTAssertEqual(sidebar, NSRect(x: 1_004, y: 56, width: 420, height: 828))
        XCTAssertEqual(rail, NSRect(x: 916, y: 68, width: 76, height: 804))
        XCTAssertEqual(sidebar.minX - rail.maxX, PanelGeometry.railGap)
    }

    func testRailSitsRightOfLeftEdgeSidebarTowardScreenCenter() throws {
        let usable = NSRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        let sidebar = PanelGeometry.sidebarFrame(
            in: usable,
            edge: .left,
            requestedWidth: 500,
            inset: 16
        )
        let rail = try XCTUnwrap(PanelGeometry.railFrame(
            adjacentTo: sidebar,
            in: usable,
            edge: .left
        ))

        XCTAssertEqual(sidebar, NSRect(x: -1_904, y: 16, width: 500, height: 1_048))
        XCTAssertEqual(rail, NSRect(x: -1_392, y: 28, width: 76, height: 1_024))
        XCTAssertEqual(rail.minX - sidebar.maxX, PanelGeometry.railGap)
    }

    func testRailNarrowsWithoutOverlappingSidebarOnSmallDisplay() throws {
        let usable = NSRect(x: 0, y: 0, width: 360, height: 400)
        let sidebar = NSRect(x: 72, y: 0, width: 288, height: 400)
        let rail = try XCTUnwrap(PanelGeometry.railFrame(
            adjacentTo: sidebar,
            in: usable,
            edge: .right,
            requestedWidth: 76,
            gap: 12
        ))

        XCTAssertEqual(rail, NSRect(x: 0, y: 12, width: 60, height: 376))
        XCTAssertEqual(sidebar.minX - rail.maxX, 12)
    }

    func testRailIsUnavailableWhenSidebarConsumesTheUsableFrame() {
        let usable = NSRect(x: 0, y: 0, width: 1_000, height: 700)

        XCTAssertNil(PanelGeometry.railFrame(
            adjacentTo: usable,
            in: usable,
            edge: .right
        ))
    }

    func testFloatingInsetMovesAndShortensRightSidebar() {
        let usable = NSRect(x: 0, y: 40, width: 1_440, height: 860)
        let frame = PanelGeometry.sidebarFrame(
            in: usable,
            edge: .right,
            requestedWidth: 420,
            inset: 16
        )

        XCTAssertEqual(frame, NSRect(x: 1_004, y: 56, width: 420, height: 828))
    }

    func testFloatingInsetWorksWithNegativeDisplayOrigins() {
        let usable = NSRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        let frame = PanelGeometry.sidebarFrame(
            in: usable,
            edge: .left,
            requestedWidth: 500,
            inset: 16
        )

        XCTAssertEqual(frame, NSRect(x: -1_904, y: 16, width: 500, height: 1_048))
    }

    func testInsetConstrainsWidthToRemainingDisplaySpace() {
        let usable = NSRect(x: 0, y: 0, width: 360, height: 400)
        let frame = PanelGeometry.sidebarFrame(
            in: usable,
            edge: .right,
            requestedWidth: 900,
            inset: 48
        )

        XCTAssertEqual(frame, NSRect(x: 48, y: 48, width: 264, height: 304))
    }

    func testNonfiniteGeometryInsetFallsBackToFlushPlacement() {
        let usable = NSRect(x: 0, y: 40, width: 1_440, height: 860)
        let frame = PanelGeometry.sidebarFrame(
            in: usable,
            edge: .right,
            requestedWidth: 420,
            inset: .nan
        )

        XCTAssertEqual(frame, NSRect(x: 1_020, y: 40, width: 420, height: 860))
    }

    func testHiddenFramesMoveFullyBeyondPhysicalScreen() {
        let screen = NSRect(x: 100, y: 0, width: 1_000, height: 800)
        let visible = NSRect(x: 700, y: 20, width: 400, height: 760)

        let left = PanelGeometry.hiddenFrame(from: visible, screenFrame: screen, edge: .left)
        let right = PanelGeometry.hiddenFrame(from: visible, screenFrame: screen, edge: .right)

        XCTAssertLessThan(left.maxX, screen.minX)
        XCTAssertGreaterThan(right.minX, screen.maxX)
        XCTAssertEqual(left.minY, visible.minY)
        XCTAssertEqual(right.minY, visible.minY)
        XCTAssertEqual(left.height, visible.height)
        XCTAssertEqual(right.height, visible.height)
    }

    func testAttentionGlowUsesTheFullPhysicalEdgeWithoutReachingPastIt() {
        let screen = NSRect(x: -1_920, y: -120, width: 1_920, height: 1_200)

        let left = PanelGeometry.attentionGlowFrame(in: screen, edge: .left)
        let right = PanelGeometry.attentionGlowFrame(in: screen, edge: .right)

        XCTAssertEqual(left, NSRect(x: -1_920, y: -120, width: 72, height: 1_200))
        XCTAssertEqual(right, NSRect(x: -72, y: -120, width: 72, height: 1_200))
        XCTAssertEqual(left.minX, screen.minX)
        XCTAssertEqual(right.maxX, screen.maxX)
    }
}
