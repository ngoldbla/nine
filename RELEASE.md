# Shipping Nine to the App Store

[TESTFLIGHT.md](TESTFLIGHT.md) gets a signed build onto App Store Connect. This
file takes it from there: the store page, the screenshots, the age rating and
the submission. It is Sub-projects 3 (`deliver`) and 4 (screenshots) of the
fastlane roadmap in
`docs/superpowers/specs/2026-07-12-fastlane-match-subproject-1-design.md`.

**First release scope (owner decision 2026-10-13): iPhone/iPad with the Apple
Watch app, and Mac, at $4.99 paid up front.** Apple TV keeps shipping to
TestFlight through `beta` but is not submitted; `release` refuses platforms
outside `RELEASE_PLATFORMS` in the Fastfile. The watch app ships *inside* the
iOS version, so that version needs an Apple Watch screenshot set.

**1.2 (owner decision 2026-10-23): Apple TV joins the App Store**, after the
tvOS repair pass (#68) made it playable on a television, and iOS ships the
iPhone Duo spread (PRD-37) with its own screenshot set. `RELEASE_PLATFORMS` is
`ios tvos mac`. The tvOS record's first version goes up as 1.2, to match the
binary; ASC takes no release notes on a first version and deliver skips them.

The binary never goes through these lanes. `beta` uploads it; `release` attaches
it **by build number**, so the only pipeline that signs is the one already
proven by TestFlight.

## What lives where

| Path | What | Who changes it |
|---|---|---|
| `fastlane/metadata/<locale>/` | name, subtitle, description, keywords, promotional text, release notes, URLs | copy edits, every release (release notes) |
| `fastlane/metadata/*.txt` | copyright, categories (shared by every locale) | rarely |
| `fastlane/metadata/review_information/` | App Review notes + contact | owner |
| `fastlane/rating_config.json` | age-rating questionnaire answers | owner, when the app changes what it shows |
| `fastlane/screenshots/{ios,tvos,mac}/<locale>/` | store screenshots, one tree per platform | regenerated, never committed (`.gitignore`) |

ASC splits these fields in two, and it matters on a universal app:

- **App-level** (one value for every platform): name, subtitle, privacy policy
  URL, categories, age rating.
- **Version-level** (one value *per platform version*): description, keywords,
  promotional text, release notes, support/marketing URL, copyright, screenshots.

So `store_metadata platform:ios` and `platform:tvos` push the same files to two
different version records. Run it once per platform you are releasing.

## Lanes

```bash
set -a && source signing.env && set +a
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8   # store_check crashes on the copy's non-ASCII without it
bundle install

bundle exec fastlane ios store_check                       # offline: iOS + Mac (platform:all adds tvOS)
bundle exec fastlane ios store_pull platform:ios           # what ASC holds now → fastlane/.asc-pull/ios
bundle exec fastlane ios store_metadata platform:ios       # text + age rating, no screenshots
bundle exec fastlane ios store_screenshots_capture         # macOS: simulators → fastlane/screenshots/ios
bundle exec fastlane ios store_screenshots platform:ios    # replace the screenshots on ASC
bundle exec fastlane ios release platform:ios build:1231   # attach build, push everything, stop
bundle exec fastlane ios release platform:ios build:1231 submit:true   # …and submit for review
```

`store_check` is the gate every upload lane runs first, and the only lane that
needs no credentials — run it anywhere, including a Linux container.

**While another platform's version is In Review, pass `app_info:false`.** The
app-level record (name, subtitle, privacy URLs, categories, age rating) is shared
by every platform and ASC locks it during any review; deliver's metadata step
fetches it unconditionally and gives up after ~10 minutes of "Cannot find edit
app info". With `app_info:false`, deliver still renames/creates the version and
replaces the screenshots, and the version-level text (description, keywords,
promotional text, URLs, copyright, release notes) goes up through the API.
1.2 was staged this way on 2026-10-23 while Mac 1.1 sat in review. `release`
also attaches the build itself now: deliver only picks one inside
`submit_for_review`, so a staged version used to have none. The same path sets
**manual release** and creates **App Review details** when a version has none
(copying the contact from another version; notes from
`metadata/review_information/notes.txt`), two more things deliver's skipped
metadata step used to do. Both were done by hand for tvOS 1.2, which went in
without review details and set to release on approval.

**Game Center on a new platform's version** is not a lane step: the API takes a
`POST /v1/gameCenterAppVersions` linked to the `appStoreVersion` (done for tvOS
1.2 on 2026-10-23). Later versions on that platform inherit it, as iOS 1.2 did
from 1.1.
`release` has no default build number on purpose: HEAD's commit count is not
the number of the build that was tested. Use the number TestFlight shows
(`(commit count + 100) × 10`, +1 iOS, +2 Mac; builds before 2026-10-17 had no +100). Approval never auto-releases —
`automatic_release: false` — so going live is always a human's button.

## Screenshots

| Platform | Required set | Pixel size | How it is made |
|---|---|---|---|
| iOS | 6.9" iPhone | 1320×2868 | `store_screenshots_capture` (iPhone 17 Pro Max simulator) |
| iOS | 13" iPad | 2064×2752 | `store_screenshots_capture` (iPad Pro 13-inch (M5) simulator) |
| iOS | Apple Watch | 422×514 (Ultra 3, 49mm) or 416×496 (Series 11, 46mm) | manual — see below |
| *with Duo support* iOS | iPhone Duo, open (inner) + folded (outer) | 2853×2007 + 1398×2034 | manual, kept in git — `fastlane/screenshots/ios-duo/en-US/`, see **iPhone Duo** below |
| macOS | Mac | 2880×1800 (or 2560×1600, 1440×900, 1280×800) | `scripts/mac-store-shots.sh` (Release build, seeded state; park the pointer at the left edge first) |
| tvOS | Apple TV | 1920×1080 (or 3840×2160) | manual, kept in git — `fastlane/screenshots/tvos/en-US/`, driven with `XCUIRemote` from a clean install (see **Apple TV** below) |

**Designed set for the next imagery update.** Captioned iPhone 6.9" and iPhone
Duo slides in all ten languages are committed as JPEG in
`fastlane/screenshots/marketing/<locale>/`, made in the editor in
`store-screenshots/` (its `STORE-ART.md`). No lane uploads them yet — that
folder's README says what is missing (iPad, Watch, nine locales' listing text)
and how to wire it in.

