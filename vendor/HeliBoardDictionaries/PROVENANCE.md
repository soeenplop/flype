# HeliBoard word list provenance

Upstream: https://codeberg.org/Helium314/aosp-dictionaries
Repository commit: ff0cd52be8d9530200fefe8b296c53d4f662091e

| File here | Upstream file in `wordlists/` | List date | SHA-256 |
| --- | --- | --- | --- |
| `main_de.combined` | `main_de.combined` | 2023-09-25 | `873f0c90e104c574609d8da6a938e4a7c951d53e20cddc1b66301d4d37752b6d` |
| `main_en.combined` | `main_en_US__experimental.combined` | 2024-01-02 | `466c2eb4737fa1a9453e5f4a33337db8dd703f75012b70c2534490fd189c9487` |
| `main_fr.combined` | `main_fr__experimental.combined` | 2023-09-09 | `296d5ae8b1b697092e941af284de454695db1f949c589af8b7ffa71936e3d004` |
| `main_it.combined` | `main_it__experimental.combined` | 2023-09-09 | `50e0c819848e5d7b527dfcb0d21ca85fef3e90d99bd0f5f1d2435cacfa48301d` |
| `main_es.combined` | `main_es__experimental.combined` | 2023-09-09 | `786717cf9ca7a69f6b0bf297f8dbdc24a71e21820462f014e11aa2c8a62d3a97` |
| `main_nl.combined` | `main_nl__experimental.combined` | 2026-06-13 | `ff3200da0b873cb70b84a15b34c5af522f72803905f3af2c9a1c27837d977068` |

The contents are unchanged. Only the names differ, so the keyboard can find a list by language as
`main_<language>.combined`. Flype reads the files directly in the keyboard.

## License

Not settled. Clear this before a release.

- The upstream table and each list's `.source` file say: "source lists under CC BY 4.0", built from the word lists at
  https://wortschatz.uni-leipzig.de/en/download/ with the upstream `scripts/wordlist.py` and
  `scripts/wordlist_combined.py`.
- The upstream repository's root `LICENSE` file is GPL-3.0. Neither text says whether it also covers the generated
  word lists, so that needs an answer from upstream.
- CC BY needs visible attribution. Flype does not show any yet.
