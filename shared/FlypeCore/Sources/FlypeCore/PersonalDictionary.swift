import Darwin
import Foundation

public struct PersonalDictionaryEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var spelling: String
    public var aliases: [String]
    public var enabled: Bool
    public var useForTyping: Bool
    public var useForDictation: Bool
    public var replaceAliases: Bool
    public init(
        id: UUID = UUID(), spelling: String, aliases: [String] = [], enabled: Bool = true,
        useForTyping: Bool = true, useForDictation: Bool = true, replaceAliases: Bool = false
    ) {
        self.id = id
        self.spelling = spelling
        self.aliases = aliases
        self.enabled = enabled
        self.useForTyping = useForTyping
        self.useForDictation = useForDictation
        self.replaceAliases = replaceAliases
    }
}

public struct DictionarySnapshot: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var revision = UUID()
    public var entries: [PersonalDictionaryEntry] = []
    public init(entries: [PersonalDictionaryEntry] = []) { self.entries = entries }
    public func completions(prefix: String) -> [String] {
        guard !prefix.isEmpty else { return [] }
        let key = prefix.precomposedStringWithCanonicalMapping.lowercased()
        return entries.filter {
            $0.enabled && $0.useForTyping && !$0.spelling.contains(where: \.isWhitespace)
                && $0.spelling.lowercased().hasPrefix(key)
        }
        .map(\.spelling).sorted { a, b in
            if a.count != b.count { return a.count < b.count }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }
    /// Explicit aliases only. One pass over the original input prevents cascading replacements.
    public func applyingAliases(to text: String) -> String {
        let text = text.precomposedStringWithCanonicalMapping
        let rules = entries.filter { $0.enabled && $0.useForDictation && $0.replaceAliases }
            .flatMap { entry in entry.aliases.map { ($0, entry.spelling) } }
            .sorted { $0.0.count > $1.0.count }
        guard !rules.isEmpty else { return text }
        let names = rules.map { NSRegularExpression.escapedPattern(for: $0.0) }.joined(separator: "|")
        guard
            let regex = try? NSRegularExpression(
                pattern: "(?<![\\p{L}\\p{N}'’_-])(?:" + names + ")(?![\\p{L}\\p{N}'’_-])", options: .caseInsensitive)
        else { return text }
        let input = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: input.length))
        var output = text
        for match in matches.reversed() {
            let original = input.substring(with: match.range)
            guard let rule = rules.first(where: { $0.0.lowercased() == original.lowercased() }),
                let range = Range(match.range, in: output)
            else { continue }
            output.replaceSubrange(range, with: rule.1)
        }
        return output
    }
    public func relevantTerms(for text: String, maximum: Int = 30) -> [String] {
        let lower = text.lowercased()
        return Array(
            entries.filter {
                $0.enabled && $0.useForDictation
                    && (lower.contains($0.spelling.lowercased())
                        || $0.aliases.contains { lower.contains($0.lowercased()) })
            }
            .map(\.spelling).prefix(maximum))
    }
}

