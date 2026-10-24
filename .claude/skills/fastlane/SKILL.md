---
name: fastlane
description: Prepare and ship Nine with fastlane — App Store metadata and copy, screenshots, age rating, App Store Connect setup, TestFlight builds and review submission. Use when asked to release Nine, edit its store listing, capture or upload store screenshots, run deliver/pilot/match, or check App Store readiness.
---

# fastlane for Nine

Two documents are the source of truth; read the one you need before acting:

- `TESTFLIGHT.md` — signing (`match`), builds and TestFlight (`beta*` lanes).
- `RELEASE.md` — the store: metadata, screenshots, age rating, submission
  (`store_*` and `release` lanes) and the account-side checklist.

**Current scope:** iOS + macOS at $4.99 since 1.1, with the watch app embedded
in the iOS app; **Apple TV joins the App Store with 1.2** (owner, 2026-10-23),
and iOS 1.2 ships the iPhone Duo set. `RELEASE_PLATFORMS` is `ios tvos mac`.
Store copy may describe Apple TV, the Duo and, since the owner's call of
2026-10-24, the Parlor (SharePlay, "Play together"). The listing is in ten
locales (`fastlane/metadata/<locale>/`).

Lanes live in `fastlane/Fastfile` under `platform :ios`, so they are invoked as
`bundle exec fastlane ios <lane>`. Every lane takes `platform:tvos|ios|mac`.

## Where you are decides what you can run

| Lane | Needs | Runs in a Linux cloud container? |
|---|---|---|
| `store_check` | nothing | **yes** — always run it after touching `fastlane/` |
| `store_pull`, `store_metadata`, `store_screenshots`, `release` | ASC API key | yes, if the key is in the environment (it usually is not) |
| `store_screenshots_capture` | macOS, Xcode, simulators | no |
| `beta`, `beta_app`, `beta_all` | macOS, Xcode, match repo access | no |

In a cloud container, set up once per session:

```bash
export PATH=/opt/rbenv/versions/3.3.6/bin:$PATH LC_ALL=C.UTF-8 LANG=C.UTF-8 \
       FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_OPT_OUT_USAGE=1
bundle install          # Gemfile pins fastlane 2.237.0
bundle exec fastlane ios store_check
```

`bundle install` writes a `Gemfile.lock`; it is not committed (CI resolves its
own on macOS) — delete it before committing. On the owner's Mac, fastlane was
installed by Homebrew and `signing.env` holds the credentials:
`set -a && source signing.env && set +a`.

Never ask for, echo or commit ASC keys, `MATCH_PASSWORD` or `.p8` content. If a
lane needs credentials the session does not have, stop at `store_check` and hand
the exact command to the user.

## Editing the store listing

- Copy is in `fastlane/metadata/<locale>/*.txt`, en-US first and the other
  nine translated from it in Nine's own terms (`Localizable.xcstrings`); app-wide fields in
  `fastlane/metadata/*.txt`. Limits: name and subtitle 30, promotional text 170,
  description and release notes 4000, keywords 100 **bytes**, comma-separated
  with no spaces, no words already in the name. `store_check` enforces them.
- Copy must describe the build being shipped. The daily, the streak, the weekly
  table and the daily widgets were removed in #58 — never advertise them. The
  Parlor (PRD-28) ships with the Group Activities entitlement and is advertised
  (owner, 2026-10-24); say what it does (same board, a dot per friend, no times
  until all finish), not more. When unsure whether a feature is live, check `nine/PROGRAM-2.0.md`'s
  status column and `nine/DEVIATIONS.md`, not a PRD's intent.
- Art direction applies to screenshots too: dark-first, the board owns the
  frame, no transient chrome. Captures come from the seeded `ninestate.py`
  container for exactly that reason; do not hand-drive a fresh install for a
  store frame.
- A new locale is a new folder named with an ASC locale code (`de-DE`, `ja`,
  `pt-BR`, `zh-Hans` …) holding at least `name.txt`, `description.txt`,
  `keywords.txt`, `support_url.txt`, `privacy_url.txt`.

## Support and privacy pages

`site/` is a static site (index, support, privacy) served by the Cloudflare
Worker `nine-sudoku` (https://nine-sudoku.ngoldbla.workers.dev);
`site/deploy.sh` publishes it with wrangler, filling `{{CONTACT_EMAIL}}` from
`NINE_CONTACT_EMAIL`. Keep the privacy page true to `nine/PrivacyInfo.xcprivacy`
and the App Privacy label: if the app ever collects data, all three change
together. Never commit a filled-in contact address you weren't given for that
purpose.

## Screenshots

**What iOS uploads is the designed set** in `fastlane/screenshots/marketing/`
(captioned iPhone, iPad, Watch and Duo slides, ten locales, committed as JPEG):
`STORE_SHOT_DIRS` in the Fastfile points deliver at it. It is made in the
editor in `store-screenshots/`; that folder's `STORE-ART.md` and the marketing
README say how to rebuild it. tvOS and Mac upload their own en-US folders, and
`store_check` lets a locale without a folder fall back to en-US as ASC does.

`store_screenshots_capture` (macOS) runs `nine/scripts/shotlist.py` with its
`iphone-store` / `ipad-store` devices and copies the frames named in
`STORE_SHOTS` into `fastlane/screenshots/ios/en-US/` as `NN-device-scene-appearance.png`:
plain frames, no longer uploaded, kept as raw material and a quick check. To add
a scene, add it to `SCENES` in `shotlist.py` (it is the critic lane's list too).
tvOS and Mac sets are manual — sizes and tools are in `RELEASE.md`. PNGs are
gitignored, except the English iPhone Duo frames in `fastlane/screenshots/ios-duo/en-US/`
(posture needs a person) and the tvOS set.

## Traps

- **Build numbers** are `(commit count + 100) × 10` + 0 tvOS / 1 iOS / 2 Mac,
  computed in the `beta` lane; CI uploads from `main` only. `release` takes `build:` explicitly — never compute it
  from HEAD. Never rewrite this repo's history (see `CLAUDE.md`).
- **`release` without `submit:true` stages only.** Submitting for review is
  outward-facing: confirm with the user before passing `submit:true`, every time.
- **Metadata uploads overwrite what is on ASC.** Run `store_pull` first and
  `diff -ru fastlane/.asc-pull/<platform> fastlane/metadata` when ASC may hold
  edits made in the web UI.
- **App-level fields are shared across platforms** (name, subtitle, privacy URL,
  categories, age rating); version-level ones are per platform. Pushing
  metadata for one platform does not update the others.
- **The Matchfile is scoped to Nine's three bundle ids** because the certs repo
  is shared with four other apps. Never widen it, and never run `match` without
  `readonly: true` unless the user asked for a re-mint.
- **The App Privacy label, pricing, CloudKit production schema and Game Center
  artwork** cannot be set by these lanes — they are on the `RELEASE.md`
  checklist; report them, do not pretend a lane covered them.
