import FlypeCore

#if DEBUG
    import Foundation
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
            return false
        }
    }
#endif
