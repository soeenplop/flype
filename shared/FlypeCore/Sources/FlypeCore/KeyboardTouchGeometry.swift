import CoreGraphics
import Foundation

/// Assign the visual gaps to the nearest key without extending beyond the keyboard.
public enum KeyboardTouchGeometry {
    /// The keys own the keyboard's outer margins, up to whatever sits above them.
    public static func touchArea(container: CGRect, topLimit: CGFloat?) -> CGRect {
        let top = max(container.minY, topLimit ?? container.minY)
        return CGRect(x: container.minX, y: top, width: container.width, height: max(0, container.maxY - top))
    }

    public static func nearest(to point: CGPoint, frames: [CGRect], within bounds: CGRect) -> Int? {
        guard point.x.isFinite, point.y.isFinite, bounds.contains(point) else { return nil }
        var best: (index: Int, edge: CGFloat, center: CGFloat)?
        for (index, frame) in frames.enumerated() {
            guard !frame.isEmpty, !frame.isNull, !frame.isInfinite else { continue }
            let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
            let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
            let edge = dx * dx + dy * dy
            let center = pow(frame.midX - point.x, 2) + pow(frame.midY - point.y, 2)
            if best == nil || edge < best!.edge || (edge == best!.edge && center < best!.center) {
                best = (index, edge, center)
            }
        }
        return best?.index
    }
}
