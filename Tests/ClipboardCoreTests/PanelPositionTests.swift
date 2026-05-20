import XCTest
import AppKit
@testable import ClipboardCore

final class PanelPositionTests: XCTestCase {

    private let panelSize = CGSize(width: 620, height: 420)

    func testClamp_originFitsInsideFrame_unchanged() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: 400, y: 300)
        let result = PanelPositionCalculator.clampToVisible(
            origin: origin, panelSize: panelSize, visibleFrame: frame
        )
        XCTAssertEqual(result, origin)
    }

    func testClamp_originOffLeftEdge_clampsToMinX() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: -100, y: 300)
        let result = PanelPositionCalculator.clampToVisible(
            origin: origin, panelSize: panelSize, visibleFrame: frame
        )
        XCTAssertEqual(result.x, frame.minX)
    }

    func testClamp_originOffRightEdge_clampsToMaxXMinusPanelWidth() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: 1400, y: 300)
        let result = PanelPositionCalculator.clampToVisible(
            origin: origin, panelSize: panelSize, visibleFrame: frame
        )
        XCTAssertEqual(result.x, frame.maxX - panelSize.width)
    }

    func testClampFrame_keepsWholePanelInsideVisibleFrame() {
        let frame = NSRect(x: 0, y: 25, width: 1440, height: 875)
        let panelFrame = NSRect(x: 1200, y: -80, width: panelSize.width, height: panelSize.height)

        let result = PanelPositionCalculator.clampToVisible(
            frame: panelFrame, visibleFrame: frame
        )

        XCTAssertEqual(result.origin.x, frame.maxX - panelSize.width)
        XCTAssertEqual(result.origin.y, frame.minY)
        XCTAssertEqual(result.size, panelSize)
    }

    func testCenter_returnsFrameMidpoint() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let result = PanelPositionCalculator.centerOrigin(
            panelSize: panelSize, visibleFrame: frame
        )
        let expectedX = frame.midX - panelSize.width / 2
        let expectedY = frame.midY - panelSize.height / 2 + 80
        XCTAssertEqual(result.x, expectedX)
        XCTAssertEqual(result.y, expectedY)
    }

    func testCenter_clampsUpwardOffsetInsideShortVisibleFrame() {
        let frame = NSRect(x: 0, y: 25, width: 700, height: 470)

        let result = PanelPositionCalculator.centerOrigin(
            panelSize: panelSize, visibleFrame: frame
        )

        XCTAssertEqual(result.y, frame.maxY - panelSize.height)
    }

    func testFollowMouseNearBottomRight_clampsInsideVisibleFrame() {
        let frame = NSRect(x: 0, y: 25, width: 1440, height: 875)
        let mouseLocation = NSPoint(x: 1435, y: 30)

        let result = PanelPositionCalculator.followMouseOrigin(
            mouseLocation: mouseLocation,
            panelSize: panelSize,
            visibleFrame: frame
        )

        XCTAssertEqual(result.x, frame.maxX - panelSize.width)
        XCTAssertEqual(result.y, frame.minY)
    }

    func testStatusBarClick_originBelowIcon() {
        let iconOrigin = NSPoint(x: 1300, y: 780)
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let result = PanelPositionCalculator.statusBarClickOrigin(
            iconOrigin: iconOrigin, panelSize: panelSize, visibleFrame: frame
        )
        XCTAssertLessThan(result.y, iconOrigin.y)
    }
}
