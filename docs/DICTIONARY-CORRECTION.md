# Dictionary correction

An active dictionary entry with "Use in transcription" is enough for Flype to correct a name it misheard. "Replace variants automatically" only controls fixed replacements someone asked for explicitly. All settings and entries are frozen when recording starts.

## How it works

1. The selected main recognizer (Apple SpeechTranscriber or Parakeet v3) produces the raw text, which is kept for comparison.
2. Explicit variant replacements run, if turned on.
3. Flype looks for complete words or terms in the dictionary that sound similar. Short sound keys need an equal sound approximation. From five sound characters on, one different sound is allowed if the start matches. This is a limited heuristic for German and some English spellings, not universal pronunciation recognition.
4. German function words and common words are protected. On iOS, at least one word in a candidate span must be unknown to the local spell checker. URLs, email addresses and numbers are excluded. Limits: 12 candidates, 4 words per term, 5,000 UTF-8 bytes of input.
5. Apple's `DictationTranscriber` listens to the same local audio file again with the candidates as `AnalysisContext.contextualStrings`. It acts only as a checker and does not supply replacement text. Its result must fully align with the original through the proposed replacements. Other words, missing negations or changed numbers lead to rejection. Punctuation may differ, and the original form stays.
6. If the local FoundationModels model supports the language, it checks whether the replacement fits the sentence. Second recognitions that only match by sound must get this confirmation. Without the model, only exact spelling confirmations from the second recognizer are accepted. The model returns only candidate IDs and cannot write its own text.
7. Confirmed spans are replaced once, from back to front. Overlapping or ambiguous decisions are dropped. Cleaned mode then runs its separate [cleanup](TEXT-CLEANUP.md), and Verbatim ends here.

Changes that only affect capitalization need no second audio pass.

## Why not FluidAudio's CTC model

FluidAudio's custom vocabulary needs an extra CTC encoder for Parakeet TDT 0.6B v3. The 110M model is listed as English on its model card, so German quality is unproven, and FluidAudio documents false replacements with short brand names. Apple's `DictationTranscriber` explicitly supports German and avoids bundling another Core ML model.

- <https://huggingface.co/FluidInference/parakeet-ctc-110m-coreml>
- <https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/CustomVocabulary.md>
- <https://developer.apple.com/documentation/speech/dictationtranscriber>
- <https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings>

The second recognition gives no calibrated probabilities per candidate, and the context decision is heuristic. The method does not guarantee perfect name recognition.

## Lifecycle, failures and privacy

No recording is uploaded. The check keeps the temporary recording a little longer and deletes it afterwards as usual. The model receives only text. No pronunciation profile is stored, no model is trained, and candidates never become dictionary entries on their own.

An eight-second limit ends the check and keeps the recognized text. Late results are rejected through the job ID and phase. Cancelling ends the matching `SpeechAnalyzer`. Failures and missing models leave the recognized text unchanged.
