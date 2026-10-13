#!/bin/zsh
# Mac App Store screenshots: three 2880x1800 window captures of a Release build,
# photographed against the same quiet seeded state as the iOS lanes
# (nine/scripts/ninestate.py), into fastlane/screenshots/mac/en-US.
#
#   scripts/mac-store-shots.sh            # build, then capture
#   scripts/mac-store-shots.sh --no-build
#
# Needs Screen Recording permission for the app running this shell, and a
# Retina display whose visible frame fits a 1440x900pt window.
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

if [[ ${1:-} != --no-build ]]; then
  (cd $nine && xcodegen generate -q && xcodebuild -project Nine.xcodeproj -scheme Nine \
     -configuration Release -destination 'platform=macOS' -derivedDataPath .build/mac \
     build CODE_SIGNING_ALLOWED=NO -quiet)
fi

swift_eval() { print -r -- "$1" > $home/s.swift && swift $home/s.swift 2>/dev/null; }
visible=$(swift_eval 'import AppKit; let v = NSScreen.main!.visibleFrame; print(Int(v.minX), Int(v.minY), Int(v.width), Int(v.height))')
pointer_x=$(swift_eval 'import AppKit; print(Int(NSEvent.mouseLocation.x))')
(( pointer_x < 300 )) || { print "park the pointer at the far left edge of the screen first" >&2; exit 1; }

shoot() {  # appearance resume out.png
  pkill -f "$app/Contents/MacOS/Nine" 2>/dev/null || true; sleep 1
  local store="$home/Library/Application Support/CouchKit"
  rm -rf $store && mkdir -p $store
  (cd $nine && python3 - "$store" $1 $2 <<'EOF'
import json, os, sys
sys.path.insert(0, "scripts")
import ninestate
store, appearance, resume = sys.argv[1], sys.argv[2], sys.argv[3] == "true"
# NinePrefs stores the theme under its pre-theme key, "appearance".
prefs = dict(ninestate.PREFS_ERRORS_ON, appearance=appearance, resumeOnLaunch=resume)
for name, body in ninestate.quiet_blobs(prefs).items():
    open(os.path.join(store, name), "w").write(body)
EOF
  )
  local v=(${=visible})
  CFFIXED_USER_HOME=$home $app/Contents/MacOS/Nine \
    -"NSWindow Frame nine.main" "$((pointer_x + 40)) $((v[2] + 47)) 1440 900 ${v[1]} ${v[2]} ${v[3]} ${v[4]} " \
    -ApplePersistenceIgnoreState YES >/dev/null 2>&1 &
  sleep 8
  local win=$(swift_eval "import CoreGraphics
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in l where (w[kCGWindowOwnerPID as String] as? Int32) == $! && (w[kCGWindowLayer as String] as? Int) == 0 { print(w[kCGWindowNumber as String]!); break }")
  screencapture -x -o -l $win $3
  print "$3: $(sips -g pixelWidth -g pixelHeight $3 | awk '/pixel/ {printf "%s ", $2}')"
}

mkdir -p $out && rm -f $out/*.png(N)
shoot dark true  $out/01-mac-game-dark.png
shoot dark false $out/02-mac-home-dark.png
shoot light true $out/03-mac-game-light.png
print "look at every frame before \`fastlane ios store_screenshots platform:mac\`"
