# Contributing

## Where things belong

- Used by one platform only: `ios/`, `macos/` or `website/`.
- Used by both apps: `shared/`. Never copy files between platforms. See [shared/README.md](shared/README.md).
- Small platform differences in shared code can use `#if os(iOS)`. Anything larger belongs in the platform folder.
- Backend: `supabase/`. Third-party code: `vendor/`, and only change it together with its version, provenance and license.
- Do not commit model weights, app bundles or secrets.

New or deleted Swift files in `ios/App`, `ios/Keyboard` or `shared/App` need `python3 scripts/generate_project.py` so the Xcode project knows about them.

## Naming

Code says `dictation`, matching Apple's own terms such as `DictationTranscriber` and `hasDictationKey`. Text people read says transcription, and the key that starts recording is the microphone key.

Stored names cannot change without a migration: the JSON and settings keys (`dictationMode`, `dictationLanguage`, `dictationKey`, `useForDictation`), which the live database enforces, and the `one.binda.flype://dictate` link. Add a new migration rather than editing one in `supabase/migrations/`.

## Checks

| Changed | Check |
| --- | --- |
| `shared/` | `./scripts/check.sh` (affects both apps) |
| `ios/` | `./scripts/check.sh ios` |
| `macos/` | `./scripts/check.sh macos` |
| `supabase/` | `./scripts/check.sh backend`, for SQL also `./scripts/check.sh database` |
| `website/` | Look at it on phone and desktop, in both languages |

`git config core.hooksPath .githooks` runs the full check before each commit. GitHub Actions does not run these checks. A template is in [scripts/ci-template.yml](scripts/ci-template.yml). To turn it on, move it to `.github/workflows/ci.yml`. Changing workflows needs the `workflow` scope on your Git credentials.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/) with the area as scope: `ios`, `keyboard`, `macos`, `website`, `core`, `speech`, `app`, `backend`, `vendor`, `docs`, `build`, `ci`.

```text
feat(keyboard): add long-press alternates
fix(macos): keep focus while inserting text
docs(website): explain offline transcription
```

A commit holds one complete change with its tests. Commit third-party changes separately from Flype changes.
