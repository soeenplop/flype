# Fast keyboard input

Why the keyboard is built the way it is. Most of this exists because something felt slow or dropped touches.

## Touch handling

- Keys keep their visible gaps. `KeyboardKeyGrid` also assigns touches in the gaps to a key, first by row, then by the nearest visible target. Each key's touch area reaches halfway to its neighbors.
- `KeyboardInputView` passes the keyboard's outer edges and the narrow gap below the suggestion bar on to the grid, so edge keys reach the keyboard's edge. The suggestion bar keeps its own area, and the edge below the microphone does not trigger it.
- The main view needs a background with minimal opacity (0.001). The system does not deliver touches from fully transparent areas to the extension.
- Switching between letters and symbols runs layout right away. New keys have no frames until the next layout pass, and a touch arriving before it would hit no key and be lost.
- The hosted microphone link receives touches through its own view hierarchy, so enlarged touch areas of neighboring keys cannot intercept it.
- A short tap no longer waits for a long-press gesture to end. Once a real long press is recognized, UIKit suppresses the regular character, so choosing an umlaut adds no extra base letter.
- The key preview appears on touch-down and disappears on lift, with no minimum duration. It hangs on the observing gesture `KeyboardPreviewGesture` rather than key state, because the system can delay touches at the screen edge for views. The gesture recognizes, delays and interrupts nothing.

## Swipe typing

On iPhone, sliding one finger across the letters enters a whole word. It runs for each language with a word list in `vendor/HeliBoardDictionaries`, which is all six. iPad stays out because swiping up there selects a key's upper character.

- `KeyboardSwipeGesture` only takes over once one finger has moved 0.8 key widths from a letter. Up to then keys behave as usual, and a second finger, a long press or a menu makes it fail. When it takes over, UIKit cancels the touch on the starting key, so its letter is not typed.
- The word has no space behind it, so punctuation can attach. The next letter or swipe adds the space, and one press of delete removes the word but keeps a space before it. The suggestion bar shows the other readings of the path, and tapping one replaces the word.
- `CombinedWordList` memory-maps the `.combined` file and keeps only positions of words with frequency 30 or more, between about 86,000 and 200,000 words, depending on the language. The file is sorted by frequency, so the scan ends early and the rest of the file is never read. Offensive words, abbreviations with periods and hyphenated words stay out. An apostrophe, as in c'est, does not count as a key.
- `SwipeDecoder` runs in the `SwipeTypingEngine` actor. It only looks at words whose first and last letters are near the path's ends, requires every letter to be passed in order, then scores the path's shape, how close it passes each key, the word's frequency and whether the list expects it after the previous word.
- Words with the same path, such as "Halo" and "Hallo", are decided by frequency alone. The list comes from web and news text, so everyday words can lose. That is what the suggestion bar is for.

- Personal words with "for keyboard suggestions" on can be swiped too, which needs full access.
- Unknown words are counted on the device in `WordLearningStore`, which is never synced. A word goes into the personal dictionary once the same swiped word was corrected the same way twice, or once it was typed letter by letter three times. A correction is a swiped word that is deleted and replaced, or extended, as with geht to geht's; it is marked `learnedFromCorrection`. A typed word counts only when typed from its first letter, without a suggestion, and ended by a space, punctuation, return, a swipe or sending; it is marked `learnedFromTyping`. Both counts are separate. It takes full access, no email or URL field, only letters and apostrophes, 2 to 32 characters, a word that is neither in the list nor already in the dictionary, and for a replacement a word that fits the original path. Counts expire after 30 days, at most 500 words are kept, and the privacy screen can delete them.
- A capital that is only there because a sentence starts is removed before saving.

Tests measure accuracy on synthetic strokes. They guard against regressions, and say little about how swiping feels. Tune it on a real iPhone.

## Keeping the main thread free

- The system spell checker has to run on the main actor. It starts only after a 200 ms typing pause and is rescheduled only by keystrokes. Correction suggestions run only with fewer than two completions, and repeat lookups are cached.
- File access, the personal dictionary, sorting and assembling suggestions run in their own actor. After computing, document, text, selection, language and full access are checked again, and outdated results are dropped.
- Characters go directly through the document proxy. The suggestion bar changes height only when its visibility changes.
- The 350 ms refresh reads session state and pending transcriptions off the main thread, so file locks shared with the app cannot hold up touches. At most one further read is queued.
- The keyboard's heartbeat is written every 1.5 seconds, and the app accepts it for 3 seconds. Freshness is computed inside the same file lock as the read, so a heartbeat written during the wait cannot look like a future state.
- One-time requests and claiming a transcription stay synchronous on the main thread, because they must be settled right before opening or inserting.

## Diagnostics

Debug builds log only screen zones and durations through `KeyboardTouchDiagnostics`, never characters or words. The summary appears every 50 touches and when the keyboard hides, in Console under subsystem `one.binda.flype.keyboard`. `refresh` and `spelling` also show up as signposts in Instruments. Layout diagnostics are off by default and turned on through `keyboardLayoutDiagnostics` in shared settings.

Geometry tests cover gaps, uneven function keys, keyboard edges, invalid geometry and full grid coverage. Real typing speed and overlapping thumbs have to be tested on an iPhone, because core tests do not simulate UIKit touches.

## Links and start requests

Tapping the microphone link writes its matching, still valid one-time request again. Regular refreshes may not replace it until it is confirmed or the start wait expires. That keeps the link, the start and the return target on one request. If the write fails, the link does not open.

The keyboard uses `one.binda.flype://dictate` and `one.binda.flype://review`, which reliably open the current app even if an old development install (`de.flype.app`) still registers `flype://`. The old scheme stays registered for existing links and OAuth.

## Layout

- The language menu is the native long-press menu on the space bar. A short tap types a space, and a double tap keeps the period rule. The menu stays stable between unchanged refreshes and locks during preparation, recording and processing.
- The microphone sits left of the space bar.
- On iPhone the symbol view follows Apple's keyboard, checked key by key on iOS 27.2: an apostrophe always leads back to the letters, a space or return does once something was typed in the symbol view, and every other symbol stays. Deleting or switching between the two symbol pages does not reset that. iPad keeps its own behavior, where the space leads back.
- The iPhone key area is 216 points without and 262 points with suggestions, with 10 points between the four rows. iPad has its own layout.
