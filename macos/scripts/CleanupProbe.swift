import FlypeCore
import Foundation

@main
struct CleanupProbe {
    static func main() async {
        let cases = [
            (
                "War das eine echte Bestellung? Nein, das war ein Test.",
                "War das eine echte Bestellung? Nein, das war ein Test."
            ),
            (
                "Wir haben keinen Auftrag erteilt. Nein, das war ein Test.",
                "Wir haben keinen Auftrag erteilt. Nein, das war ein Test."
            ),
            ("Hallo, das ist Nein, das war ein Test.", "Hallo, das war ein Test."),
            (
                "Die Lieferung kommt morgen. Wir nehmen den kleinen, nein, den großen Wagen. Der Fahrer wartet am Eingang.",
                "Die Lieferung kommt morgen. Wir nehmen den großen Wagen. Der Fahrer wartet am Eingang."
            ),
            (
                "Das Treffen ist am Montag. Nein, das Treffen war am Dienstag. Die Unterlagen liegen bereit.",
                "Das Treffen war am Dienstag. Die Unterlagen liegen bereit."
            ),
            ("Nein, das war ein Test.", "Nein, das war ein Test."),
            ("drei nein vier Häuser", "Vier Häuser."),
            ("sieben äh nein acht Wohnungen", "Acht Wohnungen."),
            (
                "Bitte reserviere den kleinen nein den großen Besprechungsraum. Die Gäste kommen mit dem Zug.",
                "Bitte reserviere den großen Besprechungsraum. Die Gäste kommen mit dem Zug."
            ),
            (
                "Wir treffen uns am Montag nein am Dienstag im Büro und sprechen über den Vertrag.",
                "Wir treffen uns am Dienstag im Büro und sprechen über den Vertrag."
            ),
            ("Wir bauen hier ein ähm nein zwei Häuser.", "Wir bauen hier zwei Häuser."),
            (
                "Der Bau beginnt morgen. Wir bauen hier ein ähm nein zwei Häuser. Der Garten bleibt erhalten.",
                "Der Bau beginnt morgen. Wir bauen hier zwei Häuser. Der Garten bleibt erhalten."
            ),
            (
                "Wir planen einen Anbau und sprechen heute mit dem Architekten. Wir bauen hier ein ähm nein zwei Häuser. Die Zufahrt bleibt an der gleichen Stelle und die Bäume sollen erhalten bleiben. Die Unterlagen schicken wir am Dienstag nein am Mittwoch an die Gemeinde. Danach besprechen wir die nächsten Schritte.",
                "Wir planen einen Anbau und sprechen heute mit dem Architekten. Wir bauen hier zwei Häuser. Die Zufahrt bleibt an der gleichen Stelle und die Bäume sollen erhalten bleiben. Die Unterlagen schicken wir am Mittwoch an die Gemeinde. Danach besprechen wir die nächsten Schritte."
            ),
            ("Wir bestellen rote nein blaue Stühle für das Büro.", "Wir bestellen blaue Stühle für das Büro."),
            ("Hallo, das ist ein nein das sind zwei Tests.", "Hallo, das sind zwei Tests."),
            ("Nein, das sind zwei Tests.", "Nein, das sind zwei Tests."),
            ("Hallo Anna, das ist ein nein das sind drei Aufgaben.", "Hallo Anna, das sind drei Aufgaben."),
            ("Hallo Anna, ich komme nicht morgen.", "Hallo Anna, ich komme nicht morgen."),
        ]
        var failures = 0
        for (input, expected) in cases {
            do {
                let result = try await TextCleanupService().clean(
                    input, dictionary: DictionarySnapshot(), language: .de)
                func words(_ text: String) -> [String] {
                    text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
                }
                let passed = words(result.text) == words(expected) && !result.requiresReview
                print("FIXTURE: \(passed ? "PASS" : "FAIL") | \(result.text) | review=\(result.requiresReview)")
                if !passed { failures += 1 }
            } catch {
                print("PROBE_ERROR: \(error)")
                failures += 1
            }
        }
        if failures > 0 { exit(1) }
    }
}
