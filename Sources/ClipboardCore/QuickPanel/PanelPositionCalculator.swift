import AppKit

/// Pure geometry helper for panel positioning.
/// All methods are stateless and depend only on their arguments,
/// making them straightforward to unit-test without UI infrastructure.
public enum PanelPositionCalculator {

    /// Returns the origin that centers the panel within `visibleFrame`,
    /// offset upward by 80 pt so it clears the Dock on typical displays.
    public static func centerOrigin(panelSize: CGSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.midY - panelSize.height / 2 + 80
        )
    }

    /// Returns an origin that places the panel under the current mouse cursor,
    /// clamped so the panel stays fully inside `visibleFrame`.
    public static func followMouseOrigin(panelSize: CGSize, visibleFrame: NSRect) -> NSPoint {
        let mouseLocation = NSEvent.mouseLocation
        let raw = NSPoint(
            x: mouseLocation.x - panelSize.width / 2,
            y: mouseLocation.y - panelSize.height / 2
        )
        return clampToVisible(origin: raw, panelSize: panelSize, visibleFrame: visibleFrame)
    }

    /// Returns an origin that drops the panel directly below a status-bar icon,
    /// clamped so the panel stays fully inside `visibleFrame`.
    /// - Parameters:
    ///   - iconOrigin: The bottom-left corner of the status-bar icon in screen coordinates.
    public static func statusBarClickOrigin(
        iconOrigin: NSPoint, panelSize: CGSize, visibleFrame: NSRect
    ) -> NSPoint {
        let gap: CGFloat = 5
        let raw = NSPoint(
            x: iconOrigin.x - panelSize.width / 2,
            y: iconOrigin.y - panelSize.height - gap
        )
        return clampToVisible(origin: raw, panelSize: panelSize, visibleFrame: visibleFrame)
    }

    /// Clamps `origin` so that a rectangle of `panelSize` placed at `origin`
    /// fits entirely within `visibleFrame`.
    public static func clampToVisible(
        origin: NSPoint, panelSize: CGSize, visibleFrame: NSRect
    ) -> NSPoint {
        let clampedX = max(visibleFrame.minX,
                           min(origin.x, visibleFrame.maxX - panelSize.width))
        let clampedY = max(visibleFrame.minY,
                           min(origin.y, visibleFrame.maxY - panelSize.height))
        return NSPoint(x: clampedX, y: clampedY)
    }

    /// Returns the NSScreen that currently contains the mouse pointer.
    /// Falls back to the main screen. Returns nil only when no screens are available,
    /// which callers must handle gracefully rather than force-unwrapping.
    public static func mouseScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
    }
}
