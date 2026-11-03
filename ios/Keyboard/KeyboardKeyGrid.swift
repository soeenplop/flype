import FlypeCore
import UIKit

/// Routes touches in the margins around the key grid to the nearest key.
/// Everything else keeps the normal view hierarchy, including the suggestion bar and recording view.
final class KeyboardInputView: UIInputView {
    weak var keyGrid: KeyboardKeyGrid?
    weak var suggestionBar: UIView?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        marginTarget(at: point, with: event) ?? super.hitTest(point, with: event)
    }

    private func marginTarget(at point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, let grid = keyGrid, let parent = grid.superview,
            !grid.isHidden, !parent.isHidden, bounds.contains(point),
            !grid.convert(grid.bounds, to: self).contains(point)
        else { return nil }
        let bar = suggestionBar.flatMap { $0.isHidden ? nil : $0.convert($0.bounds, to: self) }
        let area = KeyboardTouchGeometry.touchArea(container: bounds, topLimit: bar?.maxY)
        guard area.contains(point) else { return nil }
        let target = grid.touchTarget(
            at: convert(point, to: grid), within: convert(area, to: grid), with: event)
        #if DEBUG
            if target != nil { KeyboardTouchDiagnostics.shared.marginHit(event) }
        #endif
        return target
    }
}

/// Visual spacing stays native; the touch targets fill the spaces between keys.
final class KeyboardKeyGrid: UIStackView {
    static let hostedKeyTag = 8107

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }
        guard let target = nearestTarget(at: point, within: bounds) else {
            return super.hitTest(point, with: event)
        }
        return resolve(target, at: point, with: event)
    }

    /// Hit testing for a point in the margins around the grid, in this view's coordinates.
    func touchTarget(at point: CGPoint, within area: CGRect, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, alpha > 0.01, let target = nearestTarget(at: point, within: area) else {
            return nil
        }
        return resolve(target, at: point, with: event)
    }

    private func resolve(_ target: UIView, at point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let key = target as? KeyboardKeyButton else {
            // Resolve inside the selected host, never through the entire grid again:
            // a neighboring key's expanded point(inside:) can otherwise swallow the Link.
            // Returning the SwiftUI descendant preserves its gestures and open-URL handling.
            return target.hitTest(target.convert(point, from: self), with: event)
        }
        #if DEBUG
            if key.isTracking { KeyboardTouchDiagnostics.shared.sameKeyHit(event) }
        #endif
        return key
    }

    private func nearestTarget(at point: CGPoint, within area: CGRect) -> UIView? {
        let keyRows = arrangedSubviews.compactMap { $0 as? UIStackView }.filter { !$0.isHidden }
        let rowFrames = keyRows.map { CGRect(x: 0, y: $0.frame.minY, width: bounds.width, height: $0.frame.height) }
        guard let rowIndex = KeyboardTouchGeometry.nearest(to: point, frames: rowFrames, within: area) else {
            return nil
        }
        let row = keyRows[rowIndex]
        let targets = row.arrangedSubviews.filter {
            !$0.isHidden && $0.alpha > 0.01 && $0.isUserInteractionEnabled
                && ($0 is UIControl || $0.tag == Self.hostedKeyTag)
        }
        let frames = targets.map { $0.convert($0.bounds, to: self) }
        guard let index = KeyboardTouchGeometry.nearest(to: point, frames: frames, within: area) else {
            return nil
        }
        if let key = targets[index] as? KeyboardKeyButton {
            let left = index == 0 ? area.minX : (frames[index - 1].maxX + frames[index].minX) / 2
            let right = index == frames.count - 1 ? area.maxX : (frames[index].maxX + frames[index + 1].minX) / 2
            let top = rowIndex == 0 ? area.minY : (rowFrames[rowIndex - 1].maxY + rowFrames[rowIndex].minY) / 2
            let bottom =
                rowIndex == rowFrames.count - 1
                ? area.maxY : (rowFrames[rowIndex].maxY + rowFrames[rowIndex + 1].minY) / 2
            key.touchRegion = key.convert(
                CGRect(x: left, y: top, width: right - left, height: bottom - top), from: self)
        }
        return targets[index]
    }
}
