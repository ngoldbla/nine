"""Every iPhone or iPad store frame, in each of Nine's ten languages.

    python3 store-screenshots/scripts/capture-ios.py [--device iphone|ipad] <out-dir> [locale ...]

Then `scripts/place-captures.sh <out-dir> [iphone|ipad]` flattens and files them
under public/screenshots/apple/<device>/<locale>/. An iPhone run also saves the
Killer board it opened in <out-dir>/killer/; pass that folder to an iPad run as
NINE_KILLER_STATE (see KILLER below).

Writes <out>/<locale>/NN.png, numbered as the deck uses them:
  01 board            02 coach             03 Killer board
  04 board, ember     05 board, meadow     06 SharePlay session (dark)
  07 home screen      09 SharePlay session (light)
  10 Technique School (iPad only: its shelf is mostly empty glass, so the iPad
     languages slide shows the School instead)
(08, a second language's home screen for the languages slide, is copied from
another locale's 07 by the caller.)

Same rig as Nine's shotlist (seeded board, 9:41 bar, mistake marks off), on the
6.9" `Nine-Store-iPhone` simulator (iPhone 17 Pro Max: no runtime here runs an
iPhone 18 Pro Max, and the slot is the same 1320x2868) or the 13"
`Nine-Store-iPad` (2064x2752), as shotlist's STORE_DEVICES names them. Needs a Debug build
installed (`-NineDebugSurface coach` and `-parlor-demo` are Debug-only); the
`store_screenshots_capture` lane or shotlist.py leaves one. Skips shotlist's
click-based rotation check, which drove Simulator.app (gone in Xcode 27). Tap
targets are looked up in the string catalog, because accessibility labels are
localised; waits are on time rather than labels for the same reason.
"""
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "nine", "scripts"))
import ninestate  # noqa: E402
import shotlist  # noqa: E402
import simrig  # noqa: E402

ARGS = sys.argv[1:]
DEVICE = "iphone"
if ARGS[:1] == ["--device"]:
    DEVICE, ARGS = ARGS[1], ARGS[2:]
STORE = shotlist.STORE_DEVICES["%s-store" % DEVICE]
OUT = ARGS[0]
LOCALES = ARGS[1:] or ["en", "de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "zh-Hans"]
APPLE_LOCALE = {"en": "en_US", "de": "de_DE", "es": "es_ES", "fr": "fr_FR", "it": "it_IT",
                "ja": "ja_JP", "ko": "ko_KR", "nl": "nl_NL", "pt-BR": "pt_BR", "zh-Hans": "zh_CN"}
CATALOG = json.load(open(os.path.join(REPO, "nine", "Sources", "Strings", "Localizable.xcstrings")))["strings"]
CALM = dict(ninestate.PREFS_ERRORS_OFF)
shotlist.rotate_device = lambda *a, **k: None


def L(key, lang):
    loc = CATALOG[key].get("localizations", {})
    unit = (loc.get(lang) or loc.get("en") or {}).get("stringUnit", {})
    return unit.get("value", key)


devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "--json"]))
udid = next(d["udid"] for rt in devices["devices"].values() for d in rt
            if d["name"] == STORE["sim_name"])
subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True)
subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture_output=True)
simrig.pin_status_bar(udid)
simrig.warm_up_bridge(udid)
shotlist.verify_tap_space(udid, shotlist.point_size(udid, STORE["scale"]))


def tap_label(label):
    data = simrig.wait_for(udid, label)
    simrig.tap(udid, data, label)
    time.sleep(1.0)


def tap_prefix(prefix):
    """Tap the element whose label starts with `prefix`, until it is gone.

    The tier tiles read "Gentle, Killer" (穏やか、キラー in Japanese), so the
    match is on the start. A tap read off a page that is still sliding in can
    land on the old frame (it did in ja, ko and zh-Hans), so wait for the page
    to settle and tap again while the tile is still there."""
    deadline = time.time() + 40
    tapped = False
    while time.time() < deadline:
        time.sleep(1.5)
        data = simrig.describe(udid, tolerate=True)
        hit = next((e["label"] for e in (data or {}).get("entries", [])
                    if (e.get("label") or "").startswith(prefix)), None)
        if hit is None and tapped:
            return
        if hit:
            simrig.tap(udid, data, hit)
            tapped = True
    raise SystemExit("could not open %r" % prefix)


