import CoreGraphics
import XCTest

@testable import FlypeCore

final class SwipeDecoderTests: XCTestCase {
    private static let sample = """
        dictionary=main:de,locale=de,version=18
         word=das,f=231
          bigram=Haus,f=2
         word=dass,f=200
         word=und,f=180
         word=Haus,f=166
         word=Hass,f=100
         word=hallo,f=55
         word=Maß,f=50
         word=Dr.,f=50
         word=Baden-Württemberg,f=50
         word=Schimpf,f=50,possibly_offensive=true
         word=x,f=50
         word=Hund,f=40
         word=selten,f=10
        """

    private var sampleList: CombinedWordList { CombinedWordList(data: Data(Self.sample.utf8)) }

    /// iPhone geometry: rows 52 points apart, keys 35 points apart, the lower rows centered under the top row.
    private static func layout(for language: FlypeLanguage) -> SwipeKeyLayout {
        var keys: [String: CGPoint] = [:]
        let rows = language.keyboardRows
        for (row, letters) in rows.enumerated() {
            let indent = Double(rows[0].count - letters.count) * 35 / 2
            for (column, letter) in letters.enumerated() {
                keys[String(letter)] = CGPoint(x: 18 + indent + Double(column) * 35, y: 26 + Double(row) * 52)
            }
        }
        return SwipeKeyLayout(keys: keys, keyPitch: 35)
    }

    private static let layout = layout(for: .de)

    private func idealPath(_ word: String, on layout: SwipeKeyLayout = SwipeDecoderTests.layout, spacing: Double = 8)
        -> [CGPoint]
    {
        var centers: [CGPoint] = []
        for character in word.lowercased() {
            let special = ["ß": "s", "œ": "o", "æ": "a", "ø": "o"][String(character)]
            let base = String(character).decomposedStringWithCanonicalMapping.unicodeScalars.first.map(String.init)
            let center = layout.keys[String(character)] ?? layout.keys[special ?? base ?? ""]
            if let center, centers.last != center { centers.append(center) }
        }
        guard let first = centers.first else { return [] }
        var path = [first]
        for (start, end) in zip(centers, centers.dropFirst()) {
            let steps = max(1, Int((hypot(end.x - start.x, end.y - start.y) / spacing).rounded()))
            for step in 1...steps {
                let ratio = Double(step) / Double(steps)
                path.append(CGPoint(x: start.x + (end.x - start.x) * ratio, y: start.y + (end.y - start.y) * ratio))
            }
        }
        return path
    }

    /// A rough human stroke: corners are cut and the whole line sits off-center and wanders slowly.
    private func sloppyPath(
        _ word: String, on layout: SwipeKeyLayout = SwipeDecoderTests.layout, random: inout SeededRandom, amount: Double
    ) -> [CGPoint] {
        let ideal = idealPath(word, on: layout)
        guard ideal.count > 2 else { return ideal }
        let smoothed = ideal.indices.map { index -> CGPoint in
            let window = ideal[max(0, index - 3)...min(ideal.count - 1, index + 3)]
            return CGPoint(
                x: window.map(\.x).reduce(0, +) / CGFloat(window.count),
                y: window.map(\.y).reduce(0, +) / CGFloat(window.count))
        }
        let driftX = random.next(in: -amount...amount)
        let driftY = random.next(in: -amount...amount)
        let phaseX = random.next(in: 0...6.28)
        let phaseY = random.next(in: 0...6.28)
        return smoothed.enumerated().map { index, point in
            CGPoint(
                x: point.x + driftX + amount * sin(phaseX + Double(index) * 0.15),
                y: point.y + driftY + amount * sin(phaseY + Double(index) * 0.11))
        }
    }

    private func candidates(_ path: [CGPoint], list: CombinedWordList, previous: String? = nil) -> [String] {
        SwipeDecoder.candidates(path: path, layout: Self.layout, list: list, previousWord: previous)
    }

    // MARK: Reading the file

    func testKeepsOnlyPlainFrequentWords() {
        let words = sampleList.groups.values.flatMap { $0 }.map(sampleList.word)
        XCTAssertEqual(
            Set(words), ["das", "dass", "und", "Haus", "Hass", "hallo", "Maß", "Hund"],
            "periods, hyphens, offensive words, single letters and rare words stay out")
        XCTAssertEqual(sampleList.count, 8)
    }

