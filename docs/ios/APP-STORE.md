# App Store submission

**Decision from November 3, 2026:** The iOS app goes to the App Store. The Mac app does not go to the Mac App Store. It ships as a Developer ID signed and notarized direct download, with a freely chosen microphone key and automatic insertion. The sandboxed variant (`macos/Flype-AppStore.entitlements`, `macos/scripts/build_appstore.sh`) is only a prototype.

Checked on November 4, 2026 against the [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (last changed October 16, 2026).

## How the rules are met

| Rule | Implementation |
| --- | --- |
| 2.5.14 Recording only with consent and indication | Starts only through user action, with status in keyboard and app and the orange dot. |
| 4.2.3 (ii) Download after notice | The setup step names 632 MB and asks before downloading. |
| 4.4.1 Switch to the next keyboard | Own globe key when `needsInputModeSwitchKey` requires it. Otherwise iOS shows the globe below the keyboard. |
| 4.4.1 Usable without Full Access | Typing works. The language then follows the device, because the App Group is out of reach. |
| 4.8 Login services | Sign in with Apple is offered equally next to Google. |
| 5.1.1 (i) Privacy in the app | "Deine Privatsphäre" screen. The link appears once `FlypeLinks.privacyPolicy` is set. |
| 5.1.1 (v) Account deletion | "Konto löschen" under "Dein Konto", including revoking the Apple token. |
| 5.1.2 (i) Sharing with third-party AI | Cloud cleanup is off, needs an account and a dialog naming OpenAI, the data and the purpose. The switch is per device and can be turned off at any time. |
| Privacy manifest | `shared/Resources/PrivacyInfo.xcprivacy` in app, keyboard and Mac app. |
| Export compliance | `ITSAppUsesNonExemptEncryption = false`. The app only uses HTTPS and hashes. |
| Private APIs | `PreviousAppReturn` and KeyboardKitHostPlugin are Debug only and absent from Release binaries. |

## Before you can submit

Done: migrations and Edge Functions (`revoke-apple-token`, `cloud-cleanup`) are live. The secrets `APPLE_CLIENT_ID`, `APPLE_CLIENT_SECRET` and `OPENAI_API_KEY` are set.

1. **Privacy policy:** Execute OpenAI's data processing agreement and confirm that the Supabase and OpenAI accounts belong to binda UG. Get `website/datenschutz.html` and `website/en/privacy.html` reviewed, including OpenAI's retention of up to 30 days.
2. **Public pages:** Publish the privacy and support pages and enter their addresses in `shared/FlypeCore/Sources/FlypeCore/FlypeLinks.swift`. Both are still `nil`.
3. **Spending limit:** Set it in the OpenAI project.
4. **Test Apple sign-in:** With a real Apple account, check that Supabase returns `provider_refresh_token` and that revoking works on deletion.
5. **Device tests in a Release build:** Parakeet in the background, the offline fallback, field text from the keyboard and the Siri button, on iOS 26 and 27. Test numbers, negations and spoken questions with both models, because the model's answer is inserted unreviewed.
6. **Archive iOS:** Product > Archive in Xcode, then Distribute App, TestFlight first. This Mac still lacks the "Apple Distribution" certificate, and automatic signing creates it. Current version: 1.0.0 (1).
7. **App Store Connect:** Create the app record and enter the texts, screenshots and the details below.

For the Mac download, also create a "Developer ID Application" certificate and build the release flow with hardened runtime, distribution signing, notarization and a download package. `macos/scripts/sign.py` still uses the development certificate.

Ongoing: `APPLE_CLIENT_SECRET` is a JWT valid for at most six months and must be renewed in time.

## Review risks

- **Rule 4.4.1 "Launch other apps besides Settings":** The keyboard's microphone opens Flype, because a keyboard extension may not record. This is the biggest rejection risk. The review notes explain it, but a rejection remains possible. Recording would then have to start from the app.
- **Rule 4.4.1 "Collect user activity only to enhance the functionality":** When a transcription starts, the keyboard reads up to 200 characters before the cursor. This only continues the started sentence, and the notes say so openly.
- **Rule 5.1.2 (i) Third-party AI:** The dialog appears only after signing in and turning it on. Reviewers have to find it, so the notes give the path.
- **Rule 2.5.4 Background modes:** Background audio serves the running recording and the standby between transcriptions. Use the notes below if asked.

## Review notes (draft)

> Flype is a keyboard with on-device speech recognition. No account is needed to test it.
>
> To test: open Flype and download the Parakeet speech model (632 MB, Wi-Fi recommended) or choose Apple speech recognition. Follow the setup to add the Flype keyboard and allow Full Access. Open any text field, switch to Flype and tap the microphone key.
>
> Why the keyboard opens the app: iOS does not allow keyboard extensions to use the microphone. The microphone key therefore opens the Flype app once to start the recording session, which runs in the main app with the audio background mode. The user then returns to their app and stops the recording in the keyboard. The app is never opened without the user tapping the microphone key, and typing works without it and without Full Access.
>
> Background audio: the microphone stays active between transcriptions only after the user started it. iOS shows the orange indicator, and the session ends on device lock, after five idle minutes or through a button in the app. No audio is stored between transcriptions and no audio leaves the device.
>
> Full Access is used to hand transcribed text from the app to the keyboard and to read the personal dictionary. When a transcription starts, the keyboard also passes up to 200 characters before the cursor to the app, so the text can continue a sentence the user started typing. This text is deleted after the transcription. Other keystrokes are not stored or transmitted.
>
> Optional cloud cleanup: by default, cleanup runs on the device with Apple's language model. To test the cloud option, sign in under Dein Konto, then open Einstellungen and turn on „Mit OpenAI in der Cloud bereinigen“ in the Dein Schreibstil section. A dialog names OpenAI and the data sent and asks for permission first. When on, the transcribed text, up to 200 characters before the cursor and matching terms from the personal dictionary go through our Supabase function to OpenAI. Recordings are never sent. If the service is unavailable, the app uses the on-device model.
>
> Account deletion: Dein Konto > Konto löschen.

## Privacy details in App Store Connect

This is a proposal and must be confirmed before submitting, especially the last row.

| Data type | Linked | Tracking | Purpose |
| --- | --- | --- | --- |
| Email address | yes | no | App functionality |
| User ID | yes | no | App functionality |
| Other user content (dictionary, settings) | yes | no | App functionality |
| Usage data (number of requests and characters for the limit) | yes | no | App functionality |
| Other user content (transcribed text and field text with cloud cleanup on) | no, OpenAI gets no user ID | no | App functionality |

Audio is not listed, because it does not leave the device. Flype does not store transcribed text, but OpenAI says it keeps it for up to 30 days for abuse detection, so it counts as collected here. Without an account, no data is collected. `shared/Resources/PrivacyInfo.xcprivacy` lists the same data types and must change along with any different classification.

## Store listing (draft, German)

The German listing stays in German, because that is how it will appear in the store.

**Name:** Flype
**Subtitle:** Tastatur mit lokaler Transkription
**Category:** Productivity
**Age rating:** 4+
**Keywords:** Transkription,Tastatur,Sprache zu Text,Spracherkennung,Schreiben,Offline,Wörterbuch,Datenschutz

**Description:**

> Schreib, wie du sprichst. Flype ist eine Tastatur, die deine Stimme direkt dort in Text verwandelt, wo du gerade schreibst.
>
> Deine Stimme bleibt auf deinem Gerät. Aufnahmen werden lokal erkannt und nie an Server gesendet.
>
> - Mikrofon antippen, sprechen, stoppen: Der Text steht im Textfeld.
> - Parakeet oder Apple-Spracherkennung, beide lokal
> - Bereinigung auf Wunsch: setzt Satzzeichen, lässt Füllwörter weg und führt angefangene Sätze fort
> - Die Bereinigung läuft auf dem Gerät. Optional und nur nach deiner Zustimmung kann sie mit Konto über OpenAI laufen; dann wird der Text dorthin übertragen.
> - Persönliches Wörterbuch für Namen und Fachbegriffe
> - Vertraute Tastatur mit Wortvorschlägen und Umlauten
> - Deutsch, Englisch, Französisch, Italienisch, Spanisch und Niederländisch
> - Optionales Konto, um Wörter und Einstellungen zwischen iPhone, iPad und Mac abzugleichen

**Screenshots:** iPhone 6.9" and iPad 13", taken in the simulators with real sample texts.
