#!/bin/bash
# PRD-37 zero-change proof: main vs branch, same Xcode, same iOS 26.5 runtime, same harness.
# Each run writes to its own directory; a lane that times out (a known simulator flake) is retried once.
S=/private/tmp/claude-501/-Users-aquilops-nine/39f5188e-4357-417b-a0c5-7844ac940113/scratchpad
B=/Users/aquilops/nine/nine
M=$S/wt-main/nine
P=$S/proof2; rm -rf "$P"; mkdir -p "$P"
export NINE_SIMSLIM=0
cd "$B" || exit 2
run_lane() {
  lane="$1"; tag="$2"; app="$3"; out="$P/$tag-$lane"
  for attempt in 1 2; do
    rm -rf "$out"; mkdir -p "$out"
    python3 scripts/$lane.py --runtime 26.5 --app "$app" --out-dir "$out" > "$out.log" 2>&1
    rc=$?
    grep -q "timed out waiting" "$out.log" || break
    echo "  $tag $lane: timed out, retrying"
  done
  echo "$tag $lane exit=$rc files=$(ls "$out" | wc -l | tr -d ' ')"
}
for xc in 266 271; do
  if [ "$xc" = 271 ]; then export DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer; mdir=build271; bdir=build271
  else unset DEVELOPER_DIR; mdir=build266; bdir=build; fi
  for lane in ax-snapshot contrast-harness loc-harness; do
    run_lane "$lane" "main$xc" "$M/$mdir/Build/Products/Debug-iphonesimulator/Nine.app"
    run_lane "$lane" "branch$xc" "$B/$bdir/Build/Products/Debug-iphonesimulator/Nine.app"
    d=$(diff -r -q -x '*.png' -x '*.bmp' "$P/main$xc-$lane" "$P/branch$xc-$lane" | wc -l | tr -d ' ')
    n=$(find "$P/main$xc-$lane" -name '*.txt' | wc -l | tr -d ' ')
    echo "== Xcode $xc $lane: $n text files compared, main vs branch differing files: $d"
  done
done
