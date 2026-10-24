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
| `scripts/build-decks.py` | Writes both decks into `app-store-screenshots.json` from the copy |
| `scripts/capture-iphone.py` | Captures the eight iPhone frames per language |
| `scripts/capture-mac.sh` | The Mac board mid-solve, for slide 05 |
| `scripts/place-captures.sh` | Flattens captures into `public/screenshots/apple/` |
| `scripts/publish.py` | Turns export zips into the committed JPEG set |
| `public/screenshots/apple/devices`, `gamecenter` | Mac, TV, Watch captures and the achievement badges |

Raw captures (`public/screenshots/apple/iphone`, `duo-*`) and `exports/` are
regenerated, not committed.

## Rebuild

```bash
bun install
python3 scripts/capture-iphone.py /tmp/shots     # needs a Debug build on Nine-Store-iPhone
zsh scripts/place-captures.sh /tmp/shots
python3 scripts/build-decks.py --device iphone
bun dev -- -p 3077                               # Export bundle, per device
python3 scripts/build-decks.py --device duo-inner-landscape   # reload, Export bundle
python3 scripts/publish.py <iphone.zip> <duo.zip>
```

## Things that bit

- **No iPhone 18 Pro Max runtime** on this Mac: frames come from the 6.9"
  iPhone 17 Pro Max simulator (same 1320×2868 slot) and are drawn in the
  bundled iPhone 18 Pro Max bezel.
- **Accessibility labels are localised.** Tap targets come from
  `Localizable.xcstrings`. The Killer tier tile ignores taps in ja, ko and
  zh-Hans, so the Killer board is opened once in English and its library is
  seeded into every locale.
- **SharePlay** cannot be called between simulators: slide 06 is Nine's
  Debug-only `-parlor-demo` session (two simulated players), the same screen a
  real call shows.
- **Connected canvas is off.** With it on, two-phone layouts bleed into the
  neighbouring slides' exports.
- The headless export of 360 iPhone renders takes several minutes; give the
  download wait 30.
