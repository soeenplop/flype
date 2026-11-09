import Foundation

/// Proposed edits are bounded spans of the original transcript, never generated text.
public struct DictionaryCandidate: Equatable, Sendable {
    public let id: Int
    public let range: NSRange
    public let heard: String
    public let spelling: String
}

/// A dictionary term that a second recognition of the same audio supports, but that no local model
/// could check in the sentence. Cleanup may use it when the term fits; it never replaces text on its own.
public struct DictionarySoundAlike: Codable, Equatable, Sendable {
    public let heard: String
    public let spelling: String
    public init(heard: String, spelling: String) {
        self.heard = heard
        self.spelling = spelling
    }
}

public enum DictionaryCorrection {
    private struct Word {
        let text: String
        let range: NSRange
    }
    // Function words must never become names merely because they sound similar.
    private static let protectedWords: Set<String> = Set(
        "ich du er sie es wir ihr der die das den dem des ein eine einer einen einem eines und oder aber auch nicht kein keine keinen keinem keiner ohne nie niemals ja nein bitte bin bist ist sind seid war waren werde wird werden habe hast hat haben hatte kann kannst können muss müssen soll sollen mit für von zu zur zum auf aus an am im in um über unter nach vor bei bis als so noch nur hier dort heute morgen gestern jetzt dann mein meine dein deine sein seine unser unsere wie was wer wo wann warum dass wenn weil bleibe bleib bleibt bleiben i you he she it we they the a an and or but not no never without am is are was were will have has can must with for in on at from to my your le la les un une des et ou mais ne pas jamais sans je tu il elle nous vous ils elles est sont de du au aux mon ton son non mai senza io tu lui lei noi voi loro il lo gli di da con per e o ma no nunca sin yo tú él ella nosotros vosotros ellos el los las una unos unas y pero con para en por mi tu su niet geen nooit zonder ik jij hij zij wij jullie het een en of maar is zijn van voor op uit mijn jouw"
            .split(separator: " ").map(String.init))

