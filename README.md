# Flype

Speak, then keep typing, on iPhone, iPad and Mac. Speech is recognized on the device. An optional account syncs personal words and settings, and optional cloud cleanup is off by default.

This repository holds every platform, the website and the backend.

```text
flype/
├── ios/           iPhone and iPad: app, keyboard extension, Xcode project
├── macos/         Mac: app, entitlements, build and signing scripts
├── website/       Static website in German and English
├── shared/        Everything used by more than one platform
│   ├── FlypeCore/     Swift package: data models, dictionary, sync, tests
│   ├── FlypeSpeech/   Swift package: speech recognition runtime
│   ├── App/           SwiftUI views and services used by both apps
│   ├── Resources/     App icons, translations, privacy manifest
│   └── Config/        Signing and model manifest, no secrets
├── supabase/      Backend: migrations, Edge Functions, tests
├── vendor/        Pinned third-party sources with license and provenance
├── scripts/       Checks and tools for the whole repository
├── docs/          Product and engineering notes
└── Package.swift  Builds the Mac app
```

## Getting started

| Area | Start | Docs |
| --- | --- | --- |
| iOS | `open ios/Flype.xcodeproj` | [ios/README.md](ios/README.md) |
| Mac | `./macos/scripts/build.sh` | [macos/README.md](macos/README.md) |
| Website | `python3 -m http.server 4173 --directory website` | [website/README.md](website/README.md) |

You need macOS 26 on Apple silicon and Xcode 26.2 or later. The backend tests also need Node.js, and the database tests need Docker.

```sh
./scripts/check.sh           # lint, backend, core tests, iOS and Mac builds
./scripts/check.sh core      # one area: lint, backend, core, ios, macos, database
```

## Docs

- [Account and sync](docs/ACCOUNT-AND-SYNC.md)
- [Design and languages](docs/DESIGN-AND-LANGUAGES.md)
- [Recording start](docs/RECORDING-START.md)
- [Text cleanup](docs/TEXT-CLEANUP.md)
- [Flype Pro](docs/BILLING.md)
- [Dictionary correction](docs/DICTIONARY-CORRECTION.md)
- [Fast keyboard input](docs/ios/TYPING-INPUT.md)
- [App Store submission](docs/ios/APP-STORE.md)

See [CONTRIBUTING.md](CONTRIBUTING.md) for where things belong and how to check a change.
