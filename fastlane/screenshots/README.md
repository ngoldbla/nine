# Store screenshots

One tree per platform, one folder per ASC locale: `ios/en-US/`, `tvos/en-US/`,
`mac/en-US/`. The PNGs are regenerated, never committed. Sizes, sources and
the capture lane are in [RELEASE.md](../../RELEASE.md#screenshots);
`bundle exec fastlane ios store_check` validates whatever is here.
