# Recording start

The first words must not get lost, so recording starts before anything slow happens.

**Mac:** Recording starts as soon as the microphone key goes down (`armed`). The 140 ms hold window then only confirms the transcription and the on-screen indicator. Short presses and key combinations cancel the prepared recording, and its file is deleted without being transcribed. Recording starts before Flype reads the target field through Accessibility and before it touches the dictionary. Releasing after a confirmed hold ends the audio immediately. The speech model may still finish loading afterwards.

**iOS:** Recording starts after microphone permission and before the dictionary and speech model are prepared. Preparation is its own cancellable task. Stopping during loading closes the audio segment, and recognition then waits for the model. The return to the writing app can happen during model preparation. Cancelling or ending the session also revokes preparation, and operation IDs stop an old preparation from changing a new recording.

Recording still begins only after an explicit key press. Turning on the audio input takes extra time depending on device and route. Core tests cover immediate arming, hold confirmation, discarding short or interrupted presses and ending exactly once. Hardware latency and whether the first spoken words are complete have to be checked with a real microphone.

The Mac app keeps the recognized original in memory only and offers "Compare original". This shows whether something was already missing after recognition or got lost during cleanup. If cleanup looks unsafe, for example changed numbers or a much shorter sentence, Flype inserts the full text from before cleanup. A change from spelled-out numbers to digits alone can conservatively trigger this fallback.
