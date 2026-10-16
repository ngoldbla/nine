#!/bin/zsh
# Usage: watch-shots.sh <mode> — launches the probe in PROBE_MODE=<mode> on the
# Duo probe simulator, then screenshots both displays 3s after every hinge line.
export DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer
U=5B8C0158-1D1D-4893-AD33-C669512D1100
S=/private/tmp/claude-501/-Users-aquilops-nine/39f5188e-4357-417b-a0c5-7844ac940113/scratchpad
MODE=$1
LOG=$S/probe-$MODE.log
mkdir -p $S/shots-$MODE
: > $LOG
xcrun simctl launch --console-pty --terminate-running-process $U dev.scratch.duoprobe $MODE > $LOG 2>&1 &
n=0
seen=0
while true; do
  count=$(grep -c "\] hinge\|^DUOPROBE hinge" $LOG 2>/dev/null)
  if [[ $count -gt $seen ]]; then
    seen=$count
    sleep 3
    n=$((n+1))
    last=$(grep "hinge" $LOG | tail -1 | sed 's/.*hinge //; s/ /_/g')
    xcrun simctl io $U screenshot --display=primary $S/shots-$MODE/$n-$last-outer.png >/dev/null 2>&1
    xcrun simctl io $U screenshot --display=primary-1 $S/shots-$MODE/$n-$last-inner.png >/dev/null 2>&1
    echo "shot $n after: $last"
  fi
  sleep 1
done
