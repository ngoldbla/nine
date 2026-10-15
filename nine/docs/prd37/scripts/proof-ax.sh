#!/bin/bash
# AX lane, main vs branch, both toolchains, harness simulator rebooted before every run.
S=/private/tmp/claude-501/-Users-aquilops-nine/39f5188e-4357-417b-a0c5-7844ac940113/scratchpad
U=F2A2C95F-0F65-48BA-B2A0-8B3AC32E197F
P=$S/proof-ax2; rm -rf "$P"; mkdir -p "$P"
export NINE_SIMSLIM=0
cd /Users/aquilops/nine/nine || exit 2
for spec in "branch266:build" "main266:$S/wt-main/nine/build266"; do
  tag="${spec%%:*}"; dir="${spec#*:}"
  if [ "${tag: -3}" = 271 ]; then export DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer; else unset DEVELOPER_DIR; fi
  xcrun simctl shutdown $U >/dev/null 2>&1; xcrun simctl boot $U; xcrun simctl bootstatus $U -b >/dev/null 2>&1
  python3 scripts/ax-snapshot.py --runtime 26.5 --no-erase --app "$dir/Build/Products/Debug-iphonesimulator/Nine.app" --out-dir "$P/$tag" > "$P/$tag.log" 2>&1
  echo "$tag exit=$? files=$(ls "$P/$tag" | grep -c txt) $(grep -E 'timed out|drifted|all accessibility' "$P/$tag.log" | head -1 | cut -c1-50)"
done
for x in 266; do
  echo "== AX Xcode $x: main vs branch differing tree files: $(diff -r -q -x '*.png' "$P/main$x" "$P/branch$x" | wc -l | tr -d ' ') of $(ls "$P/main$x" | grep -c txt)"
done
