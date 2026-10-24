#!/bin/zsh
# File capture-ios.py's, capture-watch.py's or capture-duo.py's output into the editor: flatten
# alpha (App Store screenshots must be opaque) and, for iPhone and iPad, add a
# second language's screen for the languages slide (Japanese, or English on the
# Japanese set): 08 from its home screen, and on iPad 11 from its School.
#   zsh scripts/place-captures.sh <capture-out-dir> [iphone|ipad|watch|duo|mac|tv]
set -euo pipefail
src=$1
device=${2:-iphone}
app=${0:A:h:h}/public/screenshots/apple
dst=$app/$device
[[ $device == duo ]] && dst=$app/duo-inner/landscape
tmp=$(mktemp -d); trap 'rm -rf $tmp' EXIT
flat() { sips -s format jpeg -s formatOptions 100 $1 --out $tmp/x.jpg >/dev/null
         sips -s format png $tmp/x.jpg --out $2 >/dev/null; }
for dir in $src/*(/); do
  lang=${dir:t}
  mkdir -p $dst/$lang
  for f in $dir/*.png; do flat $f $dst/$lang/${f:t}; done
done
print "placed $device: $(ls $dst | tr '\n' ' ')"
[[ $device == (watch|duo|mac|tv) ]] && exit 0
for dir in $dst/*(/); do
  lang=${dir:t}; partner=ja; [[ $lang == ja ]] && partner=en
  cp $dst/$partner/07.png $dst/$lang/08.png
  if [[ -f $dst/$partner/10.png ]]; then cp $dst/$partner/10.png $dst/$lang/11.png; fi
done
[[ $device == ipad ]] && exit 0

# The folded Duo board (the "both screens" slide) shows no language, so the
# committed English frame in fastlane/screenshots/ios-duo serves every locale.
# The open frames come from capture-duo.py, placed with `duo` above.
duo=${0:A:h:h:h}/fastlane/screenshots/ios-duo/en-US
mkdir -p $app/duo-outer/portrait
flat $duo/04-duo-folded-game-light.png $app/duo-outer/portrait/04.png
print "placed the folded Duo frame"
