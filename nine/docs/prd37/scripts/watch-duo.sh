#!/bin/zsh
# Screenshot both Duo panels every 4 s into $1 (a fresh directory), for at most 30 min.
export DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer
U=5B8C0158-1D1D-4893-AD33-C669512D1100
D=$1; mkdir -p $D
for i in $(seq -w 1 450); do
  xcrun simctl io $U screenshot --display=primary-1 $D/$i-inner.png >/dev/null 2>&1
  xcrun simctl io $U screenshot --display=primary $D/$i-outer.png >/dev/null 2>&1
  sleep 4
done
