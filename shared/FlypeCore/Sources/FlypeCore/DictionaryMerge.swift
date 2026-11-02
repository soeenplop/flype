import Foundation

/// Three-way merge. Conflicting edits stay on each device until explicitly resolved.
public enum DictionaryMerge {
    public struct Conflict: Error, Equatable { public let ids: [UUID] }
    public static func merge(
        base: [PersonalDictionaryEntry], local: [PersonalDictionaryEntry], remote: [PersonalDictionaryEntry]
    ) throws -> [PersonalDictionaryEntry] {
        func indexed(_ entries: [PersonalDictionaryEntry]) throws -> [UUID: PersonalDictionaryEntry] {
            guard Set(entries.map(\.id)).count == entries.count else { throw PersonalDictionaryStore.Failure.invalid }
            return Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        }
        let b = try indexed(base)
        let l = try indexed(local)
        let r = try indexed(remote)
        var merged: [PersonalDictionaryEntry] = []
        var conflicts: [UUID] = []
        for id in Set(b.keys).union(l.keys).union(r.keys).sorted(by: { $0.uuidString < $1.uuidString }) {
            let value: PersonalDictionaryEntry?
            if l[id] == b[id] {
                value = r[id]
            } else if r[id] == b[id] || l[id] == r[id] {
                value = l[id]
            } else {
                conflicts.append(id)
                continue
            }
            if let value { merged.append(value) }
        }
        guard conflicts.isEmpty else { throw Conflict(ids: conflicts) }
        // Identical independently added spellings collapse; differing options need a decision.
        var keys: [String: PersonalDictionaryEntry] = [:]
        var result: [PersonalDictionaryEntry] = []
        for entry in merged {
            if let existing = keys[entry.spelling.lowercased()] {
                var comparison = entry
                comparison.id = existing.id
                guard comparison == existing else { throw Conflict(ids: [entry.id, existing.id]) }
                continue
            }
            for key in ([entry.spelling] + entry.aliases).map({ $0.lowercased() }) {
                guard keys[key] == nil else { throw Conflict(ids: [entry.id, keys[key]!.id]) }
                keys[key] = entry
            }
            result.append(entry)
        }
        return result
    }
}
