import CoreGraphics
import Foundation

/// Where each letter sits on screen, in the same coordinates as the finger's path.
public struct SwipeKeyLayout: Equatable, Sendable {
    public let keys: [String: CGPoint]
    /// Distance between the centers of two neighboring keys.
    public let keyPitch: Double

    public init(keys: [String: CGPoint], keyPitch: Double) {
        self.keys = keys
        self.keyPitch = keyPitch
    }
}

public enum SwipeCasing: Sendable {
    case asListed, capitalized, allCaps
}

/// Compares the finger's path with the ideal path of each plausible word, then weighs in how common the word is.
public enum SwipeDecoder {
    private static let sampleCount = 40
    private static let shortlistSize = 24
    /// How far from a key the path may pass while still counting as having touched it, in key pitches.
    private static let passRadius = 1.4
    private static let endRadius = 1.6

    struct Weights: Sendable {
        var shape = 8.0
        var pass = 1.0
        var frequency = 0.02
        var nextWord = 0.6
        /// Abbreviations such as FDP are common in the list's news texts, but rarely what someone swipes.
        var innerCapital = 1.0
    }

    /// Personal words have no frequency. This puts them level with common words, so a matching path finds them.
    private static let personalFrequency = 150.0

    private enum Source {
        case listed(CombinedWordList.Entry)
        case personal(String)
    }

    private struct Candidate {
        let source: Source
        let score: Double
    }

    public static func candidates(
        path: [CGPoint], layout: SwipeKeyLayout, list: CombinedWordList, personalWords: [String] = [],
        previousWord: String? = nil, casing: SwipeCasing = .asListed, limit: Int = 3
    ) -> [String] {
        rank(
            path: path, layout: layout, list: list, personalWords: personalWords, previousWord: previousWord,
            casing: casing, limit: limit, weights: Weights())
    }

