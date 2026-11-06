# Flype for Mac

Hold a key, speak, let go: the text lands in the active text field. The right Command key is the default, and you can choose another in Settings. Regular keyboard shortcuts keep working.

## Build and check

```sh
./macos/scripts/build.sh
./scripts/check.sh macos
```

You need Apple silicon, macOS 26 or later and Xcode 26.2 or later. The `Package.swift` at the repository root builds the app, because SwiftPM only compiles sources inside the package folder and `shared/App` is also used by the iOS project. `macos/App` holds only Mac-specific code.

Normal builds write `build/macos/Flype.app` and sign it with a development certificate from the team in `shared/Config/Signing.json`. Certificates from other teams are rejected. To pick one explicitly:

```sh
FLYPE_SIGN_IDENTITY='Apple Development: ...' ./macos/scripts/build.sh
```

Automated checks use a local ad-hoc signature and write to `build/check/macos/Flype.app`. They never replace the signed app, because an ad-hoc signature there would void its Accessibility permission.

## Using it

Open the app and allow the microphone and Accessibility during setup. Hold the microphone key in any text field, speak and release. A very short press starts no recording. Flype inserts into any focused field, including browsers and Electron apps. If you switch app or window while recording, or the field is a protected password field, Flype does not insert and keeps the last text ready to copy. Recordings last at most two minutes, and locking the Mac or sleep cancels them.

## Local data

- Active dictionary: `~/Library/Application Support/Flype/Dictionary/`
- Dictionary states per account: `~/Library/Application Support/Flype/Account/`
- Speech model: `~/Library/Application Support/FlypeModels/`
- Sign-in session: macOS Keychain, service `one.binda.flype.account`

Local conflict backups hold earlier dictionary states, never audio or transcriptions.

## Distribution

The Mac app is planned as a signed, notarized direct download. `./macos/scripts/build_appstore.sh` builds a sandboxed prototype in `build/AppStore`, where ⌃⌥Space starts a transcription and the text goes to the clipboard. Automatic insertion needs Accessibility, which the sandbox does not allow. It is not a planned distribution channel.
