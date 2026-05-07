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

    func testStatusBarClick_originBelowIcon() {
        let iconOrigin = NSPoint(x: 1300, y: 780)
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let result = PanelPositionCalculator.statusBarClickOrigin(
            iconOrigin: iconOrigin, panelSize: panelSize, visibleFrame: frame
        )
        XCTAssertLessThan(result.y, iconOrigin.y)
    }
}
