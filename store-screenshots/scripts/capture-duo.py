"""The open iPhone Duo store frames, in each of Nine's ten languages.

    DEVELOPER_DIR=/Applications/Xcode-27.1.app/Contents/Developer \
        python3 store-screenshots/scripts/capture-duo.py <out-dir> [locale ...]

Then `scripts/place-captures.sh <out-dir> duo` files them under
public/screenshots/apple/duo-inner/landscape/<locale>/.

Writes <out>/<locale>/NN.png at 2853x2007 (the inner panel), numbered as the
Duo deck uses them:
  01 board (dark)    02 coach (dark)    03 Technique School (dark)
  04 board (light)

On `Nine-Shotlist-Duo` with a Debug build installed and **Device Hub's posture
already set to Open** by a person: no tool can set it (PRD-37 §1.6), and it
survives relaunch, so one press covers the whole run. The posture is checked
from the first frame's size rather than asked for on stdin. Each scene is
reached by launch alone, through shotlist's own `duo_launch` table, because
neither taps nor the accessibility bridge reach the open inner panel; mistake
marking is off. The folded board on the "both screens" slide shows no
language and stays the committed English frame in fastlane/screenshots/ios-duo.
"""
import json
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "nine", "scripts"))
import ninestate  # noqa: E402
import shotlist  # noqa: E402
import simrig  # noqa: E402

OUT = sys.argv[1]
LOCALES = sys.argv[2:] or ["en", "de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "zh-Hans"]
APPLE_LOCALE = {"en": "en_US", "de": "de_DE", "es": "es_ES", "fr": "fr_FR", "it": "it_IT",
                "ja": "ja_JP", "ko": "ko_KR", "nl": "nl_NL", "pt-BR": "pt_BR", "zh-Hans": "zh_CN"}
FRAMES = [(1, "game", "dark"), (2, "coach", "dark"), (3, "school", "dark"), (4, "game", "light")]
OPEN_SIZE = (2853, 2007)

devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "--json"]))
udid = next(d["udid"] for rt in devices["devices"].values() for d in rt
            if d["name"] == "Nine-Shotlist-Duo" and d["state"] == "Booted")
simrig.pin_status_bar(udid)


def shot(path, scene, appearance, lang):
    resume, surface = shotlist.duo_launch(scene)
    subprocess.run(["xcrun", "simctl", "ui", udid, "appearance", appearance])
    prefs = dict(ninestate.PREFS_ERRORS_OFF, resumeOnLaunch=resume)
    args = ["-AppleLanguages", "(%s)" % lang, "-AppleLocale", APPLE_LOCALE[lang]] + surface
    simrig.relaunch(udid, shotlist.BUNDLE_ID, ninestate.quiet_blobs(prefs), args)
    grab = lambda: subprocess.run(simrig.screenshot_args(udid, path, "png", "open"),  # noqa: E731
                                  check=True, capture_output=True)
    shotlist.settle_by_pixels(grab, path)
    print("  ", path, flush=True)


for lang in LOCALES:
    d = os.path.join(OUT, lang)
    os.makedirs(d, exist_ok=True)
    print(lang, flush=True)
    for n, scene, appearance in FRAMES:
        path = os.path.join(d, "%02d.png" % n)
        shot(path, scene, appearance, lang)
        from PIL import Image
        if Image.open(path).size != OPEN_SIZE:
            sys.exit("%s is %s, not the open inner panel: set Device Hub's posture to Open"
                     % (path, Image.open(path).size))
subprocess.run(["xcrun", "simctl", "ui", udid, "appearance", "dark"])
print("done", flush=True)