**Apple Watch, by hand** (one size is enough; ASC scales it to the others):

```bash
cd nine && xcodegen generate
xcrun simctl create Nine-Store-Watch "Apple Watch Ultra 3 (49mm)"   # once; prints a udid
xcrun simctl boot Nine-Store-Watch && open -a Simulator
xcodebuild -project Nine.xcodeproj -scheme NineWatch \
  -destination 'platform=watchOS Simulator,name=Nine-Store-Watch' \
  -derivedDataPath .build/watch build CODE_SIGNING_ALLOWED=NO
xcrun simctl install Nine-Store-Watch "$(find .build/watch/Build/Products -name 'NineWatch.app' -maxdepth 3 | head -1)"
xcrun simctl launch Nine-Store-Watch com.couchsuite.nine.watchkitapp
# drive it in the Simulator window, then for each frame:
xcrun simctl io Nine-Store-Watch screenshot ../fastlane/screenshots/ios/en-US/20-watch-board.png
```

The store simulators need `com.apple.gamed` if they are `simslim`-slimmed:
Nine waits on Game Center authentication at launch, and a slim simulator
without it shows a white screen for over three minutes
(`simslim on <udid> --keep com.apple.gamed`).

Four frames tell the story: the home list, a board mid-solve, one box zoomed
in with the Crown dial turning, and the solve celebration. In the Simulator,
the Crown is the scroll wheel / two-finger scroll over the watch face. Number
the files `20-…` onward so they sort after the phone and iPad sets.

**Apple TV** (1.2). Five frames, committed like the Duo's because nothing seeds
a tvOS state: the shelf on Gentle and on Sharp, a fresh board, the digit ring,
and settings beside the board. Taken 2026-10-23 from a clean install (uninstall
first, so there is no saved board), the timer switched off in settings, each
frame after the transient chrome and the once-per-launch legend had faded. The
capture was a throwaway `XCUIRemote` test in `nine/UITests/TV/` writing
`XCUIScreen.main.screenshot()` to `NINE_UITEST_DUMP`; the same pattern reshoots.

