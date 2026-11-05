# Design and languages

iPhone, iPad and Mac share one structure: **Start, Words, Settings**. The account is reached through the profile or Settings. Warm neutral surfaces, the system font, a purple accent and shared terms connect both apps. Colors follow the system appearance, and the dark variant uses a lighter accent so controls stay readable.

On iPhone, transcribing stays a keyboard feature. The start page holds setup, standby and a real test area, but no second regular recording flow. On Mac, you hold the key to speak and release to insert. The button on the start page runs a local test, and test text is not sent to another app. The floating indicator shows the recording, the language, a round outline that reacts to your voice and a round button that cancels. See [Recording start](RECORDING-START.md#cancelling).

The iOS app is universal and uses the adaptive sidebar on iPad. On 12.9- and 13-inch iPads, the keyboard follows the native full-size layout with five rows: a number row, keys with two characters, function keys with their symbol in a corner and, on ISO layouts, an L-shaped Return. Smaller iPads follow their native four-row layout, where swiping up on a key inserts its small grey character and a second symbol page holds those characters. Keys, punctuation and grids of all six languages come from the native keyboards and scale with the width. Swiping up on a two-character key inserts its upper character. iOS adds its own row with undo, redo and paste above any keyboard on iPad. It cannot be removed and takes no words, so Flype's word row sits below it and the keys are slightly lower, which keeps the height of the native keyboard. Apple offers keyboards no undo or redo, so those keys on the symbol page stay empty. Narrow layouts stay compact.

## Six languages

German, English, French, Italian, Spanish and Dutch can be chosen separately for the interface and for transcription. The interface follows the device by default and falls back to English. The transcription language stays German until changed. On iOS, these settings live in the App Group, so the app and keyboard use the same choice. Accounts, tokens and transcriptions are not part of them.

`FlypeLanguage.swift` defines language codes, recognition locales and layouts. QWERTZ has German umlauts, French uses AZERTY, and Spanish uses QWERTY with ñ. Word suggestions use the matching system spell checker. The extra German next-word heuristics apply to German only.

`L10n.swift` holds the shared translations, keyed by the German text. The apps and keyboard need no downloads or translation services at runtime. User input and dictionary words are not translated. `shared/Resources/*.lproj/InfoPlist.strings` holds the microphone text for system dialogs.

The language is fixed at the start of a recording in `DictationOptions`. Apple recognition uses the local `SpeechTranscriber` or `DictationTranscriber` language data and downloads it when needed. Parakeet v3 detects the language itself, and its public API cannot force one, so the choice only steers the keyboard, suggestions and cleanup. Cleanup does not translate and checks whether Apple's local model supports the chosen language. If not, the original text stays. The dictionary audio check uses the chosen language, while the phonetic matching is limited to German and English.

## Still needs device testing

Real transcriptions in every language, long translations and dark mode, iPad in portrait, landscape and Split View, VoiceOver, keyboard access, and automatic return and insertion in other apps. Automated core tests do not replace these.
