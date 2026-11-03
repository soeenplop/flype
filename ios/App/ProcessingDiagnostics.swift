import FlypeCore

#if DEBUG
    import Foundation
    import FoundationModels
    import UIKit

    @MainActor
    enum ProcessingDiagnostics {
        static func runIfRequested() -> Bool {
            if ProcessInfo.processInfo.arguments.contains("--verify-dictionary") {
                Task {
                    UIApplication.shared.isIdleTimerDisabled = true
                    defer { UIApplication.shared.isIdleTimerDisabled = false }
                    let file = URL.documentsDirectory.appendingPathComponent("flype-dictionary-test.wav")
                    let service = DictionaryCorrectionService()
                    let begin = ProcessInfo.processInfo.systemUptime
                    print("FLYPE_DICTIONARY_DIAGNOSTIC preparing=true")
                    await service.prepare()
                    print(
                        "FLYPE_DICTIONARY_DIAGNOSTIC prepared=true seconds=\(ProcessInfo.processInfo.systemUptime - begin)"
                    )
                    let dictionary = DictionarySnapshot(entries: [.init(spelling: "Flype")])
                    for (index, text, expected) in [
                        (0, "Ich benutze Fleib.", "Ich benutze Flype."),
                        (1, "Ich bleibe hier.", "Ich bleibe hier."),
                        (2, "Ich benutze Fleib nicht.", "Ich benutze Fleib nicht."),
                        (3, "Ich benutze Fleib.", "Ich benutze Flype."),
                        (4, "Ich benutze Fleib.", "Ich benutze Flype."),
                        (5, "Ich benutze Flight.", "Ich benutze Flype."),
                    ] {
                        do {
                            let start = ProcessInfo.processInfo.systemUptime
                            let result = try await service.correct(text, file: file, dictionary: dictionary)
                            print(
                                "FLYPE_DICTIONARY_CASE index=\(index) expected=\(result.text == expected) changes=\(result.changes) fallback=\(result.notice != nil) seconds=\(ProcessInfo.processInfo.systemUptime - start)"
                            )
                        } catch {
                            let error = error as NSError
                            print(
                                "FLYPE_DICTIONARY_CASE index=\(index) errorDomain=\(error.domain) errorCode=\(error.code)"
                            )
                        }
                    }
                }
                return true
            }
            guard ProcessInfo.processInfo.arguments.contains("--verify-local-cleanup") else { return false }
            Task {
                UIApplication.shared.isIdleTimerDisabled = true
                defer { UIApplication.shared.isIdleTimerDisabled = false }
                guard TextCleanupService.availabilityMessage() == nil else {
                    print("FLYPE_CLEANUP_DIAGNOSTIC available=false")
                    return
                }
                print(
                    "FLYPE_CLEANUP_DIAGNOSTIC available=true mode=\(DictationOptions.current().mode.rawValue) build=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "unknown")"
                )
                let service = TextCleanupService()
                let examples = [
                    "Hallo Anna äh ich komme morgen bitte bring die Unterlagen mit",
                    "Ich komme nicht morgen sondern am Freitag",
                    "Bitte überweise 15 Euro an Anna",
                    "Hallo Anna ich komme um zehn nein um elf",
                    "drei nein vier Häuser",
                    "sieben äh nein acht Wohnungen",
                ]
                for (index, text) in examples.enumerated() {
                    let start = ProcessInfo.processInfo.systemUptime
                    do {
                        let result = try await service.clean(text, dictionary: DictionarySnapshot())
                        let expected = index == 4 ? "vier Häuser" : index == 5 ? "acht Wohnungen" : nil
                        let actual = result.lowercased().split(whereSeparator: { !$0.isLetter }).joined(
                            separator: " ")
                        let matched = expected.map { actual == $0.lowercased() } ?? true
                        print(
                            "FLYPE_CLEANUP_MATCH index=\(index) matched=\(matched)")
                        print(
                            "FLYPE_CLEANUP_CASE index=\(index) success=true characters=\(result.count) seconds=\(ProcessInfo.processInfo.systemUptime - start)"
                        )
                    } catch {
                        let error = error as NSError
                        print(
                            "FLYPE_CLEANUP_CASE index=\(index) success=false domain=\(error.domain) code=\(error.code)")
                    }
                }
            }
            return true
        }
    }
#endif