**iPhone Duo** (taken for 1.2; uploaded with 1.2). The eight frames — board, coach
and Technique School dark plus board light, once per posture — live in
`fastlane/screenshots/ios-duo/en-US/` with a README naming each one. They are
the only committed store PNGs (a `.gitignore` exception), because a reshoot
needs a person: nothing scriptable sets the Duo's posture (PRD-37 §1.6).

They stay in `screenshots/ios-duo/` (committed) rather than moving into the
regenerated `screenshots/ios/`, which `store_screenshots_capture` empties. The
Fastfile's `COMMITTED_SHOT_DIRS` merges them into the iOS set at upload, via
`fastlane/.store-shots/ios`. fastlane 2.237.0 had no display type for 2853×2007
or 1398×2034; 2.241.1 (the Gemfile pin since 1.2) maps both postures to
`APP_IPHONE_DUO`, which `store_screenshot_problems` now requires on iOS.

To reshoot (Xcode 27.1; one person at Device Hub for the two posture
presses):

```bash
export DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer
cd nine
python3 scripts/shotlist.py --device duo-open   --appearance both --scenes game,coach,school
python3 scripts/shotlist.py --device duo-folded --appearance both --scenes game,coach,school \
        --errors off --no-build --no-erase
# keep dark game/coach/school + light game from each; name them NN-<device>-<scene>-<appearance>.png
```

Each run stops at a prompt until Device Hub's posture matches; it reads
stdin, so it needs a terminal (or a pty) to answer. **If Device Hub's
posture buttons do nothing**, check `xcrun devicectl list devices` before
anything else. On 2026-10-22 CoreDeviceService had been up for eight days
and was serving a stale list: it still showed deleted simulators and not the
new one, so Device Hub's buttons went nowhere. Killing `CoreDeviceService`
fixed it. It relaunches on demand and running simulators are not touched.
Relaunching Device Hub alone did not help. Also run the Device Hub that
matches the runtime: Xcode 27.0's lists the 27.1 Duos but cannot drive them.

The iOS capture reuses `nine/scripts/shotlist.py` — the same seeded, frozen
container the AX, contrast and localization lanes photograph against, status bar
pinned at 9:41 — with two store-sized devices added beside its critic devices.
`STORE_SHOTS` in the Fastfile picks the scenes and their order. deliver orders a
set by filename, so prefix manual captures `01-`, `02-` … into the right
platform folder.

## Account-side checklist (human-owned, not lane work)

Blocking — ASC will refuse submission without these:

- [x] **Support and privacy pages** — live since 2026-10-13 at
      `https://nine-sudoku.ngoldbla.workers.dev/{support,privacy}`, a
      static-assets Cloudflare Worker built from `site/`. Redeploy with
      `NINE_CONTACT_EMAIL=… site/deploy.sh`; the metadata URLs already match.
- [x] **App Privacy questionnaire** (published 2026-10-13: Data Not Collected; privacy URL set) ("nutrition label") — ASC web → App Privacy →
      *Data Not Collected*. deliver cannot set it.
- [x] **Price and availability: $4.99, paid up front** (set 2026-10-13; Paid Apps agreement Active under Business 2026-10-13) (decided 2026-10-13).
      Universal purchase is automatic — one bundle id across iOS and macOS.
      Set it in the ASC web UI (Pricing and Availability); the covenant (no
      IAP, no ads) holds. The Paid Apps agreement, tax and banking must be
      active under Business before a paid app can go on sale.
- [x] **App Review contact** (2026-10-13: set in ASC on iOS, copied to the Mac
      version through the API; neither lives in the repo) — `fastlane/metadata/review_information/` takes
      `first_name.txt`, `last_name.txt`, `phone_number.txt`, `email_address.txt`.
      Not committed by default; add them locally or in ASC.
- [x] **Age rating** (4+; uploaded by `store_metadata` for iOS and Mac 2026-10-13) — confirm the answers in `fastlane/rating_config.json`
      (all *None* / *No*). `store_metadata` uploads them.
- [x] **Screenshots for every required set above** (iPhone 6.9", iPad 13", Mac).
      (2026-10-13: uploaded — iPhone 5, iPad 4, Apple Watch 4, Mac 3. No home
      frame while the Parlor card is unadvertised; see `STORE_SHOTS` in the
      Fastfile. Watch frames were driven with `sim-use tap -x -y`, which works
      on watchOS; `simctl status_bar` does not, so the watch clock is real.)
