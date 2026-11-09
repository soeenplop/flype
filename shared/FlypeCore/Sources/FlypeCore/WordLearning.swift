import Darwin
import Foundation

/// When an unknown word joins the personal dictionary, and the counts that get it there.
public enum WordLearning {
    /// The same correction of a swiped word, as with geht to geht's.
    public static let correctionsNeeded = 2
    /// The same unknown word typed letter by letter.
    public static let typingsNeeded = 3
    /// Counts that do not reach the threshold expire.
    public static let keepDays = 30.0
    static let maximumCandidates = 500

    /// The word to count, or nil if this does not look like a word. Numbers and symbols can be private data.
    public static func learnable(_ text: String, startsSentence: Bool) -> String? {
        let word = text.precomposedStringWithCanonicalMapping
        guard word.count >= 2, word.count <= 32, word.allSatisfy(SwipeCorrection.isWordCharacter),
            word.first?.isLetter == true
        else { return nil }
        // A capital that is only there because a sentence starts is not part of the word.
        let rest = word.dropFirst()
        if startsSentence, !rest.contains(where: \.isUppercase) { return word.prefix(1).lowercased() + rest }
        return word
    }
}

/// Counts unknown words on this device until they qualify. It never leaves the device and is not synced.
public final class WordLearningStore: @unchecked Sendable {
    public enum Source: Sendable { case correction, typing }

    public struct Counts: Equatable, Sendable {
        public var corrections = 0
        public var typings = 0
        public init(corrections: Int = 0, typings: Int = 0) {
            self.corrections = corrections
            self.typings = typings
        }
    }

    struct Candidate: Codable, Equatable {
        var word: String
        var corrections: Int
        var typings: Int
        var lastSeen: Date
    }

    public let directory: URL
    var fileURL: URL { directory.appendingPathComponent("candidates.json") }

    public init(directory: URL) { self.directory = directory }

    public static func shared() throws -> WordLearningStore {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ResultStore.appGroup)
        else { throw PersonalDictionaryStore.Failure.unavailable }
        return WordLearningStore(directory: url.appendingPathComponent("Learning", isDirectory: true))
    }

    /// Counts the word once more and returns its counts so far.
    @discardableResult
    public func record(_ word: String, as source: Source, now: Date = Date()) throws -> Counts {
        try locked {
            var candidates = prune(try read(), now: now)
            var candidate =
                candidates.first { $0.word == word } ?? Candidate(word: word, corrections: 0, typings: 0, lastSeen: now)
            switch source {
            case .correction: candidate.corrections += 1
            case .typing: candidate.typings += 1
            }
            candidate.lastSeen = now
            candidates.removeAll { $0.word == word }
            candidates.append(candidate)
            if candidates.count > WordLearning.maximumCandidates {
                candidates = Array(
                    candidates.sorted { $0.lastSeen > $1.lastSeen }.prefix(WordLearning.maximumCandidates))
            }
            try write(candidates)
            return Counts(corrections: candidate.corrections, typings: candidate.typings)
        }
    }

    public func remove(_ word: String) throws {
        try locked {
            var candidates = try read()
            candidates.removeAll { $0.word == word }
            try write(candidates)
        }
    }

    public func clear() throws {
        try locked {
            if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
        }
    }

    public func count(now: Date = Date()) throws -> Int { try locked { prune(try read(), now: now).count } }

    private func prune(_ candidates: [Candidate], now: Date) -> [Candidate] {
        candidates.filter { now.timeIntervalSince($0.lastSeen) < WordLearning.keepDays * 86_400 }
    }

    private func read() throws -> [Candidate] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        // A damaged file only loses counts, so start over instead of failing every keystroke.
        return (try? JSONDecoder().decode([Candidate].self, from: Data(contentsOf: fileURL))) ?? []
    }

    private func write(_ candidates: [Candidate]) throws {
        let data = try JSONEncoder().encode(candidates)
        #if os(iOS)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        #else
            try data.write(to: fileURL, options: .atomic)
        #endif
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(directory.appendingPathComponent("store.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw PersonalDictionaryStore.Failure.unavailable }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw PersonalDictionaryStore.Failure.unavailable }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}
