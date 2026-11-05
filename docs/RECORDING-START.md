# Recording start

The first words must not get lost, so recording starts before anything slow happens.

**Mac:** Recording starts as soon as the microphone key goes down (`armed`). The 140 ms hold window then only confirms the transcription and the on-screen indicator. Short presses and key combinations cancel the prepared recording, and its file is deleted without being transcribed. Recording starts before Flype reads the target field through Accessibility and before it touches the dictionary. Releasing after a confirmed hold ends the audio immediately. The speech model may still finish loading afterwards.

**iOS:** Recording starts after microphone permission and before the dictionary and speech model are prepared. Preparation is its own cancellable task. Stopping during loading closes the audio segment, and recognition then waits for the model. The return to the writing app can happen during model preparation. Cancelling or ending the session also revokes preparation, and operation IDs stop an old preparation from changing a new recording.

## Cancelling

Cancelling always means the same thing: nothing is inserted and the recording is deleted. It needs no confirmation and shows no message, the indicator simply disappears. There is no undo, because the audio is deleted right away. VoiceOver alone announces it, since it would otherwise get no feedback.

**Mac:** The round button in the floating indicator cancels the recording and the processing, as do Esc and the menu bar. The circle on the left only shows the level. While the indicator offers cancelling, Esc stays away from the app in front. Typing after release still only keeps the text in Flype instead of inserting it.

**iOS:** Cancel in the keyboard's recording view is a command of its own. It discards this transcription and keeps the microphone ready, so the next one needs no app switch. It outranks an unprocessed stop, and the keyboard ignores the status and any result of a cancelled ID, because the app can publish a result before it reads the command. Only "Mikrofon ausschalten" in the app ends the standby.

Cancelling ends just before text reaches another app. On Mac the button then disappears, because a sent paste cannot be taken back. A cancelled cloud cleanup only drops the answer: the text may already have reached OpenAI, and the server counts the request first. A running model step finishes before the work really stops, and a new recording waits for that instead of failing.

## Hardware

Recording still begins only after an explicit key press. Turning on the audio input takes extra time depending on device and route. Core tests cover immediate arming, hold confirmation, discarding short or interrupted presses and ending exactly once. Hardware latency and whether the first spoken words are complete have to be checked with a real microphone.

The Mac app keeps the recognized original in memory only and offers "Compare original". This shows whether something was already missing after recognition or got lost during cleanup. If cleanup looks unsafe, for example changed numbers or a much shorter sentence, Flype inserts the full text from before cleanup. A change from spelled-out numbers to digits alone can conservatively trigger this fallback.
