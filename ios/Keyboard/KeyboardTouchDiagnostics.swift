#if DEBUG
    import OSLog
    import UIKit

    /// Debug-only timing for real-device typing tests. Records only screen zones and durations,
    /// never characters, words or key titles. Read it in Console with the subsystem below.
    @MainActor
    final class KeyboardTouchDiagnostics {
        static let shared = KeyboardTouchDiagnostics()
        private static let subsystem = "one.binda.flype.keyboard"
        private let logger = Logger(subsystem: subsystem, category: "touch")
        private let signposter = OSSignposter(subsystem: subsystem, category: "work")

        private enum Zone: String, CaseIterable {
            case left, center, right, bottom
        }
        private let edgeWidth: CGFloat = 44
        private let bottomHeight: CGFloat = 50
        private let summaryInterval = 50

        private var delays: [Zone: [Double]] = [:]
        private var previewDelays: [Zone: [Double]] = [:]
        private var work: [String: [Double]] = [:]
        private var marginHits = 0
        private var sameKeyHits = 0
        private var cancelled = 0
        private var coalesced = 0
        private var touches = 0
        private var lastMarginEvent: TimeInterval?
        private var lastSameKeyEvent: TimeInterval?

        private func zone(of touch: UITouch) -> Zone? {
            guard let window = touch.window else { return nil }
            let point = touch.location(in: window)
            if point.y > window.bounds.maxY - bottomHeight { return .bottom }
            if point.x < edgeWidth { return .left }
            if point.x > window.bounds.maxX - edgeWidth { return .right }
            return .center
        }

        /// How long after the hardware event the key view got the touch.
        func touchBegan(_ touch: UITouch) {
            guard let zone = zone(of: touch) else { return }
            // The touch keeps its hardware time when the system holds back its delivery.
            delays[zone, default: []].append((ProcessInfo.processInfo.systemUptime - touch.timestamp) * 1000)
            touches += 1
            if touches % summaryInterval == 0 { logSummary() }
        }

        /// How long after the hardware event the preview gesture got the touch.
        func previewBegan(_ touch: UITouch) {
            guard let zone = zone(of: touch) else { return }
            previewDelays[zone, default: []].append((ProcessInfo.processInfo.systemUptime - touch.timestamp) * 1000)
        }

        func touchEnded(pressDuration: TimeInterval) {
            // Press and release within one 60 Hz frame cannot show a highlight.
            if pressDuration < 1.0 / 60 { coalesced += 1 }
        }

        func touchCancelled() { cancelled += 1 }

        func marginHit(_ event: UIEvent?) {
            // UIKit can hit-test one touch several times.
            guard event?.timestamp != lastMarginEvent || event == nil else { return }
            lastMarginEvent = event?.timestamp
            marginHits += 1
        }

        func sameKeyHit(_ event: UIEvent?) {
            guard event?.timestamp != lastSameKeyEvent || event == nil else { return }
            lastSameKeyEvent = event?.timestamp
            sameKeyHits += 1
        }

        /// Visible in Instruments as a signpost interval; the duration also enters the summary.
        func measure<T>(_ name: StaticString, _ action: () throws -> T) rethrows -> T {
            let state = signposter.beginInterval(name)
            let start = ProcessInfo.processInfo.systemUptime
            defer {
                signposter.endInterval(name, state)
                work["\(name)", default: []].append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            }
            return try action()
        }

        func record(_ name: String, milliseconds: Double) { work[name, default: []].append(milliseconds) }

        /// Reports which recognizers hold touches back; it does not change them.
        func logSystemGestures(from view: UIView) {
            var found: [String] = []
            var node = view.superview
            while let current = node {
                for recognizer in current.gestureRecognizers ?? [] where recognizer.delaysTouchesBegan {
                    found.append("\(type(of: recognizer))@\(type(of: current))")
                }
                node = current.superview
            }
            logger.notice("delaying recognizers: \(found.joined(separator: ", "), privacy: .public)")
        }

        func logSummary() {
            guard touches > 0 else { return }
            for zone in Zone.allCases {
                guard let values = delays[zone], !values.isEmpty else { continue }
                logger.notice(
                    "delay \(zone.rawValue, privacy: .public): \(Self.describe(values), privacy: .public)")
            }
            for zone in Zone.allCases {
                guard let values = previewDelays[zone], !values.isEmpty else { continue }
                logger.notice(
                    "preview \(zone.rawValue, privacy: .public): \(Self.describe(values), privacy: .public)")
            }
            for (name, values) in work.sorted(by: { $0.key < $1.key }) {
                logger.notice("work \(name, privacy: .public): \(Self.describe(values), privacy: .public)")
            }
            logger.notice(
                "touches=\(self.touches) marginHits=\(self.marginHits) sameKeyHits=\(self.sameKeyHits) cancelled=\(self.cancelled) coalesced=\(self.coalesced)"
            )
        }

        private static func describe(_ values: [Double]) -> String {
            let sorted = values.sorted()
            func percentile(_ fraction: Double) -> Double { sorted[Int(Double(sorted.count - 1) * fraction)] }
            return String(
                format: "n=%d p50=%.1fms p95=%.1fms max=%.1fms", sorted.count, percentile(0.5), percentile(0.95),
                sorted[sorted.count - 1])
        }
    }
#endif