# NINE_ONLY=3,7 retakes just those frames, leaving the rest of <out-dir> alone.
ONLY = {int(n) for n in os.environ.get("NINE_ONLY", "").split(",") if n}


def shot(path, prefs, args, appearance="dark", steps=(), wait=7, state=None):
    if ONLY and int(os.path.basename(path)[:2]) not in ONLY:
        return
    def go():
        subprocess.run(["xcrun", "simctl", "ui", udid, "appearance", appearance])
        blobs = ninestate.quiet_blobs(prefs)
        blobs.update(state or {})
        simrig.relaunch(udid, shotlist.BUNDLE_ID, blobs, args=list(args))
        time.sleep(wait)
        for step in steps:
            step()
        time.sleep(3)
        shotlist.shoot(udid, path)
        print("  ", path, flush=True)
    try:
        simrig.retrying_stale_touch(udid, go, os.path.basename(path))
    except SystemExit as exc:
        print("  FAILED", path, exc, flush=True)


# A channel board is two blobs: the library holds the board, and its cages live
# in `nine.channelRules` (AppModel). A library without the rules opens as a
# Killer board with no cages drawn.
KILLER_BLOBS = ("default.nine.library.json", "default.nine.channelRules.json")


def killer_state():
    """The seeded library with a Gentle Killer board open on top of it, and its cages.

    Opened once, in English, by tapping through the shelf; every locale then
    resumes it. Tapping the tier tile works in seven languages and silently
    does nothing in ja, ko and zh-Hans, so the taps are not repeated per locale."""
    subprocess.run(["xcrun", "simctl", "ui", udid, "appearance", "dark"])
    simrig.relaunch(udid, shotlist.BUNDLE_ID, ninestate.quiet_blobs(CALM),
                    args=["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
    time.sleep(7)
    tap_label(L("game.control.home", "en"))
    tap_label(L("channel.next", "en"))
    tap_label(L("channel.next", "en"))
    tap_prefix(L("difficulty.gentle.title", "en"))
    time.sleep(4)
    subprocess.run(["xcrun", "simctl", "terminate", udid, shotlist.BUNDLE_ID])
    time.sleep(2)
    container = subprocess.check_output(
        ["xcrun", "simctl", "get_app_container", udid, shotlist.BUNDLE_ID, "data"], text=True).strip()
    return {name: open(os.path.join(container, simrig.STORE_DIR, name)).read() for name in KILLER_BLOBS}


# The iPad's Gentle Killer tile ignores simulated taps in every language, so
# an iPad run resumes the board an iPhone run saved: NINE_KILLER_STATE.
if os.environ.get("NINE_KILLER_STATE"):
    KILLER = {name: open(os.path.join(os.environ["NINE_KILLER_STATE"], name)).read()
              for name in KILLER_BLOBS}
else:
    KILLER = killer_state()
    os.makedirs(os.path.join(OUT, "killer"), exist_ok=True)
    for name, body in KILLER.items():
        with open(os.path.join(OUT, "killer", name), "w") as handle:
            handle.write(body)

for lang in LOCALES:
    d = os.path.join(OUT, lang)
    os.makedirs(d, exist_ok=True)
    lang_args = ["-AppleLanguages", "(%s)" % lang, "-AppleLocale", APPLE_LOCALE[lang]]
    p = lambda n: os.path.join(d, "%02d.png" % n)  # noqa: E731
    print(lang, flush=True)
    shot(p(1), CALM, lang_args)
    shot(p(2), CALM, lang_args + ["-NineDebugSurface", "coach"], wait=12)
    shot(p(3), CALM, lang_args, state=KILLER)
    shot(p(4), dict(CALM, accent="ember"), lang_args)
    shot(p(5), dict(CALM, accent="meadow"), lang_args)
    shot(p(6), CALM, lang_args + ["-parlor-demo"], wait=11)
    shot(p(7), dict(CALM, resumeOnLaunch=False), lang_args)
    shot(p(9), CALM, lang_args + ["-parlor-demo"], appearance="light", wait=14)
    if DEVICE == "ipad":
        shot(p(10), dict(CALM, resumeOnLaunch=False), lang_args + ["-NineDebugSurface", "school"],
             wait=9)
subprocess.run(["xcrun", "simctl", "ui", udid, "appearance", "dark"])
print("done", flush=True)