public final class PersonalDictionaryStore: @unchecked Sendable {
    public static let didChange = Notification.Name("one.binda.flype.dictionaryChanged")
    public enum Failure: LocalizedError {
        case invalid, conflict, limit, unsupported, unavailable
        public var errorDescription: String? {
            switch self {
            case .invalid: "Bitte gib einen Begriff mit höchstens 80 Zeichen und höchstens acht Varianten ein."
            case .conflict: "Diese Schreibweise oder Variante gehört bereits zu einem anderen Eintrag."
            case .limit: "Das Wörterbuch unterstützt zunächst bis zu 1.000 Einträge."
            case .unsupported: "Das Wörterbuchformat wird von dieser Version nicht unterstützt."
            case .unavailable: "Das persönliche Wörterbuch ist momentan nicht verfügbar."
            }
        }
    }
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("dictionary.json") }
    public init(directory: URL) { self.directory = directory }
    public static func shared() throws -> PersonalDictionaryStore {
        #if os(macOS)
            return PersonalDictionaryStore(
                directory: URL.applicationSupportDirectory.appendingPathComponent("Flype/Dictionary", isDirectory: true)
            )
        #else
            guard
                let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ResultStore.appGroup)
            else { throw Failure.unavailable }
            return PersonalDictionaryStore(directory: url.appendingPathComponent("Dictionary", isDirectory: true))
        #endif
    }
    public func snapshot() throws -> DictionarySnapshot {
        try locked {
            let snapshot = try read()
            // An empty dictionary also needs a stable revision for the first remote pull.
            if !FileManager.default.fileExists(atPath: fileURL.path) { try write(snapshot) }
            return snapshot
        }
    }
    public func upsert(_ value: PersonalDictionaryEntry) throws {
        try locked {
            var entry = value
            entry.spelling = Self.normalized(entry.spelling)
            entry.aliases = entry.aliases.map(Self.normalized)
            guard !entry.spelling.isEmpty, entry.spelling.count <= 80, entry.aliases.count <= 8,
                entry.aliases.allSatisfy({ !$0.isEmpty && $0.count <= 80 })
            else { throw Failure.invalid }
            var snapshot = try read()
            let keys = ([entry.spelling] + entry.aliases).map { $0.lowercased() }
            guard Set(keys).count == keys.count else { throw Failure.conflict }
            let otherKeys = Set(
                snapshot.entries.filter { $0.id != entry.id }.flatMap { [$0.spelling] + $0.aliases }.map {
                    $0.lowercased()
                })
            guard otherKeys.isDisjoint(with: keys) else { throw Failure.conflict }
            if let index = snapshot.entries.firstIndex(where: { $0.id == entry.id }) {
                snapshot.entries[index] = entry
            } else {
                guard snapshot.entries.count < 1_000 else { throw Failure.limit }
                snapshot.entries.append(entry)
            }
            snapshot.revision = UUID()
            try write(snapshot)
        }
    }
    public func delete(id: UUID) throws {
        try locked {
            var snapshot = try read()
            snapshot.entries.removeAll { $0.id == id }
            snapshot.revision = UUID()
            try write(snapshot)
        }
    }
    /// Compare-and-swap prevents a network response from replacing newer local edits.
    public func replace(entries: [PersonalDictionaryEntry], expectedRevision: UUID? = nil) throws {
        try locked {
            let current = try read()
            if let expectedRevision, current.revision != expectedRevision { throw Failure.conflict }
            guard entries.count <= 1_000, Set(entries.map(\.id)).count == entries.count else { throw Failure.limit }
            var keys = Set<String>()
            for entry in entries {
                guard entry.aliases.count <= 8 else { throw Failure.invalid }
                for word in [entry.spelling] + entry.aliases {
                    guard !word.isEmpty, word.count <= 80, Self.normalized(word) == word else { throw Failure.invalid }
                    guard keys.insert(word.lowercased()).inserted else { throw Failure.conflict }
                }
            }
            try write(DictionarySnapshot(entries: entries))
        }
    }
    private static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    private func read() throws -> DictionarySnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return DictionarySnapshot() }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 2_000_000 else { throw Failure.invalid }
        let snapshot = try JSONDecoder().decode(DictionarySnapshot.self, from: Data(contentsOf: fileURL))
        guard snapshot.schemaVersion == 1 else { throw Failure.unsupported }
        guard snapshot.entries.count <= 1_000,
            snapshot.entries.allSatisfy({
                !$0.spelling.isEmpty && $0.spelling.count <= 80 && $0.aliases.count <= 8
                    && $0.aliases.allSatisfy { !$0.isEmpty && $0.count <= 80 }
            })
        else { throw Failure.invalid }
        return snapshot
    }
    private func write(_ snapshot: DictionarySnapshot) throws {
        #if os(iOS)
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: [.atomic, .completeFileProtection])
        #else
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        #endif
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
    private func locked<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(directory.appendingPathComponent("store.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Failure.unavailable }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw Failure.unavailable }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}
