import Foundation

/// Reads an AOSP `.combined` word list in place, so a large file stays out of the keyboard's memory budget.
/// The file is sorted by descending frequency, which lets the scan stop at the first word below the minimum.
/// Only positions are kept: words are read from the mapped bytes when they are needed.
public struct CombinedWordList: Sendable {
    struct Entry: Sendable {
        let offset: UInt32
        let length: UInt8
        let frequency: UInt8
    }

    private static let wordMarker = Array(" word=".utf8)
    private static let bigramMarker = Array("  bigram=".utf8)
    private static let newline = UInt8(ascii: "\n")
    private static let comma = UInt8(ascii: ",")
    private static let maximumWordBytes = 48

    private let data: Data
    /// Grouped by lowercase first letter. Each group keeps the file's descending frequency order.
    let groups: [UInt32: [Entry]]
    public let count: Int

    public init(data: Data, minimumFrequency: UInt8 = 30) {
        self.data = data
        let groups = data.withUnsafeBytes { Self.scan($0, minimumFrequency: minimumFrequency) }
        self.groups = groups
        count = groups.values.reduce(0) { $0 + $1.count }
    }

    func word(_ entry: Entry) -> String {
        data.withUnsafeBytes { bytes in
            let start = Int(entry.offset)
            return String(decoding: bytes[start..<start + Int(entry.length)], as: UTF8.self)
        }
    }

    func withBytes<Result>(_ body: (UnsafeRawBufferPointer) -> Result) -> Result {
        data.withUnsafeBytes(body)
    }

    /// The words the list expects after `word`, lowercase, with their stored strength. Ignores the case of `word`.
    func nextWords(after word: String) -> [String: Int] {
        let lower = word.lowercased()
        guard let first = lower.unicodeScalars.first, let group = groups[first.value] else { return [:] }
        let capitalized = lower.prefix(1).uppercased() + lower.dropFirst()
        let variants = [Array(lower.utf8), Array(capitalized.utf8)]
        return data.withUnsafeBytes { bytes in
            let match = group.first { entry in
                let start = Int(entry.offset)
                let slice = bytes[start..<start + Int(entry.length)]
                return variants.contains { $0.elementsEqual(slice) }
            }
            guard let match else { return [:] }
            return Self.readNextWords(bytes, after: Int(match.offset) + Int(match.length))
        }
    }

    private static func readNextWords(_ bytes: UnsafeRawBufferPointer, after position: Int) -> [String: Int] {
        var result: [String: Int] = [:]
        var lineStart = lineEnd(bytes, from: position) + 1
        while lineStart < bytes.count, hasPrefix(bytes, at: lineStart, bigramMarker) {
            let end = lineEnd(bytes, from: lineStart)
            let wordStart = lineStart + bigramMarker.count
            if let separator = find(comma, in: bytes, from: wordStart, to: end),
                let strength = frequency(bytes, at: separator + 1, end: end)
            {
                let word = String(decoding: bytes[wordStart..<separator], as: UTF8.self)
                result[word.lowercased()] = Int(strength.value)
            }
            lineStart = end + 1
        }
        return result
    }

    private static func scan(_ bytes: UnsafeRawBufferPointer, minimumFrequency: UInt8) -> [UInt32: [Entry]] {
        var groups: [UInt32: [Entry]] = [:]
        var lineStart = 0
        while lineStart < bytes.count {
            let end = lineEnd(bytes, from: lineStart)
            defer { lineStart = end + 1 }
            guard hasPrefix(bytes, at: lineStart, wordMarker) else { continue }
            let wordStart = lineStart + wordMarker.count
            guard let separator = find(comma, in: bytes, from: wordStart, to: end),
                let parsed = frequency(bytes, at: separator + 1, end: end)
            else { continue }
            if parsed.value < minimumFrequency { break }
            // Anything after the frequency marks the word as offensive or as not being a word.
            let length = separator - wordStart
            guard parsed.end == end, length >= 2, length <= maximumWordBytes,
                isLetters(bytes, from: wordStart, to: separator),
                let first = lowercaseFirstScalar(bytes, from: wordStart, to: separator),
                wordStart <= Int(UInt32.max)
            else { continue }
            groups[first, default: []].append(
                Entry(offset: UInt32(wordStart), length: UInt8(length), frequency: parsed.value))
        }
        return groups
    }

    /// Swiping cannot produce digits, periods or hyphens. Apostrophes stay, as in c'est or auto's.
    private static func isLetters(_ bytes: UnsafeRawBufferPointer, from start: Int, to end: Int) -> Bool {
        for index in start..<end {
            let byte = bytes[index]
            let asciiLetter = (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
            guard asciiLetter || byte >= 0x80 || (byte == 0x27 && index > start) else { return false }
        }
        return true
    }

    private static func lowercaseFirstScalar(_ bytes: UnsafeRawBufferPointer, from start: Int, to end: Int) -> UInt32? {
        let byte = bytes[start]
        if byte < 0x80 { return UInt32(byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte) }
        let scalar = String(decoding: bytes[start..<min(start + 4, end)], as: UTF8.self).unicodeScalars.first
        return scalar.flatMap { Character($0).lowercased().unicodeScalars.first?.value }
    }

    private static func frequency(
        _ bytes: UnsafeRawBufferPointer, at start: Int, end: Int
    ) -> (value: UInt8, end: Int)? {
        guard start + 2 < end, bytes[start] == UInt8(ascii: "f"), bytes[start + 1] == UInt8(ascii: "=") else {
            return nil
        }
        var position = start + 2
        var value = 0
        while position < end, bytes[position] >= 0x30, bytes[position] <= 0x39, value <= 255 {
            value = value * 10 + Int(bytes[position] - 0x30)
            position += 1
        }
        guard position > start + 2, value <= 255 else { return nil }
        return (UInt8(value), position)
    }

    private static func lineEnd(_ bytes: UnsafeRawBufferPointer, from start: Int) -> Int {
        find(newline, in: bytes, from: start, to: bytes.count) ?? bytes.count
    }

    private static func find(_ byte: UInt8, in bytes: UnsafeRawBufferPointer, from start: Int, to end: Int) -> Int? {
        guard start < end, let base = bytes.baseAddress else { return nil }
        guard let found = memchr(base + start, Int32(byte), end - start) else { return nil }
        return UnsafeRawPointer(found) - base
    }

    private static func hasPrefix(_ bytes: UnsafeRawBufferPointer, at start: Int, _ prefix: [UInt8]) -> Bool {
        guard start + prefix.count <= bytes.count else { return false }
        for index in prefix.indices where bytes[start + index] != prefix[index] { return false }
        return true
    }
}
