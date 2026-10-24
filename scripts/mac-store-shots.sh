#!/bin/zsh
# Mac App Store screenshots: three 2880x1800 window captures of a Release build,
# photographed against the same quiet seeded state as the iOS lanes
# (nine/scripts/ninestate.py), into fastlane/screenshots/mac/en-US.
#
#   scripts/mac-store-shots.sh            # build, then capture
#   scripts/mac-store-shots.sh --no-build
#   scripts/mac-store-shots.sh --no-build --out <dir> en de ja …
#
# With --out, each language is captured into <dir>/<language>/NN.png for the
# designed set in store-screenshots/ (01 board dark, 02 shelf dark, 03 board
# light), launched with -AppleLanguages; without it, the English plain set.
#
# Needs Screen Recording permission for the app running this shell, and a
# Retina (2x) display whose visible frame fits a 1440x900pt window. That display
# need not be the main one: with a 1x external monitor as main, the window goes
# on the first 2x screen, or the capture would be 1440x900 pixels.
#
# Three things this works around, each found the hard way (2026-10-13):
# - The app runs unsigned, so unsandboxed: its CouchKit store would be the real
#   ~/Library/Application Support/CouchKit. CFFIXED_USER_HOME points it at a
#   throwaway home instead.
# - The window size comes from the `nine.main` frame autosave (MacUI.swift),
#   overridden from the argument domain. The screen rect in that string must be
#   the real visible frame or AppKit rescales the window.
# - SwiftUI first opens the window centered, and if the pointer is inside that
#   rect the board records a hover cell that never clears once the window jumps
#   to its saved frame. Park the pointer at the far left edge before running.
set -euo pipefail
repo=${0:A:h:h}
nine=$repo/nine
out=$repo/fastlane/screenshots/mac/en-US
home=$(mktemp -d)
trap 'pkill -f "$app/Contents/MacOS/Nine" 2>/dev/null; rm -rf "$home"' EXIT
app=$nine/.build/mac/Build/Products/Release/Nine.app

build=1 dest=
[[ ${1:-} == --no-build ]] && { build=0; shift; }
[[ ${1:-} == --out ]] && { dest=$2; shift 2; }
langs=(${@:-en})

if (( build )); then
  (cd $nine && xcodegen generate -q && xcodebuild -project Nine.xcodeproj -scheme Nine \
     -configuration Release -destination 'platform=macOS' -derivedDataPath .build/mac \
     build CODE_SIGNING_ALLOWED=NO -quiet)
fi

swift_eval() { print -r -- "$1" > $home/s.swift && swift $home/s.swift 2>/dev/null; }
visible=$(swift_eval 'import AppKit
guard let s = NSScreen.screens.first(where: { $0.backingScaleFactor >= 2 && $0.visibleFrame.width >= 1480 && $0.visibleFrame.height >= 950 }) else { exit(1) }
let v = s.visibleFrame; print(Int(v.minX), Int(v.minY), Int(v.width), Int(v.height))') ||
  { print "no Retina (2x) screen fits a 1440x900pt window" >&2; exit 1; }
pointer=(${=$(swift_eval 'import AppKit; let p = NSEvent.mouseLocation; print(Int(p.x), Int(p.y))')})
pointer_x=${pointer[1]}
vis=(${=visible})
# The window opens 40pt right of the pointer if it is at the screen's left
# edge, else 40pt in; either way the pointer must not be inside it.
left=$(( vis[1] + 40 ))
(( pointer_x >= vis[1] && pointer_x < vis[1] + 300 )) && left=$(( pointer_x + 40 ))
if (( pointer_x >= left && pointer_x <= left + 1440 && pointer[2] >= vis[2] && pointer[2] <= vis[2] + 947 )); then
  print "park the pointer at the far left edge of the Retina screen, or on another screen" >&2; exit 1
fi

shoot() {  # appearance resume out.png [language]
  pkill -f "$app/Contents/MacOS/Nine" 2>/dev/null || true; sleep 1
  local store="$home/Library/Application Support/CouchKit"
  rm -rf $store && mkdir -p $store
  (cd $nine && python3 - "$store" $1 $2 <<'EOF'
import json, os, sys
sys.path.insert(0, "scripts")
import ninestate
store, appearance, resume = sys.argv[1], sys.argv[2], sys.argv[3] == "true"
# NinePrefs stores the theme under its pre-theme key, "appearance".
# Mistake marking off, as in every other store frame.
prefs = dict(ninestate.PREFS_ERRORS_OFF, appearance=appearance, resumeOnLaunch=resume)
for name, body in ninestate.quiet_blobs(prefs).items():
    open(os.path.join(store, name), "w").write(body)
EOF
  )
  local v=(${=visible})
  local lang=(); [[ -n ${4:-} ]] && lang=(-AppleLanguages "($4)" -AppleLocale ${4//-/_})
  CFFIXED_USER_HOME=$home $app/Contents/MacOS/Nine $lang \
    -"NSWindow Frame nine.main" "$left $((v[2] + 47)) 1440 900 ${v[1]} ${v[2]} ${v[3]} ${v[4]} " \
    -ApplePersistenceIgnoreState YES >/dev/null 2>&1 &
  sleep 8
  local win=$(swift_eval "import CoreGraphics
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in l where (w[kCGWindowOwnerPID as String] as? Int32) == $! && (w[kCGWindowLayer as String] as? Int) == 0 { print(w[kCGWindowNumber as String]!); break }")
  screencapture -x -o -l $win $3
  print "$3: $(sips -g pixelWidth -g pixelHeight $3 | awk '/pixel/ {printf "%s ", $2}')"
}

if [[ -n $dest ]]; then
  for l in $langs; do
    mkdir -p $dest/$l
    shoot dark true  $dest/$l/01.png $l
    shoot dark false $dest/$l/02.png $l
    shoot light true $dest/$l/03.png $l
  done
  exit 0
fi
mkdir -p $out && rm -f $out/*.png(N)
shoot dark true  $out/01-mac-game-dark.png
shoot dark false $out/02-mac-home-dark.png
shoot light true $out/03-mac-game-light.png
print "look at every frame before \`fastlane ios store_screenshots platform:mac\`"