    func testStopsAtTheFirstWordBelowTheMinimum() {
        let list = CombinedWordList(data: Data(" word=vorne,f=40\n word=mitte,f=20\n word=hinten,f=90\n".utf8))
        XCTAssertEqual(list.count, 1)
    }

    func testReadsNextWordsWhateverTheCase() {
        XCTAssertEqual(sampleList.nextWords(after: "das"), ["haus": 2])
        XCTAssertEqual(sampleList.nextWords(after: "Das"), ["haus": 2])
        XCTAssertEqual(sampleList.nextWords(after: "unbekannt"), [:])
        XCTAssertEqual(sampleList.nextWords(after: "und"), [:])
    }

    func testBrokenFilesProduceNoWords() {
        for text in ["", "\n\n", " word=", " word=abc", " word=abc,f=", " word=abc,f=999", "unsinn,f=100"] {
            XCTAssertEqual(CombinedWordList(data: Data(text.utf8)).count, 0, text)
        }
    }

    // MARK: Decoding

    func testFindsTheWordOnAnExactPath() {
        XCTAssertEqual(candidates(idealPath("hallo"), list: sampleList).first, "hallo")
        XCTAssertEqual(candidates(idealPath("und"), list: sampleList).first, "und")
    }

    func testAmbiguousPathsPreferTheCommonerWord() {
        XCTAssertEqual(candidates(idealPath("das"), list: sampleList).prefix(2), ["das", "dass"])
    }

    func testPreviousWordCanTipTheBalance() {
        // A double letter does not move the finger, so both words share one path.
        let list = CombinedWordList(
            data: Data(" word=der,f=200\n  bigram=Hass,f=2\n word=Has,f=100\n word=Hass,f=95\n".utf8))
        let path = idealPath("has")
        XCTAssertEqual(candidates(path, list: list).first, "Has")
        XCTAssertEqual(candidates(path, list: list, previous: "der").first, "Hass")
    }

    func testLettersWithoutTheirOwnKeyUseTheirBaseLetter() {
        XCTAssertEqual(candidates(idealPath("maß"), list: sampleList).first, "Maß")
    }

    func testApostrophesDoNotCountAsKeys() {
        let list = CombinedWordList(
            data: Data(" word=l',f=240\n word=c'est,f=200\n word=auto's,f=100\n word='n,f=90\n".utf8))
        XCTAssertEqual(list.count, 3, "a word cannot start with an apostrophe")
        let french = Self.layout(for: .fr)
        XCTAssertEqual(
            SwipeDecoder.candidates(path: idealPath("cest", on: french), layout: french, list: list).first, "c'est")
        XCTAssertEqual(candidates(idealPath("autos"), list: list).first, "auto's")
    }

    func testWordsOnASingleKeyAreNeverSuggested() {
        let list = CombinedWordList(data: Data(" word=l',f=250\n word=lo,f=40\n".utf8))
        XCTAssertEqual(candidates(idealPath("lo"), list: list), ["lo"])
    }

    func testLigaturesUseTheKeyThatOffersThem() {
        let list = CombinedWordList(data: Data(" word=cœur,f=100\n".utf8))
        let french = Self.layout(for: .fr)
        XCTAssertEqual(
            SwipeDecoder.candidates(path: idealPath("coeur", on: french), layout: french, list: list).first, "cœur")
    }

    func testAppliesCasingAndDropsResultingDuplicates() {
        let list = CombinedWordList(data: Data(" word=essen,f=100\n word=Essen,f=90\n".utf8))
        let path = idealPath("essen")
        XCTAssertEqual(candidates(path, list: list), ["essen", "Essen"])
        XCTAssertEqual(
            SwipeDecoder.candidates(path: path, layout: Self.layout, list: list, casing: .capitalized), ["Essen"])
        XCTAssertEqual(
            SwipeDecoder.candidates(path: path, layout: Self.layout, list: list, casing: .allCaps), ["ESSEN"])
    }

    func testPathsThatMatchNothingReturnNothing() {
        XCTAssertEqual(candidates([], list: sampleList), [])
        XCTAssertEqual(candidates([CGPoint(x: 18, y: 26)], list: sampleList), [])
        XCTAssertEqual(candidates(idealPath("qp"), list: sampleList), [])
        let invalid = [CGPoint(x: CGFloat.nan, y: 1), CGPoint(x: 2, y: 2)]
        XCTAssertEqual(candidates(invalid, list: sampleList), [])
        let far = [CGPoint(x: 5000, y: 5000), CGPoint(x: 6000, y: 5000)]
        XCTAssertEqual(candidates(far, list: sampleList), [])
    }

