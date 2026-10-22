# iPhone Duo store frames — Nine 1.2

Captured 2026-10-22 on Xcode 27.1, iOS 27.1, a slimmed `Nine-Shotlist-Duo`,
from the seeded `ninestate.py` container (status bar pinned at 9:41). Unlike
every other store PNG these are **committed, not regenerated**: no tool can
set the Duo's posture, so a reshoot needs a person in Device Hub.

| File | Posture | Size | Scene |
|---|---|---|---|
| `01-duo-open-game-dark.png` | open (inner panel) | 2853×2007 | board, dark |
| `02-duo-open-coach-dark.png` | open | 2853×2007 | coach card over the board, dark |
| `03-duo-open-school-dark.png` | open | 2853×2007 | Technique School, dark |
| `04-duo-open-game-light.png` | open | 2853×2007 | board, light |
| `01-duo-folded-game-dark.png` | folded (outer panel) | 1398×2034 | board, dark |
| `02-duo-folded-coach-dark.png` | folded | 1398×2034 | coach card, dark |
| `03-duo-folded-school-dark.png` | folded | 1398×2034 | Technique School, dark |
| `04-duo-folded-game-light.png` | folded | 1398×2034 | board, light |

The open set marks the wrong digit (`errorHighlight` on, the lane's default);
the folded set was taken with `--errors off`. The folded coach card still
reads "A slip somewhere": that is the hint's text about the seeded board's
conflict, which the preference does not hide. The flick rose is missing from
both sets — no launch argument opens it, and taps cannot reach the open inner
panel.

## Not uploaded — why this is not `screenshots/ios/`

fastlane 2.237.0's deliver has no display type for either size
(`Deliver::AppScreenshot.calculate_display_type` returns nil for all eight),
so in `screenshots/ios/` they would fail `store_check` and the iOS upload.
When shipping the Duo-native iOS version, first check whether a newer
fastlane, or App Store Connect itself, has an iPhone Duo display type. If one
of them does, move these into `screenshots/ios/en-US/` (numbered after the
iPhone and iPad sets) and add the type to `store_screenshot_problems` in the
Fastfile. If neither does, upload them by hand in App Store Connect. The steps
and the reshoot recipe are in `RELEASE.md` under "iPhone Duo".
