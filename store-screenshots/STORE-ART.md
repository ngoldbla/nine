# Nine's store screenshots

This folder is the screenshot editor from the `app-store-screenshots` skill
(Next.js; `README.md` is the template's own guide), set up for Nine. It renders
the captioned slides committed in `../fastlane/screenshots/marketing/`.

## Look

"Pixels under glass", Nine's own art direction: near-black with a soft blue
spotlight, SF Pro headlines at weight 600, one word per headline in the
glacier accent, and real app captures in Apple's device frames. Theme
`nine-glass` in `src/lib/constants.ts`; `*word*` in a headline marks the
emphasised word (`paintText` in `slide-canvas.tsx`, `.kenten` in
`globals.css`).

## Files

| Path | What |
|---|---|
| `copy/store-copy.json` | Every label, headline and list row, in ten languages |
| `scripts/build-decks.py` | Writes the four decks (iPhone, iPad, Watch, Duo) into `app-store-screenshots.json` from the copy |
| `scripts/capture-ios.py` | Captures the iPhone or iPad frames per language (`--device ipad`) |
| `scripts/capture-watch.py` | Captures the four Watch frames per language from a seeded save slot |
| `scripts/capture-duo.py` | Captures the four open-Duo frames per language (Device Hub set to Open by hand) |
| `scripts/capture-tv.py` | Captures the four Apple TV frames per language (seeded; `-NineRemoteInjector` for the ring and settings) |
| `../scripts/mac-store-shots.sh --out` | Captures the three Mac windows per language |
| `scripts/capture-mac.sh` | The Mac board mid-solve, for slide 05 |
| `scripts/place-captures.sh` | Flattens captures into `public/screenshots/apple/` |
| `scripts/publish.py` | Turns export zips into the committed JPEG set |
| `public/screenshots/apple/devices`, `gamecenter` | Mac, TV, Watch captures and the achievement badges |

Raw captures (`public/screenshots/apple/iphone`, `ipad`, `watch`, `duo-*`) and
`exports/` are regenerated, not committed. So are `mac/` and `tv/`.

## Rebuild

```bash
bun install
python3 scripts/capture-ios.py /tmp/shots/iphone         # Debug build on Nine-Store-iPhone
NINE_KILLER_STATE=/tmp/shots/iphone/killer \
  python3 scripts/capture-ios.py --device ipad /tmp/shots/ipad   # Debug build on Nine-Store-iPad
python3 scripts/capture-watch.py /tmp/shots/watch        # NineWatch on Nine-Store-Watch
DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer \
  python3 scripts/capture-duo.py /tmp/shots/duo          # iOS 27.1 SDK build; Duo set to Open
python3 scripts/capture-tv.py /tmp/shots/tv              # tvOS Debug build, Apple TV 4K (at 1080p)
zsh ../scripts/mac-store-shots.sh --no-build --out /tmp/shots/mac en de …   # Release build
zsh scripts/place-captures.sh /tmp/shots/iphone          # then: ipad, watch, duo, mac, tv
bun dev -- -p 3077
python3 scripts/build-decks.py --device iphone           # reload, Export bundle; repeat per deck
python3 scripts/publish.py --iphone <zip> --ipad <zip> --watch <zip> --duo <zip>
```

`publish.py` replaces only the devices it is given, so one deck can be
re-exported alone. `NINE_ONLY=3,10` makes `capture-ios.py` retake just those
frames.

## Things that bit

- **No iPhone 18 Pro Max runtime** on this Mac: frames come from the 6.9"
  iPhone 17 Pro Max simulator (same 1320×2868 slot) and are drawn in the
  bundled iPhone 18 Pro Max bezel.
- **Accessibility labels are localised.** Tap targets come from
  `Localizable.xcstrings`. The Killer tier tile ignores taps in ja, ko and
  zh-Hans, and on the iPad in every language, so the Killer board is opened
  once on the iPhone in English and seeded everywhere else.
- **A channel board is two blobs.** The library holds the board; its cages are
  in `nine.channelRules`. Seed only the library and the board opens titled
  "Killer" with no cages drawn, as the first iPad run did; `capture-ios.py`
  now saves and seeds both (`killer/`).
- **The iPad shelf is mostly empty glass**, so the iPad languages slide shows
  each locale's Technique School (frame 10) instead of its home screen.
- **The Duo needs an iOS 27.1 SDK build.** A 27.0-SDK build runs letterboxed on
  the open Duo: no spread, and the Debug surfaces do not open. Device Hub's
  posture must be Open and *not* turned.
- **The watch marks mistakes whatever the phone's setting**, so
  `capture-watch.py` corrects the fixture's deliberate wrong digit, and
  `simctl status_bar` does nothing on watchOS: the watch clock is real.
- **The tvOS canvas is 3840×2160.** The editor lays the Apple TV deck out at its
  first size and scales the 1920×1080 export from it, so coordinates in
  `build-decks.py` are 4K ones.
- **The Mac capture needs a 2× screen**, not the main one: with a 1× external
  display as main, the window would be 1440×900 pixels. The script picks the
  first Retina screen.
- **Holding ▶︎II undoes on tvOS now**; settings open on a held click, which the
  injector sends as `hold` then `holdEnd`.
- **SharePlay** cannot be called between simulators: slide 06 is Nine's
  Debug-only `-parlor-demo` session (two simulated players), the same screen a
  real call shows.
- **Connected canvas is off.** With it on, two-phone layouts bleed into the
  neighbouring slides' exports.
- The headless export of 360 iPhone renders takes several minutes; give the
  download wait 30.
