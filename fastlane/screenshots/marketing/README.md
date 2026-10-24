# Store screenshots — designed set (Nine 1.3 imagery)

The iOS App Store screenshots: captioned slides built in the editor in
`store-screenshots/`, one folder per App Store Connect locale. This is what
deliver uploads for iOS (`STORE_SHOT_DIRS` in the Fastfile); the plain frames
`store_screenshots_capture` leaves in `screenshots/ios/` no longer go up. The
folder is committed and only changes when `store-screenshots/scripts/publish.py`
rewrites it.

| Files | Display | Size |
|---|---|---|
| `01-iphone-hero.jpg` … `09-iphone-closer.jpg` | 6.9" iPhone (`APP_IPHONE_67`) | 1320×2868 |
| `11-ipad-hero.jpg` … `19-ipad-closer.jpg` | 13" iPad (`APP_IPAD_PRO_3GEN_129`) | 2064×2752 |
| `21-duo-hero.jpg` … `24-duo-school.jpg` | iPhone Duo, open (`APP_IPHONE_DUO`) | 2853×2007 |
| `31-watch-hero.jpg` … `34-watch-home.jpg` | Apple Watch Ultra (`APP_WATCH_ULTRA`) | 422×514 |

JPEG at quality 92 rather than PNG (App Store Connect takes both): the PNGs
are ~1.4 MB a slide, and this repository's history cannot be rewritten to drop
them later. App Store Connect scales each set to the smaller sizes of its display.

## The slides

| # | Feature | en-US headline |
|---|---|---|
| 01 / 11 | The board | Sudoku, made **beautiful**. |
| 02 / 12 | Coaching | You've got **this**. |
| 03 / 13 | Classic, Thermo, Killer | Three ways to **play**. |
| 04 / 14 | Ten accent colours | Make it **yours**. |
| 05 / 15 | iPhone, iPad, Mac, Apple TV, Watch | At home on **every** screen. |
| 06 / 16 | SharePlay on FaceTime | Solve it **together**. |
| 07 / 17 | Game Center achievements | Celebrate every **win**. |
| 08 / 18 | Ten languages | Speaks **your** language. |
| 09 / 19 | Everything, as a list | Everything you'll **love**. |
| 21 | Duo: the board | Sudoku, made **beautiful**. |
| 22 | Duo: coaching | You've got **this**. |
| 23 | Duo: folded and open | One board, **both** screens. |
| 24 | Duo: Technique School | Learn every **technique**. |
| 31 | Watch: the board | Sudoku on your **wrist**. |
| 32 | Watch: one box under the lens | One box at a **time**. |
| 33 | Watch: solved | Celebrate every **win**. |
| 34 | Watch: home | Pick up **anytime**. |

The iPad tells the iPhone's story in iPad captures (`11`–`19` reuse the iPhone
copy). Copy for all ten languages is in `store-screenshots/copy/store-copy.json`.

## What is and is not localised

- **iPhone and iPad:** every app screen was captured in that language, except
  the Mac, Apple TV and Watch on the devices slide, which are the English
  captures (nearly all digits), and the Game Center badges (no text). The
  iPhone languages slide shows the locale's home screen in front of another
  language's; the iPad's shows each one's Technique School, because the iPad
  shelf is mostly empty glass.
- **Duo:** the open frames were captured in each language with mistake marking
  off. The folded board on slide 23 is the committed English frame in
  `screenshots/ios-duo/` (it shows no text).
- **Watch:** every frame in its language; the watch clock is the real time,
  because `simctl status_bar` does nothing on watchOS.

## Rebuilding

See `store-screenshots/STORE-ART.md`. In short: capture with
`capture-ios.py` (iPhone, then `--device ipad`), `capture-watch.py` and
`capture-duo.py`, file each with `place-captures.sh`, export each deck from the
editor, then

```bash
python3 scripts/publish.py --iphone <zip> --ipad <zip> --watch <zip> --duo <zip>
```

Any one device can be republished alone.
