import AppKit
import XCTest
@testable import SideCord

final class PanelGeometryTests: XCTestCase {
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
}