- [x] **~~Leave the Apple TV version unsubmitted.~~** Superseded 2026-10-23:
      tvOS ships with 1.2 (see the scope note at the top).
- [x] **Marketing version** (2026-10-13: ASC's iOS and Mac versions are both
      1.1, Manual release. Submitted for review 2026-10-13: iOS build **861**
      (721 was refused — its NineWatch lacked the Game Center key) and Mac
      build 722, after Game Center was enabled on the Mac version too —
      ASC refuses a build/version mismatch either way round) — the lanes read `MARKETING_VERSION` from
      `nine/project.yml` (currently 1.1). If 1.1 is already live, bump it there
      and ship a new build first.

Before release, carried from earlier PRDs:

- [x] **Deploy the CloudKit schema to Production** (2026-10-13: Development
      had no record types — no build had ever synced — so `LibraryEntry` and
      `SolveReplay` were created there by hand from `LibraryCloudStore` and
      deployed; the deployed schema is `nine/CloudKit/schema.ckdb`) (PRD-7 §5) — development
      schemas do not promote themselves, and library sync silently does nothing
      in a production build without it.
- [x] **Game Center** — upload leaderboard and achievement artwork and add Game
      Center to the version. (2026-10-13: Game Center is on the iOS 1.1 version
      with `points` and the five `solve.*` / `sharp.first` / `swift`
      achievements attached; artwork from `scripts/gamecenter_art.py`
      (`fastlane/gamecenter/`, 1024x1024 RGB) uploaded and processed.) The live IDs are `GameCenter.ID` in
      `nine/Sources/App/GameCenter.swift`: the streak boards, streak achievements
      and weekly table stopped receiving submissions with the daily removal
      (#58), so leave them off the version; the per-channel boards
      (`com.couchsuite.nine.points.<channel>`) have no ASC records yet, and
      channel solves submit into silence until they do.
- [x] **Copy review** (2026-10-13: owner kept the web-UI edits — name "Nine:
      Sudoku", no em dashes — now in the repo and pushed to iOS + Mac; ASC takes
      no release notes on a first version) — `fastlane/metadata/en-US/` is a first draft written from
      the README, PRDs and the #58 removal. Read it against the build you are
      shipping; `release_notes.txt` especially is per-release.

1.2 to external TestFlight (iOS + Mac; not App Store review):

- [x] **Builds** (2026-10-16: the push of #61, `6e23320`, uploaded tvOS 750,
      iOS 751 and Mac 752 as 1.2; all processed. They sit below 1.1's iOS 861,
      which went up from an 86-commit branch while main stood at 74 — fixed
      2026-10-17 by the +100 base in `BUILD_BASE_COMMITS` and main-only
      uploads, so the next main build is 1760/1761/1762.)
- [x] **Gate** (2026-10-17: `swift test` in `nine/` 126 tests and `couchkit/`
      35 green; both `strings.py` checks green; `store_check` green for iOS +
      Mac. `platform:all` fails only on the tvOS screenshot set, which does
      not exist yet.)
- [x] **Simulator check of HEAD** (2026-10-17, Xcode 27.1: iOS launches on the
      iPhone Duo folded, with widgets and watch embedded; NineWatch launches to
      a board; the Mac Release build launches to the shelf. The open-Duo
      spread was not checked — Device Hub's posture needs a person.)
- [x] **iOS 751 external beta** (approved before 2026-10-17, in Friends &
      Family, What to Test "Adding Duo support".)
- [x] **Mac 752 external beta** (2026-10-17: export compliance already "no
      non-exempt encryption"; What to Test set; added to Friends & Family;
      submitted for Beta App Review — waiting for review.)
- [ ] **tvOS 750 stays internal.** The owner found it not playable on
      2026-10-17; it is not sent to external beta review until that is fixed.
- [x] **First-run copy** (2026-10-23): `firstrun.ledger.sync` is "Boards and
      stats follow you between devices" in all ten languages; `onePurchase`
      ("… Mac & Apple TV") became true when Apple TV joined the store.

Later (PRD-35, "The Store Tells the Story"): localized store pages for the nine
shipped languages, app preview videos, custom product pages.