    public static func candidates(in text: String, dictionary: DictionarySnapshot, maximum: Int = 12)
        -> [DictionaryCandidate]
    {
        guard text.utf8.count <= 5_000, maximum > 0 else { return [] }
        let words = tokenize(text)
        struct Term {
            let spelling: String
            let key: String
        }
        var groups: [String: [Term]] = [:]
        for entry in dictionary.entries where entry.enabled && entry.useForDictation && entry.spelling.count >= 4 {
            guard entry.spelling.allSatisfy({ $0.isLetter || $0.isWhitespace || "-’'".contains($0) }) else { continue }
            let count = tokenize(entry.spelling).count
            let key = phoneticKey(entry.spelling)
            guard count > 0, count <= 4, let first = key.first else { continue }
            groups["\(count):\(first)", default: []].append(Term(spelling: entry.spelling, key: key))
        }
        var found: [DictionaryCandidate] = []
        let ns = text as NSString
        let protected = protectedRanges(in: text)
        // Build each source span once, independent of dictionary size.
        for start in words.indices {
            for count in 1...min(4, words.count - start) {
                let slice = Array(words[start..<(start + count)])
                guard slice.allSatisfy({ !protectedWords.contains($0.text) }) else { continue }
                let range = NSRange(
                    location: slice[0].range.location, length: NSMaxRange(slice.last!.range) - slice[0].range.location)
                guard !protected.contains(where: { NSIntersectionRange($0, range).length > 0 }) else { continue }
                let heard = ns.substring(with: range)
                let joined = slice.map(\.text).joined(separator: " ")
                guard heard.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") == joined else {
                    continue
                }
                let key = phoneticKey(heard)
                guard let first = key.first, let terms = groups["\(count):\(first)"] else { continue }
                for term in terms where heard != term.spelling {
                    let distance = editDistance(key, term.key)
                    let length = max(key.count, term.key.count)
                    // Short sound keys need an exact match; from five sounds, allow one difference.
                    // This only proposes an edit; audio + context still decide.
                    guard distance == 0 || (length >= 5 && key.prefix(2) == term.key.prefix(2) && distance == 1) else {
                        continue
                    }
                    found.append(.init(id: found.count, range: range, heard: heard, spelling: term.spelling))
                    if found.count >= maximum { return found }
                }
            }
        }
        return found
    }

    /// Candidates the audio supports by sound but that were neither applied nor rejected in the sentence.
    /// Without audio support nothing qualifies, so similarity alone never reaches the cleanup.
    public static func soundAlikes(
        _ candidates: [DictionaryCandidate], audioSupported: Set<Int>, decided: Set<Int>, maximum: Int = 12
    ) -> [DictionarySoundAlike] {
        var seen = Set<String>()
        return candidates.filter { audioSupported.contains($0.id) && !decided.contains($0.id) }
            .map { DictionarySoundAlike(heard: $0.heard, spelling: $0.spelling) }
            .filter { seen.insert($0.heard + "\u{0}" + $0.spelling).inserted }
            .prefix(maximum).map { $0 }
    }

    /// Evidence must be explainable entirely by our proposed edits. A different
    /// sentence, added negation/number, or an unaligned occurrence confirms nothing.
    public static func audioConfirmed(
        _ candidates: [DictionaryCandidate], original: String, evidence: String, allowPhonetic: Bool = false
    ) -> Set<Int> {
        let source = tokenize(original)
        let audio = tokenize(evidence)
        guard source.count <= 1_000, audio.count <= 1_000 else { return [] }
        var matches: [[Int]] = []
        func walk(_ i: Int, _ j: Int, _ chosen: [Int]) {
            guard matches.count < 2 else { return }
            if i == source.count && j == audio.count {
                matches.append(chosen)
                return
            }
            guard i < source.count, j < audio.count else { return }
            var alternatives: [(id: Int, sourceEnd: Int, audioEnd: Int)] = []
            for candidate in candidates where candidate.range.location == source[i].range.location {
                let replacement = tokenize(candidate.spelling).map(\.text)
                guard !replacement.isEmpty, j + replacement.count <= audio.count,
                    zip(Array(audio[j..<(j + replacement.count)]).map(\.text), replacement).allSatisfy({
                        heard, spelling in
                        heard == spelling || (allowPhonetic && similarAudioWord(heard, spelling))
                    }),
                    let last = source.firstIndex(where: { NSMaxRange($0.range) == NSMaxRange(candidate.range) })
                else { continue }
                // Case-only changes have the same acoustic path; keep the unchanged path unique.
                guard source[i...last].map(\.text) != replacement else { continue }
                alternatives.append((candidate.id, last + 1, j + replacement.count))
            }
            // In the contextual mode, agreement on an approximate spelling is
            // still acoustic support for a proposed name. Defer that decision
            // to the context gate, rather than treating the unchanged path as
            // an ambiguous competing dictionary entry.
            if source[i].text == audio[j].text && !(allowPhonetic && !alternatives.isEmpty) {
                walk(i + 1, j + 1, chosen)
            }
            for alternative in alternatives {
                walk(alternative.sourceEnd, alternative.audioEnd, chosen + [alternative.id])
            }
        }
        walk(0, 0, [])
        guard matches.count == 1 else { return [] }
        return Set(matches[0])
    }

    public static func applying(_ candidates: [DictionaryCandidate], approved: Set<Int>, to text: String) -> String {
        let edits = candidates.filter { approved.contains($0.id) }.sorted { $0.range.location < $1.range.location }
        var previousEnd = 0
        let ns = text as NSString
        for edit in edits {
            guard edit.range.location >= previousEnd, NSMaxRange(edit.range) <= ns.length,
                ns.substring(with: edit.range) == edit.heard
            else { return text }
            previousEnd = NSMaxRange(edit.range)
        }
        var output = text
        for edit in edits.reversed() {
            guard let range = Range(edit.range, in: output) else { return text }
            output.replaceSubrange(range, with: edit.spelling)
        }
        return output
    }

    /// A deliberately narrow German/English sound approximation for candidate
    /// discovery only. This is never sufficient evidence to replace a word.
    public static func phoneticKey(_ text: String) -> String {
        var value = text.precomposedStringWithCanonicalMapping.lowercased()
        for (a, b) in [
            ("ä", "e"), ("ö", "o"), ("ü", "u"), ("ß", "ss"),
            ("ph", "f"), ("igh", "ai"), ("sch", "sh"), ("tsch", "ch"), ("ei", "ai"),
            ("ey", "ai"), ("ay", "ai"), ("y", "ai"), ("ie", "i"),
        ] {
            value = value.replacingOccurrences(of: a, with: b)
        }
        var parts: [String] = []
        for word in value.split(whereSeparator: { !$0.isLetter }) {
            var part = String(word)
            if part.count > 3 && part.hasSuffix("e") { part.removeLast() }
            part = part.replacingOccurrences(of: "b", with: "p").replacingOccurrences(of: "d", with: "t")
                .replacingOccurrences(of: "g", with: "k")
            var reduced = ""
            for c in part where reduced.last != c { reduced.append(c) }
            parts.append(reduced)
        }
        return parts.joined(separator: " ")
    }

    private static func similarAudioWord(_ heard: String, _ spelling: String) -> Bool {
        let a = phoneticKey(heard)
        let b = phoneticKey(spelling)
        guard a.count >= 4, b.count >= 4, a.prefix(2) == b.prefix(2) else { return false }
        if a == b { return true }
        return min(a.count, b.count) >= 5 && editDistance(a, b) == 1
    }

    private static func tokenize(_ text: String) -> [Word] {
        let regex = try! NSRegularExpression(
            pattern: "[\\p{L}\\p{N}][\\p{L}\\p{M}\\p{N}]*(?:[-’'][\\p{L}\\p{M}\\p{N}]+)*")
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            Word(text: ns.substring(with: $0.range).precomposedStringWithCanonicalMapping.lowercased(), range: $0.range)
        }
    }
    private static func protectedRanges(in text: String) -> [NSRange] {
        let ns = text as NSString
        let protected = try! NSRegularExpression(
            pattern:
                "https?://[^\\s]+|[\\p{L}\\p{N}_.+-]+@[\\p{L}\\p{N}.-]+|[\\p{L}\\p{N}-]+\\.[\\p{L}]{2,}(?:/[^\\s]*)?|[0-9]+(?:[.,:/-][0-9]+)*",
            options: .caseInsensitive)
        return protected.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range)
    }
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let lhs = Array(a)
        let rhs = Array(b)
        guard abs(lhs.count - rhs.count) <= 1 else { return 2 }
        var previous = Array(0...rhs.count)
        for (i, left) in lhs.enumerated() {
            var current = [i + 1]
            for (j, right) in rhs.enumerated() {
                current.append(min(current[j] + 1, previous[j + 1] + 1, previous[j] + (left == right ? 0 : 1)))
            }
            previous = current
        }
        return previous.last!
    }
}
