# Unicode emoji list provenance

Upstream: https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt
Version: Emoji 17.0, dated 2025-08-04
SHA-256: `1d8a944f88d7952f7ef7c5167fef3c67995bcae24543949710231b03a201acda`

The file is unchanged. `scripts/generate_emoji.py` reads it and writes `ios/Keyboard/EmojiCatalog+Data.swift`, which the
keyboard's emoji pages use. Run the script again after replacing the file with a newer version.

## License

Unicode License v3, in `LICENSE.txt` (from https://www.unicode.org/license.txt). It allows use, copying and
distribution, provided the copyright and permission notice stays with the data.
