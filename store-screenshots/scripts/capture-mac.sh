#!/bin/zsh
# One Mac frame of the board in play: scripts/mac-store-shots.sh's recipe (Release
# build, seeded quiet state, throwaway home, 1440x900pt window), with mistake
# marks off and the selected centre cell filled with its digit (2), so every 2
# on the board lights up.
#   zsh store-screenshots/scripts/capture-mac.sh public/screenshots/apple/devices/mac.png
# Moves the pointer to the left screen edge, as the original script asks.
set -euo pipefail
out=$1
nine=${0:A:h:h:h}/nine
app=$nine/.build/mac/Build/Products/Release/Nine.app
home=$(mktemp -d)
trap 'pkill -f "$app/Contents/MacOS/Nine" 2>/dev/null; rm -rf "$home"' EXIT
swift_eval() { print -r -- "$1" > $home/s.swift && swift $home/s.swift 2>/dev/null; }

# The script's hover trap: park the pointer at the left edge before the window opens.
swift_eval 'import CoreGraphics; CGWarpMouseCursorPosition(CGPoint(x: 5, y: 450))'
visible=$(swift_eval 'import AppKit; let v = NSScreen.main!.visibleFrame; print(Int(v.minX), Int(v.minY), Int(v.width), Int(v.height))')
pointer_x=$(swift_eval 'import AppKit; print(Int(NSEvent.mouseLocation.x))')
(( pointer_x < 300 )) || { print "pointer did not park" >&2; exit 1; }

pkill -f "$app/Contents/MacOS/Nine" 2>/dev/null || true; sleep 1
store="$home/Library/Application Support/CouchKit"
mkdir -p $store
(cd $nine && python3 - "$store" <<'EOF'
import json, os, sys
sys.path.insert(0, "scripts")
import ninestate
prefs = dict(ninestate.PREFS_ERRORS_OFF, appearance="dark", resumeOnLaunch=True)
for name, body in ninestate.quiet_blobs(prefs).items():
    open(os.path.join(sys.argv[1], name), "w").write(body)
EOF
)
v=(${=visible})
CFFIXED_USER_HOME=$home $app/Contents/MacOS/Nine \
  -"NSWindow Frame nine.main" "$((pointer_x + 40)) $((v[2] + 47)) 1440 900 ${v[1]} ${v[2]} ${v[3]} ${v[4]} " \
  -ApplePersistenceIgnoreState YES >/dev/null 2>&1 &
pid=$!
sleep 8
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $pid) to true" \
          -e 'delay 1' -e 'tell application "System Events" to keystroke "2"' || print "keystroke failed" >&2
sleep 3
win=$(swift_eval "import CoreGraphics
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in l where (w[kCGWindowOwnerPID as String] as? Int32) == $pid && (w[kCGWindowLayer as String] as? Int) == 0 { print(w[kCGWindowNumber as String]!); break }")
screencapture -x -o -l $win $out
print "$out: $(sips -g pixelWidth -g pixelHeight $out | awk '/pixel/ {printf "%s ", $2}')"