    // MARK: The real list

    private func realList(_ language: FlypeLanguage = .de) throws -> CombinedWordList {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("vendor/HeliBoardDictionaries/main_\(language.rawValue).combined")
        return CombinedWordList(data: try Data(contentsOf: url, options: .alwaysMapped))
    }

    func testRealListKeepsAWorkableWordCount() throws {
        let list = try realList()
        XCTAssertGreaterThan(list.count, 100_000)
        XCTAssertLessThan(list.count, 300_000)
        XCTAssertEqual(list.nextWords(after: "der")["stadt"], 1)
    }

    /// Synthetic strokes guard against regressions. How well swiping really works can only be judged on a device.
    func testRealListFindsEverydayWordsOnRoughPaths() throws {
        let list = try realList()
        let words = [
            "hallo", "danke", "bitte", "morgen", "heute", "gerne", "vielleicht", "machen", "kommen", "gehen",
            "wir", "nicht", "auch", "aber", "wenn", "dann", "schon", "noch", "immer", "wieder",
            "Haus", "Straße", "Arbeit", "Freunde", "Zeit", "Woche", "Abend", "Geburtstag", "Wochenende", "Familie",
            "können", "müssen", "möchte", "für", "später", "schön", "wünsche", "natürlich", "Grüße", "Mutter",
        ]
        let (first, topThree) = accuracy(of: words, list: list)
        print("Swipe accuracy, everyday words: first \(first)/\(words.count), top three \(topThree)/\(words.count)")
        XCTAssertGreaterThanOrEqual(Double(first) / Double(words.count), 0.75)
        XCTAssertGreaterThanOrEqual(Double(topThree) / Double(words.count), 0.9)
    }

    func testEveryLanguageFindsCommonWordsOnItsOwnLayout() throws {
        for language in FlypeLanguage.allCases {
            let list = try realList(language)
            let layout = Self.layout(for: language)
            // The file's own order is stable, unlike the order of the groups.
            let common = list.groups.values.flatMap { $0 }.sorted { $0.offset < $1.offset }.prefix(3000)
                .map(list.word).filter { $0.dropFirst().allSatisfy { !$0.isUppercase } }.sorted()
            let words = stride(from: 0, to: common.count, by: max(1, common.count / 30)).map { common[$0] }
            let (first, topThree) = accuracy(of: words, list: list, layout: layout)
            print("Swipe accuracy, \(language.rawValue): \(first) first, \(topThree) top three of \(words.count)")
            XCTAssertGreaterThan(list.count, 50_000, language.rawValue)
            XCTAssertGreaterThanOrEqual(Double(first) / Double(words.count), 0.6, language.rawValue)
            XCTAssertGreaterThanOrEqual(Double(topThree) / Double(words.count), 0.8, language.rawValue)
        }
    }

    /// The case of a word does not count: the keyboard sets it from the shift state.
    private func accuracy(
        of words: [String], list: CombinedWordList, layout: SwipeKeyLayout = SwipeDecoderTests.layout
    ) -> (first: Int, topThree: Int) {
        var random = SeededRandom(seed: 42)
        var first = 0
        var topThree = 0
        for word in words {
            let path = sloppyPath(word, on: layout, random: &random, amount: 6)
            let results = SwipeDecoder.candidates(path: path, layout: layout, list: list).map { $0.lowercased() }
            if results.first == word.lowercased() { first += 1 }
            if results.contains(word.lowercased()) { topThree += 1 }
        }
        return (first, topThree)
    }

    func testRealListDecodesWithinATypingPause() throws {
        let list = try realList()
        let path = idealPath("wochenende")
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<5 { _ = candidates(path, list: list) }
        let duration = (ProcessInfo.processInfo.systemUptime - start) / 5
        print("Swipe decoding took \(Int(duration * 1000)) ms per word")
        XCTAssertLessThan(duration, 1)
    }
}

/// A small deterministic generator, so rough paths are the same on every run.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let unit = Double(state >> 11) / Double(UInt64(1) << 53)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}
