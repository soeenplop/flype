# Flype website

The website for Flype on iPhone, iPad and Mac, in German and English. It is static, with no build step, cookies or third-party embeds. The apps live in [`ios/`](../ios/README.md) and [`macos/`](../macos/README.md).

```sh
python3 -m http.server 4173 --directory website
```

Every push to `main` that changes `website/` deploys the site to GitHub Pages through [`.github/workflows/pages.yml`](../.github/workflows/pages.yml): <https://soeenplop.github.io/flype/>. `README.md` is not published.

| German | English | Purpose | App Store Connect |
| --- | --- | --- | --- |
| `index.html` | `en/index.html` | Product page with images | Marketing URL (optional) |
| `datenschutz.html` | `en/privacy.html` | Privacy policy (German is authoritative) | Privacy URL (required) |
| `support.html` | `en/support.html` | Setup, problems, account deletion, contact | Support URL (required) |
| `impressum.html` | `en/imprint.html` | Legal notice (German is authoritative) | |

Each language is its own file, so always change both. Navigation for both languages is in `assets/site.js`. The privacy pages are the only copy of the privacy policy.

## Before publishing

1. Fill every highlighted placeholder (`class="todo"`) in `datenschutz.html` and `en/privacy.html`: OpenAI contracting party, Supabase region, data transfers, hosting.
2. Get the privacy policy and legal notice reviewed. Add the VAT ID to the legal notice if there is one.
3. Add the price to the FAQ in both `index.html` files.
4. At launch, update the availability note in the hero and the download answer in the FAQ in both languages, and add real download links.
5. Once hosted, put the addresses in `shared/FlypeCore/Sources/FlypeCore/FlypeLinks.swift` and App Store Connect.

## Screenshots

`assets/shots/` holds real captures: iPhone and iPad from the simulator (iOS 27.2) with sample words, and the Mac app as a cropped window. All show the German interface. The recording views are recreated, because the simulator does not start the microphone.

## Design

The page keeps the purple gradient and dark content sections. It explains iPhone, iPad and Mac with text and static images, without interactive demos. Only the mobile menu needs JavaScript, and the navigation links stay visible without it.

The keyboard shown in the hero is HTML and CSS labeled as an example view, not a screenshot of another app. Help pages have jump links, and every page has a skip link. The menu supports Escape and keyboard use. Availability and requirements are stated in text, without download buttons for things that are not available yet.
