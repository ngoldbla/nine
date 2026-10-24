#!/bin/zsh
# File capture-iphone.py's output into the editor: flatten alpha (App Store
# screenshots must be opaque) and add 08, a second language's home screen for
# the languages slide (Japanese, or English on the Japanese set).
#   zsh scripts/place-captures.sh <capture-out-dir>
set -euo pipefail
src=$1
dst=${0:A:h:h}/public/screenshots/apple/iphone
tmp=$(mktemp -d); trap 'rm -rf $tmp' EXIT
flat() { sips -s format jpeg -s formatOptions 100 $1 --out $tmp/x.jpg >/dev/null
         sips -s format png $tmp/x.jpg --out $2 >/dev/null; }
for dir in $src/*(/); do
  lang=${dir:t}
  mkdir -p $dst/$lang
  for f in $dir/*.png; do flat $f $dst/$lang/${f:t}; done
done
for dir in $dst/*(/); do
  lang=${dir:t}; partner=ja; [[ $lang == ja ]] && partner=en
  cp $dst/$partner/07.png $dst/$lang/08.png
done
print "placed: $(ls $dst | tr '\n' ' ')"

# The iPhone Duo frames are committed in fastlane/screenshots/ios-duo (only a
# person can unfold the simulator); file flattened copies for the Duo deck.
duo=${0:A:h:h:h}/fastlane/screenshots/ios-duo/en-US
app=${0:A:h:h}/public/screenshots/apple
mkdir -p $app/duo-inner/landscape $app/duo-outer/portrait
for n in 01 02 03 04; do
  flat $duo/$n-duo-open-*.png(N[1]) $app/duo-inner/landscape/$n.png
  flat $duo/$n-duo-folded-*.png(N[1]) $app/duo-outer/portrait/$n.png
done
print "placed the Duo frames"
