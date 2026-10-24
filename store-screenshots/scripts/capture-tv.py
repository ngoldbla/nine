"""The Apple TV store frames, in each of Nine's ten languages.

    python3 store-screenshots/scripts/capture-tv.py <out-dir> [locale ...]

Then `scripts/place-captures.sh <out-dir> tv` files them under
public/screenshots/apple/tv/<locale>/.

Writes <out>/<locale>/NN.png at 1920x1080, numbered as the deck uses them:
  01 the board             02 the digit ring open on the board
  03 the shelf             04 settings beside the board

On the `Apple TV 4K (3rd generation) (at 1080p)` simulator with a tvOS Debug
build installed. tvOS keeps CouchKit's store in Application Support like every
other platform, so each frame is the same seeded container the phone frames use
(ninestate.py), with the timer and mistake marking off. Xcode 27 has no
Simulator.app and nothing reaches the tvOS focus engine from outside, so the
two frames that need input are driven by the Debug-only `-NineRemoteInjector`
(RemoteInjector.swift): `tap` opens the ring, and a held click (`hold`, then
`holdEnd`) opens settings, as GameScreen.swift maps them.
"""
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "nine", "scripts"))
import ninestate  # noqa: E402
import simrig  # noqa: E402

BUNDLE_ID = "com.couchsuite.nine"
OUT = sys.argv[1]
LOCALES = sys.argv[2:] or ["en", "de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "zh-Hans"]
APPLE_LOCALE = {"en": "en_US", "de": "de_DE", "es": "es_ES", "fr": "fr_FR", "it": "it_IT",
                "ja": "ja_JP", "ko": "ko_KR", "nl": "nl_NL", "pt-BR": "pt_BR", "zh-Hans": "zh_CN"}
QUIET = dict(ninestate.PREFS_ERRORS_OFF, showTimer=False)

devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "--json"]))
udid = next(d["udid"] for rt in devices["devices"].values() for d in rt
            if d["name"] == "Apple TV 4K (3rd generation) (at 1080p)")
subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True)
subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture_output=True)


def inject(command):
    subprocess.run(["xcrun", "simctl", "spawn", udid, "notifyutil", "-p",
                    "com.couchsuite.nine.inject." + command], check=True)


def shot(path, prefs, lang, steps=(), wait=12):
    args = ["-AppleLanguages", "(%s)" % lang, "-AppleLocale", APPLE_LOCALE[lang],
            "-NineRemoteInjector"]
    simrig.relaunch(udid, BUNDLE_ID, ninestate.quiet_blobs(prefs), args=args)
    # A launch straight after a terminate sometimes lands on the tvOS home
    # screen; launching the running app again only brings it to the front.
    time.sleep(4)
    subprocess.run(["xcrun", "simctl", "launch", udid, BUNDLE_ID] + args, capture_output=True)
    time.sleep(wait)
    for step in steps:
        inject(step)
        time.sleep(1.5)
    # Past the transient chrome and the once-per-launch legend.
    time.sleep(10)
    subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", "--type=png", path],
                   check=True, capture_output=True)
    print("  ", path, flush=True)


for lang in LOCALES:
    d = os.path.join(OUT, lang)
    os.makedirs(d, exist_ok=True)
    p = lambda n: os.path.join(d, "%02d.png" % n)  # noqa: E731
    print(lang, flush=True)
    shot(p(1), QUIET, lang)
    shot(p(2), QUIET, lang, steps=["tap"])
    shot(p(3), dict(QUIET, resumeOnLaunch=False), lang)
    shot(p(4), QUIET, lang, steps=["hold", "holdEnd"])
print("done", flush=True)
