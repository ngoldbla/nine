# Store screenshots — designed set (Nine 1.3 imagery)

The advertising screenshots for the next App Store update: captioned slides
built in the editor in `store-screenshots/`, one folder per App Store Connect
locale. Unlike `screenshots/ios/`, which `store_screenshots_capture` empties and
refills with plain simulator frames, this folder is committed and only changes
when `store-screenshots/scripts/publish.py` rewrites it.

| Files | Display | Size |
|---|---|---|
| `01-iphone-hero.jpg` … `09-iphone-closer.jpg` | 6.9" iPhone (`APP_IPHONE_67`) | 1320×2868 |
| `21-duo-*.jpg` | iPhone Duo, open (`APP_IPHONE_DUO`) | 2853×2007 |

JPEG at quality 92 rather than PNG (App Store Connect takes both): the PNGs
are ~1.4 MB a slide, and this repository's history cannot be rewritten to drop
them later. App Store Connect scales the 6.9" set to the smaller iPhones.

## The slides

| # | Feature | en-US headline |
|---|---|---|
| 01 | The board | Sudoku, made **beautiful**. |
| 02 | Coaching | You've got **this**. |
| 03 | Classic, Thermo, Killer | Three ways to **play**. |
| 04 | Ten accent colours | Make it **yours**. |
| 05 | iPhone, iPad, Mac, Apple TV, Watch | At home on **every** screen. |
| 06 | SharePlay on FaceTime | Solve it **together**. |
| 07 | Game Center achievements | Celebrate every **win**. |
| 08 | Ten languages | Speaks **your** language. |
| 09 | Everything, as a list | Everything you'll **love**. |
| 21 | Duo: the board | Sudoku, made **beautiful**. |
| 22 | Duo: coaching *(en-US only)* | You've got **this**. |
| 23 | Duo: folded and open | One board, **both** screens. |
| 24 | Duo: Technique School *(en-US only)* | Learn every **technique**. |

Copy for all ten languages is in `store-screenshots/copy/store-copy.json`.

## What is and is not localised

- **iPhone (01–09):** every app screen was captured in that language, except
  slide 05's Mac, Apple TV and Watch, which are the English captures
  (nearly all digits) and slide 07's Game Center badges (no text).
- **Duo (21–24):** headlines are localised; the screens are the English
  captures in `screenshots/ios-duo/`, because no tool can unfold the Duo
  simulator. So 22 and 24, whose screens are English text, ship for en-US only,
  and the Duo frames still show mistake marking (a red 7). Reshoot with the
  posture set to Open and re-run the pipeline below to fix both.
- The Duo board header ("Steady") and Japanese/German home screens on slide 08
  are real app text in the app's own translations.

## Not here yet

- iPad 13" and Apple Watch sets, which `store_check` requires for iOS.
- Store listing text for the nine other locales: `metadata/` has en-US only.
- Uploading: nothing points deliver at this folder yet. Either upload these by
  hand in App Store Connect, or add `marketing` to `COMMITTED_SHOT_DIRS` in the
  Fastfile in place of the plain `ios` capture (and drop `ios-duo`, whose
  frames these replace).

## Rebuilding

From `store-screenshots/` (see its `STORE-ART.md`):

```bash
python3 scripts/capture-iphone.py /tmp/shots         # ~35 min, all ten languages
zsh scripts/place-captures.sh /tmp/shots
python3 scripts/build-decks.py --device iphone        # then export in the editor
python3 scripts/publish.py <iphone.zip> <duo.zip>
```