    /// Whether someone could have meant this word with this path, whatever its frequency.
    public static func fits(_ word: String, path: [CGPoint], layout: SwipeKeyLayout) -> Bool {
        guard path.count >= 2, layout.keyPitch > 0, path.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            return false
        }
        var map = KeyMap(layout)
        let (pathX, pathY) = resample(path)
        let startKeys = map.keys(near: pathX[0], pathY[0], within: endRadius * layout.keyPitch)
        let endKeys = map.keys(
            near: pathX[sampleCount - 1], pathY[sampleCount - 1], within: endRadius * layout.keyPitch)
        var keys = [Int](repeating: 0, count: 64)
        var costs = [Double](repeating: 0, count: sampleCount)
        let bytes = Array(word.utf8)
        return bytes.withUnsafeBytes { raw in
            guard let length = map.decode(raw, from: 0, to: raw.count, into: &keys), startKeys[keys[0]],
                endKeys[keys[length - 1]]
            else { return false }
            return passCost(keys, length, map, pathX, pathY, radius: passRadius * layout.keyPitch, costs: &costs) != nil
        }
    }

    static func rank(
        path: [CGPoint], layout: SwipeKeyLayout, list: CombinedWordList, personalWords: [String] = [],
        previousWord: String?, casing: SwipeCasing, limit: Int, weights: Weights
    ) -> [String] {
        guard path.count >= 2, limit > 0, layout.keyPitch > 0, path.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
        else { return [] }
        var map = KeyMap(layout)
        let (pathX, pathY) = resample(path)
        let pitch = layout.keyPitch
        let startKeys = map.keys(near: pathX[0], pathY[0], within: endRadius * pitch)
        let endKeys = map.keys(near: pathX[sampleCount - 1], pathY[sampleCount - 1], within: endRadius * pitch)
        guard startKeys.contains(true), endKeys.contains(true) else { return [] }

        var shortlist: [Candidate] = []
        shortlist.reserveCapacity(shortlistSize + 1)
        var word = [Int](repeating: 0, count: 64)
        var ideal = (x: [Double](repeating: 0, count: 64), y: [Double](repeating: 0, count: 64))
        var passCosts = [Double](repeating: 0, count: sampleCount)

        func score(length: Int, frequency: Double, innerCapital: Bool) -> Double? {
            guard endKeys[word[length - 1]],
                let pass = passCost(word, length, map, pathX, pathY, radius: passRadius * pitch, costs: &passCosts)
            else { return nil }
            for index in 0..<length {
                ideal.x[index] = map.x[word[index]]
                ideal.y[index] = map.y[word[index]]
            }
            let shape = shapeCost(pathX, pathY, ideal.x, ideal.y, length, pitch: pitch)
            let capital = innerCapital ? weights.innerCapital : 0
            return weights.frequency * frequency - weights.shape * shape - weights.pass * pass / (pitch * pitch)
                - capital
        }
        func keep(_ source: Source, score: Double) {
            if shortlist.count == shortlistSize, let worst = shortlist.last, score <= worst.score { return }
            let position = shortlist.firstIndex { $0.score < score } ?? shortlist.count
            shortlist.insert(Candidate(source: source, score: score), at: position)
            if shortlist.count > shortlistSize { shortlist.removeLast() }
        }

        list.withBytes { bytes in
            for (first, group) in list.groups {
                guard let firstKey = map.key(forScalarValue: first), startKeys[firstKey] else { continue }
                for entry in group {
                    let best = weights.frequency * Double(entry.frequency)
                    if shortlist.count == shortlistSize, let worst = shortlist.last, best <= worst.score { break }
                    let start = Int(entry.offset)
                    guard let length = map.decode(bytes, from: start, to: start + Int(entry.length), into: &word),
                        let value = score(
                            length: length, frequency: Double(entry.frequency),
                            innerCapital: hasInnerCapital(entry, in: bytes))
                    else { continue }
                    keep(.listed(entry), score: value)
                }
            }
        }
        for personal in personalWords {
            let bytes = Array(personal.utf8)
            let length = bytes.withUnsafeBytes { map.decode($0, from: 0, to: $0.count, into: &word) }
            guard let length, startKeys[word[0]],
                let value = score(length: length, frequency: personalFrequency, innerCapital: false)
            else { continue }
            keep(.personal(personal), score: value)
        }
        return finish(
            shortlist, list: list, previousWord: previousWord, casing: casing, limit: limit,
            nextWordWeight: weights.nextWord)
    }

    private static func finish(
        _ shortlist: [Candidate], list: CombinedWordList, previousWord: String?, casing: SwipeCasing, limit: Int,
        nextWordWeight: Double
    ) -> [String] {
        let expected = previousWord.map { list.nextWords(after: $0) } ?? [:]
        let ranked =
            shortlist.map { candidate -> (word: String, score: Double) in
                let word: String
                switch candidate.source {
                case .listed(let entry): word = list.word(entry)
                case .personal(let value): word = value
                }
                let bonus = expected[word.lowercased()].map { _ in nextWordWeight } ?? 0
                return (word, candidate.score + bonus)
            }
            .sorted { $0.score > $1.score }
        var words: [String] = []
        for candidate in ranked {
            let value = apply(casing, to: candidate.word)
            if !words.contains(value) { words.append(value) }
            if words.count == limit { break }
        }
        return words
    }

    private static func polylineLength(_ xs: [Double], _ ys: [Double], _ count: Int) -> Double {
        var total = 0.0
        for index in 1..<max(count, 1) { total += hypot(xs[index] - xs[index - 1], ys[index] - ys[index - 1]) }
        return total
    }

    private static func hasInnerCapital(_ entry: CombinedWordList.Entry, in bytes: UnsafeRawBufferPointer) -> Bool {
        let start = Int(entry.offset)
        for index in (start + 1)..<(start + Int(entry.length)) where bytes[index] >= 0x41 && bytes[index] <= 0x5A {
            return true
        }
        return false
    }

    private static func apply(_ casing: SwipeCasing, to word: String) -> String {
        switch casing {
        case .asListed: word
        case .capitalized: word.prefix(1).uppercased() + word.dropFirst()
        case .allCaps: word.uppercased()
        }
    }

    /// Finds the best way to pass the letters in order, and returns the mean squared miss. Returns nil if a letter is
    /// out of reach. Taking the first approach to each key would hang on keys the finger merely passes on its way.
    private static func passCost(
        _ word: [Int], _ length: Int, _ map: KeyMap, _ pathX: [Double], _ pathY: [Double], radius: Double,
        costs: inout [Double]
    ) -> Double? {
        let limit = radius * radius
        for sample in 0..<sampleCount { costs[sample] = 0 }
        for index in 0..<length {
            let keyX = map.x[word[index]]
            let keyY = map.y[word[index]]
            var bestEarlier = Double.infinity
            var reachable = false
            for sample in 0..<sampleCount {
                bestEarlier = min(bestEarlier, costs[sample])
                let distance = squared(pathX[sample] - keyX, pathY[sample] - keyY)
                let usable = distance <= limit && bestEarlier.isFinite
                costs[sample] = usable ? bestEarlier + distance : .infinity
                reachable = reachable || usable
            }
            if !reachable { return nil }
        }
        return (costs.min() ?? .infinity) / Double(length)
    }

    /// Mean squared distance between equally spaced points on the path and on the word's ideal path, in key pitches.
    private static func shapeCost(
        _ pathX: [Double], _ pathY: [Double], _ idealX: [Double], _ idealY: [Double], _ length: Int, pitch: Double
    ) -> Double {
        let step = polylineLength(idealX, idealY, length) / Double(sampleCount - 1)
        var segment = 0
        var walked = 0.0
        var total = 0.0
        for sample in 0..<sampleCount {
            let target = step * Double(sample)
            var x = idealX[0]
            var y = idealY[0]
            while segment + 1 < length {
                let piece = hypot(idealX[segment + 1] - idealX[segment], idealY[segment + 1] - idealY[segment])
                if walked + piece >= target || segment + 2 == length {
                    let ratio = piece > 0 ? min(1, (target - walked) / piece) : 0
                    x = idealX[segment] + (idealX[segment + 1] - idealX[segment]) * ratio
                    y = idealY[segment] + (idealY[segment + 1] - idealY[segment]) * ratio
                    break
                }
                walked += piece
                segment += 1
            }
            total += squared(pathX[sample] - x, pathY[sample] - y)
        }
        return total / Double(sampleCount) / (pitch * pitch)
    }

    /// Equally spaced points along the path, so a slow stretch does not count for more than a fast one.
    private static func resample(_ path: [CGPoint]) -> (x: [Double], y: [Double]) {
        let xs = path.map { Double($0.x) }
        let ys = path.map { Double($0.y) }
        var totalLength = 0.0
        for index in 1..<xs.count { totalLength += hypot(xs[index] - xs[index - 1], ys[index] - ys[index - 1]) }
        guard totalLength > 0 else {
            return ([Double](repeating: xs[0], count: sampleCount), [Double](repeating: ys[0], count: sampleCount))
        }
        let step = totalLength / Double(sampleCount - 1)
        var resultX = [Double]()
        var resultY = [Double]()
        resultX.reserveCapacity(sampleCount)
        resultY.reserveCapacity(sampleCount)
        var segment = 1
        var walked = 0.0
        for sample in 0..<sampleCount {
            let target = step * Double(sample)
            while segment < xs.count - 1 {
                let piece = hypot(xs[segment] - xs[segment - 1], ys[segment] - ys[segment - 1])
                if walked + piece >= target { break }
                walked += piece
                segment += 1
            }
            let piece = hypot(xs[segment] - xs[segment - 1], ys[segment] - ys[segment - 1])
            let ratio = piece > 0 ? min(1, max(0, (target - walked) / piece)) : 0
            resultX.append(xs[segment - 1] + (xs[segment] - xs[segment - 1]) * ratio)
            resultY.append(ys[segment - 1] + (ys[segment] - ys[segment - 1]) * ratio)
        }
        return (resultX, resultY)
    }

    private static func squared(_ x: Double, _ y: Double) -> Double { x * x + y * y }

    /// Resolves letters to keys without creating strings, since it runs for tens of thousands of words per swipe.
    private struct KeyMap {
        var x: [Double] = []
        var y: [Double] = []
        private var ascii = [Int](repeating: -1, count: 128)
        private var other: [UInt32: Int] = [:]
        private var byLetter: [String: Int] = [:]

        init(_ layout: SwipeKeyLayout) {
            for (letter, center) in layout.keys.sorted(by: { $0.key < $1.key }) {
                let lower = letter.lowercased()
                byLetter[lower] = x.count
                x.append(Double(center.x))
                y.append(Double(center.y))
            }
            for value in UInt32(0)..<128 {
                guard let scalar = Unicode.Scalar(value) else { continue }
                ascii[Int(value)] = resolve(scalar) ?? -1
            }
        }

        private func resolve(_ scalar: Unicode.Scalar) -> Int? {
            let lower = Character(scalar).lowercased()
            if let key = byLetter[lower] { return key }
            // These have no canonical base letter, but the keyboard offers them on the same key.
            if let base = ["ß": "s", "œ": "o", "æ": "a", "ø": "o"][lower] { return byLetter[base] }
            // Letters without their own key are typed through their base letter, such as é through e.
            let base = lower.decomposedStringWithCanonicalMapping.unicodeScalars.first.map(String.init)
            return base.flatMap { byLetter[$0] }
        }

        mutating func key(forScalarValue value: UInt32) -> Int? {
            if value < 128 {
                let key = ascii[Int(value)]
                return key >= 0 ? key : nil
            }
            if let known = other[value] { return known >= 0 ? known : nil }
            let key = Unicode.Scalar(value).flatMap(resolve)
            other[value] = key ?? -1
            return key
        }

        func keys(near pointX: Double, _ pointY: Double, within radius: Double) -> [Bool] {
            x.indices.map { hypot(x[$0] - pointX, y[$0] - pointY) <= radius }
        }

        /// Writes the word's keys with repeats collapsed, since a double letter does not move the finger.
        mutating func decode(
            _ bytes: UnsafeRawBufferPointer, from start: Int, to end: Int, into word: inout [Int]
        ) -> Int? {
            var position = start
            var length = 0
            while position < end {
                let byte = bytes[position]
                var value = UInt32(byte)
                var size = 1
                if byte >= 0xF0 {
                    size = 4
                    value &= 0x07
                } else if byte >= 0xE0 {
                    size = 3
                    value &= 0x0F
                } else if byte >= 0xC0 {
                    size = 2
                    value &= 0x1F
                }
                guard position + size <= end else { return nil }
                if size > 1 {
                    for offset in 1..<size { value = value << 6 | UInt32(bytes[position + offset] & 0x3F) }
                }
                position += size
                // A swipe cannot reach the apostrophe in c'est or auto's, so it does not count.
                if value == 0x27 || value == 0x2019 { continue }
                guard let key = key(forScalarValue: value) else { return nil }
                if length == 0 || word[length - 1] != key {
                    guard length < word.count else { return nil }
                    word[length] = key
                    length += 1
                }
            }
            // A swipe always travels, so a word on a single key can never be what was meant.
            return length >= 2 ? length : nil
        }
    }
}
