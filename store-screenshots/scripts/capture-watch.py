"""The Apple Watch store frames, in each of Nine's ten languages.

    python3 store-screenshots/scripts/capture-watch.py <out-dir> [locale ...]

Then `scripts/place-captures.sh <out-dir> watch` files them under
public/screenshots/apple/watch/<locale>/.

Writes <out>/<locale>/NN.png at 422x514 (Ultra 3, 49mm), numbered as the deck
uses them:
  01 the board (the 9x9 map)    02 one box under the lens, a cell selected
  03 the solve celebration      04 the home list

On the `Nine-Store-Watch` simulator with NineWatch installed. Nothing is tapped
except the home button for 04: each frame is a seeded `nine.watch.board` slot
(WatchModel restores the screen it names), and the puzzle is the same frozen
fixture board the phone frames use. `simctl status_bar` does nothing on
watchOS, so the watch clock is whatever the Mac's is.
"""
import copy
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "nine", "scripts"))
import ninestate  # noqa: E402
import simrig  # noqa: E402

BUNDLE_ID = "com.couchsuite.nine.watchkitapp"
OUT = sys.argv[1]
LOCALES = sys.argv[2:] or ["en", "de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "zh-Hans"]
APPLE_LOCALE = {"en": "en_US", "de": "de_DE", "es": "es_ES", "fr": "fr_FR", "it": "it_IT",
                "ja": "ja_JP", "ko": "ko_KR", "nl": "nl_NL", "pt-BR": "pt_BR", "zh-Hans": "zh_CN"}

devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "--json"]))
udid = next(d["udid"] for rt in devices["devices"].values() for d in rt
            if d["name"] == "Nine-Store-Watch")
subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True)
subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture_output=True)

GAME = json.load(open(ninestate.FIXTURE))["entries"][0]["game"]
# The fixture carries one wrong digit for the phone's error-marking baselines;
# the watch marks mistakes whatever the phone's setting, so put it right.
ANSWER = GAME["puzzle"]["solution"]["cells"]
GAME["entries"] = [ANSWER[i] if v else 0 for i, v in enumerate(GAME["entries"])]
SOLVED = copy.deepcopy(GAME)
SOLVED["entries"] = list(GAME["puzzle"]["solution"]["cells"])
SOLVED["pencil"] = [0] * 81


def slot(game, box=None, cell=None):
    body = {"game": game}
    if box is not None:
        body["box"] = box
    if cell is not None:
        body["cell"] = cell
    return {"default.nine.watch.board.json": json.dumps(body, sort_keys=True)}


def shot(path, blobs, args, wait=6, then=None):
    simrig.relaunch(udid, BUNDLE_ID, blobs, args=list(args))
    time.sleep(wait)
    if then:
        then()
        time.sleep(3)
    subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", path], check=True,
                   capture_output=True)
    print("  ", path, flush=True)


def tap_home():
    # The home button sits top-left in the watch's toolbar (WatchApp.swift).
    subprocess.run(["sim-use", "tap", "--udid", udid, "-x", "30", "-y", "30"], capture_output=True)


for lang in LOCALES:
    d = os.path.join(OUT, lang)
    os.makedirs(d, exist_ok=True)
    lang_args = ["-AppleLanguages", "(%s)" % lang, "-AppleLocale", APPLE_LOCALE[lang]]
    p = lambda n: os.path.join(d, "%02d.png" % n)  # noqa: E731
    print(lang, flush=True)
    shot(p(1), slot(GAME), lang_args)
    shot(p(2), slot(GAME, box=4, cell=40), lang_args)
    shot(p(3), slot(SOLVED), lang_args, wait=4)
    shot(p(4), slot(GAME), lang_args, then=tap_home)
print("done", flush=True)
