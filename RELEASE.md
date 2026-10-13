# Shipping Nine to the App Store

[TESTFLIGHT.md](TESTFLIGHT.md) gets a signed build onto App Store Connect. This
file takes it from there: the store page, the screenshots, the age rating and
the submission. It is Sub-projects 3 (`deliver`) and 4 (screenshots) of the
fastlane roadmap in
`docs/superpowers/specs/2026-07-12-fastlane-match-subproject-1-design.md`.

**First release scope (owner decision 2026-10-13): iPhone/iPad and Mac, at
$4.99 paid up front.** Apple TV keeps shipping to TestFlight through `beta` but
is not submitted; `release` refuses platforms outside `RELEASE_PLATFORMS` in the
Fastfile. The watch app is not embedded in the iOS app for this release (see
the comment at the `NineWatch` dependency in `nine/project.yml`), so the store
asks for no Watch screenshots.

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
`release` has no default build number on purpose: HEAD's commit count is not
the number of the build that was tested. Use the number TestFlight shows
(`commit count × 10`, +1 iOS, +2 Mac). Approval never auto-releases —
`automatic_release: false` — so going live is always a human's button.

## Screenshots

| Platform | Required set | Pixel size | How it is made |
|---|---|---|---|
| iOS | 6.9" iPhone | 1320×2868 | `store_screenshots_capture` (iPhone 17 Pro Max simulator) |
| iOS | 13" iPad | 2064×2752 | `store_screenshots_capture` (iPad Pro 13-inch (M5) simulator) |
| macOS | Mac | 2880×1800 (or 2560×1600, 1440×900, 1280×800) | manual — a 16:10 window capture |
| *later* iOS | Apple Watch, once NineWatch is re-embedded | 422×514 (Ultra 3) | manual — Watch simulator + `xcrun simctl io <udid> screenshot` |
| *later* tvOS | Apple TV | 3840×2160 | manual — `.claude/skills/run-nine` + `xcrun simctl io <udid> screenshot` |

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
- [ ] **App Privacy questionnaire** ("nutrition label") — ASC web → App Privacy →
      *Data Not Collected*. deliver cannot set it.
- [ ] **Price and availability: $4.99, paid up front** (decided 2026-10-13).
      Universal purchase is automatic — one bundle id across iOS and macOS.
      Set it in the ASC web UI (Pricing and Availability); the covenant (no
      IAP, no ads) holds. The Paid Apps agreement, tax and banking must be
      active under Business before a paid app can go on sale.
- [ ] **App Review contact** — `fastlane/metadata/review_information/` takes
      `first_name.txt`, `last_name.txt`, `phone_number.txt`, `email_address.txt`.
      Not committed by default; add them locally or in ASC.
- [ ] **Age rating** — confirm the answers in `fastlane/rating_config.json`
      (all *None* / *No*). `store_metadata` uploads them.
- [ ] **Screenshots for every required set above** (iPhone 6.9", iPad 13", Mac).
- [ ] **Leave the Apple TV version unsubmitted.** If ASC created a tvOS version
      on the record, it can sit in *Prepare for Submission* indefinitely.
- [ ] **Marketing version** — the lanes read `MARKETING_VERSION` from
      `nine/project.yml` (currently 1.1). If 1.1 is already live, bump it there
      and ship a new build first.

Before release, carried from earlier PRDs:

- [ ] **Deploy the CloudKit schema to Production** (PRD-7 §5) — development
      schemas do not promote themselves, and library sync silently does nothing
      in a production build without it.
- [ ] **Game Center** — upload leaderboard and achievement artwork and add Game
      Center to the version. The live IDs are `GameCenter.ID` in
      `nine/Sources/App/GameCenter.swift`: the streak boards, streak achievements
      and weekly table stopped receiving submissions with the daily removal
      (#58), so leave them off the version; the per-channel boards
      (`com.couchsuite.nine.points.<channel>`) have no ASC records yet, and
      channel solves submit into silence until they do.
- [ ] **Copy review** — `fastlane/metadata/en-US/` is a first draft written from
      the README, PRDs and the #58 removal. Read it against the build you are
      shipping; `release_notes.txt` especially is per-release.

Later (PRD-35, "The Store Tells the Story"): localized store pages for the nine
shipped languages, app preview videos, custom product pages.
