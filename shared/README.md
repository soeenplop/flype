# Shared code

| Folder | Kind | Used by |
| --- | --- | --- |
| `FlypeCore/` | Swift package with tests; platform-neutral logic | iOS app, keyboard, Mac app |
| `FlypeSpeech/` | Swift package; Parakeet through `vendor/FluidAudio` | iOS app, Mac app, not the keyboard |
| `App/` | Source files compiled directly into both app targets | iOS app, Mac app, not the keyboard |
| `Resources/` | App icons, translations, privacy manifest | iOS app, Mac app |
| `Config/` | Team, bundle IDs, model manifest; no secrets | Build scripts |

`App/` is deliberately not a package. Its views and services are internal to the apps and should not become a public API. Testable logic belongs in `FlypeCore/`.

The keyboard links only `FlypeCore` on purpose. The speech model and cloud sign-in stay in the main app.
