# FluidAudio source provenance

Upstream: https://github.com/FluidInference/FluidAudio
Version: 0.18.2
Commit: e396cf780c4abf8e395087467c0585d3b0d17f68
License: Apache-2.0 (LICENSE included; original source headers retained).

Sources are unchanged from this commit. Flype uses a source-only Swift package
manifest with ASR/VAD, FastClusterWrapper and MachTaskSelfWrapper. The optional
TTS, Diarizer and NemoTextProcessing traits are disabled. The unused NeMo Rust
binary target was removed from the manifest because SwiftPM/Xcode attempted its
artifact resolution even with all optional traits disabled and stalled. No ASR
logic or model weights were modified. Update this provenance and re-run the
pinned model/device checks before upgrading.
