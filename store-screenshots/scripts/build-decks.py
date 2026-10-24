#!/usr/bin/env python3
"""Write Nine's store decks into app-store-screenshots.json from copy/store-copy.json.

    python3 scripts/build-decks.py [--device iphone|ipad|watchos|duo-inner-landscape|mac|tvos]

Six decks, ten locales each:
  iphone               9 slides, 1320x2868 (the 6.9" set; ASC scales the rest)
  ipad                 the same 9 slides, 2064x2752 (13" iPad)
  watchos              4 slides, 422x514 (Apple Watch Ultra 3; ASC scales the rest)
  duo-inner-landscape  4 slides, 2853x2007 (iPhone Duo, open)
  mac                  4 slides, 2880x1800
  tvos                 5 slides, 1920x1080 (Apple TV)

Copy lives in copy/store-copy.json; this file owns layout only. `--device`
picks which deck the editor (and a headless export) opens on.
"""
import argparse
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.join(ROOT, "app-store-screenshots.json")
COPY = json.load(open(os.path.join(ROOT, "copy", "store-copy.json")))
LOCALES = ["en", "de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "zh-Hans"]

A = "/screenshots/apple/"
SHOT = A + "iphone/{locale}/%02d.png"
IPAD = A + "ipad/{locale}/%02d.png"
WATCH = A + "watch/{locale}/%02d.png"
MAC = A + "mac/{locale}/%02d.png"
TV = A + "tv/{locale}/%02d.png"
OPEN = A + "duo-inner/landscape/{locale}/%02d.png"   # scripts/capture-duo.py
FOLDED = A + "duo-outer/portrait/%02d.png"


def t(x, y, w, h, z=4):
    return {"x": x, "y": y, "width": w, "height": h, "rotation": 0, "zIndex": z}


def img(id, src, x, y, w, h, fit="contain", z=3):
    return {"id": id, "src": src, "fit": fit, "transform": t(x, y, w, h, z)}


def copy(deck, key):
    block = COPY[deck][key]
    return ({lang: block[lang][0] for lang in LOCALES},
            {lang: block[lang][1] for lang in LOCALES})


def slide(deck, key, layout, screenshot="", unlabelled=False, **extra):
    label, headline = copy(deck, key)
    if unlabelled:
        label = {lang: "" for lang in LOCALES}
    s = dict(id=key, layout=layout, label=label, headline=headline, screenshot=screenshot)
    s.update(extra)
    return s


def framed(id, shot, frame, fw, fh, screen, x, y, width, z):
    """A capture under one of Apple's bezels in public/frames (cutouts from /api/frames)."""
    k = width / fw
    sx, sy, sw, sh = screen
    return [img(id + "-screen", A + shot, round(x + sx * k), round(y + sy * k),
                round(sw * k), round(sh * k), fit="cover", z=z),
            img(id + "-frame", "/frames/%s.png" % frame, x, y, round(width), round(fh * k), z=z + 1)]


BADGES = ["achievement-solve-first", "achievement-solve-ten", "achievement-solve-fifty",
          "achievement-sharp-first", "achievement-swift", "leaderboard-points"]


def closer_rows(x, y0, width, pitch, scale=1.0):
    """The closing slide's list: a glacier key over a white value, per row."""
    rows = COPY["closerRows"]
    text = []
    for i in range(len(rows["en"])):
        y = y0 + i * pitch
        text.append({"id": "k%d" % i, "text": {l: rows[l][i][0] for l in LOCALES},
                     "transform": t(x, y, width, round(50 * scale)), "fontSize": round(34 * scale),
                     "fontWeight": 600, "color": "#54ADFA", "align": "center"})
        text.append({"id": "v%d" % i, "text": {l: rows[l][i][1] for l in LOCALES},
                     "transform": t(x, y + round(54 * scale), width, round(90 * scale)),
                     "fontSize": round(64 * scale), "fontWeight": 500, "color": "#F5F5F7",
                     "align": "center"})
    return text


def extra(transforms, key):
    return {"transforms": transforms[key]} if transforms and key in transforms else {}


def ios_deck(shot, devices, badge_imgs, text, top, languages=(7, 8), transforms=None):
    """The nine iPhone slides; the iPad deck is the same story in its own captures."""
    return [
        slide("iphone", "hero", "hero", shot % 1),
        slide("iphone", "coach", "device-bottom", shot % 2, **extra(transforms, "coach")),
        slide("iphone", "variants", "hero", shot % 3),
        slide("iphone", "colors", "two-devices", shot % 4, screenshotSecondary=shot % 5, inverted=True),
        slide("iphone", "devices", "no-device", transforms={"caption": top}, imageElements=devices),
        # Two players on one puzzle: Nine's -parlor-demo session, dark and light.
        slide("iphone", "together", "two-devices", shot % 6, screenshotSecondary=shot % 9),
        slide("iphone", "gamecenter", "no-device", transforms={"caption": top}, imageElements=badge_imgs),
        # The locale's own screen in front of another language's.
        slide("iphone", "languages", "two-devices", shot % languages[0],
              screenshotSecondary=shot % languages[1]),
        slide("iphone", "closer", "no-device", transforms={"caption": top}, textElements=text),
    ]


def iphone_deck():
    devices = (framed("mac", "devices/mac.png", "mac", 3540, 2300, (329, 218, 2880, 1864), 40, 880, 1240, 1)
               + framed("tv", "devices/tv.png", "tv", 4300, 2780, (103, 119, 3840, 2160), 40, 1760, 1000, 3)
               + framed("watch", "devices/watch.png", "watch", 600, 960, (89, 223, 422, 514), 900, 2060, 400, 5))
    badge_imgs = [img("b%d" % i, A + "gamecenter/%s.png" % b,
                      150 + (i % 2) * 540, 900 + (i // 2) * 560, 480, 480) for i, b in enumerate(BADGES)]
    return ios_deck(SHOT, devices, badge_imgs, closer_rows(120, 1000, 1080, 225),
                    t(100, 260, 1120, 560))


def ipad_deck():
    """2064x2752: wider than the phone, so the badges go three abreast."""
    devices = (framed("mac", "devices/mac.png", "mac", 3540, 2300, (329, 218, 2880, 1864), 100, 820, 1500, 1)
               + framed("tv", "devices/tv.png", "tv", 4300, 2780, (103, 119, 3840, 2160), 560, 1660, 1400, 3)
               + framed("watch", "devices/watch.png", "watch", 600, 960, (89, 223, 422, 514), 1500, 760, 460, 5))
    badge_imgs = [img("b%d" % i, A + "gamecenter/%s.png" % b,
                      192 + (i % 3) * 590, 1000 + (i // 3) * 640, 500, 500) for i, b in enumerate(BADGES)]
    # Coach: the iPad drops below the two-line headline instead of covering it.
    coach = {"device": t(232, 900, 1600, 2133, z=2)}
    return ios_deck(IPAD, devices, badge_imgs, closer_rows(132, 860, 1800, 262, scale=1.45),
                    t(160, 200, 1744, 560), languages=(10, 11), transforms={"coach": coach})


def watch_deck():
    """422x514. No label line: at watch size the headline is all the room there is.

    The watch is drawn large, its lower band running off the bottom edge, so the
    screen gets half the canvas width and the board's digits stay legible."""
    big = {"device": t(66, 150, 290, 464, z=2)}
    return [slide("watch", key, "hero", WATCH % n, transforms=big)
            for n, key in enumerate(("hero", "box", "solved", "home"), 1)]


def duo_deck():
    return [
        slide("duo", "hero", "hero", OPEN % 1),
        slide("duo", "coach", "device-bottom", OPEN % 2),
        slide("duo", "both", "two-devices", OPEN % 4, screenshotSecondary=FOLDED % 4, inverted=True),
        slide("duo", "school", "hero", OPEN % 3),
    ]


def closer_grid(x, y0, column, pitch, scale):
    """The closing list in two columns, for the landscape canvases."""
    rows = COPY["closerRows"]
    half = (len(rows["en"]) + 1) // 2
    text = []
    for i in range(len(rows["en"])):
        cx, y = x + (i // half) * column, y0 + (i % half) * pitch
        text.append({"id": "k%d" % i, "text": {l: rows[l][i][0] for l in LOCALES},
                     "transform": t(cx, y, column, round(50 * scale)), "fontSize": round(34 * scale),
                     "fontWeight": 600, "color": "#54ADFA", "align": "center"})
        text.append({"id": "v%d" % i, "text": {l: rows[l][i][1] for l in LOCALES},
                     "transform": t(cx, y + round(54 * scale), column, round(90 * scale)),
                     "fontSize": round(64 * scale), "fontWeight": 500, "color": "#F5F5F7",
                     "align": "center"})
    return text


def mac_deck():
    """2880x1800. The Mac shelf shows tiers and Continue, not the three variants,
    so it carries the Watch's "pick up" line; the light board's label would
    claim accent colours it does not show, so it has none."""
    top = t(240, 140, 2400, 520)
    # The MacBook drawn large, its base off the bottom edge but the whole screen
    # (all nine rows of the board) above it.
    big = {"device": t(465, 590, 1950, 1267, z=2)}
    return [
        slide("iphone", "hero", "hero", MAC % 1, transforms=big),
        slide("watch", "home", "hero", MAC % 2, transforms=big),
        slide("iphone", "colors", "hero", MAC % 3, unlabelled=True, transforms=big),
        slide("iphone", "closer", "no-device", transforms={"caption": top},
              textElements=closer_grid(140, 760, 1300, 250, 1.15)),
    ]


def tv_deck():
    """The board, the digit ring, the shelf, settings beside the board.

    Laid out on the editor's 3840x2160 canvas (its first tvOS size) and exported
    at 1920x1080 too; the TV sits low enough that two-line headlines clear it."""
    top = t(320, 200, 3200, 720)
    low = {"device": t(620, 760, 2600, 1681, z=2)}
    return [
        slide("iphone", "hero", "hero", TV % 1, transforms=low),
        slide("tv", "ring", "hero", TV % 2, transforms=low),
        slide("watch", "home", "hero", TV % 3, transforms=low),
        slide("iphone", "colors", "hero", TV % 4, transforms=low),
        slide("iphone", "closer", "no-device", transforms={"caption": top},
              textElements=closer_grid(200, 900, 1720, 290, 1.4)),
    ]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", default="iphone", choices=("iphone", "ipad", "watchos", "duo-inner-landscape", "mac", "tvos"))
    args = parser.parse_args()
    state = json.load(open(PROJECT))
    state.update(appName="Nine", themeId="nine-glass", fontId="system-sans",
                 # Isolated: two-device layouts would otherwise bleed into neighbours.
                 connectedCanvas=False, locales=LOCALES, locale="en", device=args.device,
                 orientation="landscape" if args.device.endswith("landscape") else "portrait",
                 scene=dict(backdrop="spotlight", span=False, decoration="none", shadow=40, glow=0,
                            tilt=0, headlineWeight=600, headlineScale=1.25, headlineCase="as-typed",
                            captionAlign="auto"))
    state["slidesByDevice"]["iphone"] = iphone_deck()
    state["slidesByDevice"]["ipad"] = ipad_deck()
    state["slidesByDevice"]["watchos"] = watch_deck()
    state["slidesByDevice"]["duo-inner-landscape"] = duo_deck()
    state["slidesByDevice"]["mac"] = mac_deck()
    state["slidesByDevice"]["tvos"] = tv_deck()
    for deck in ("iphone", "ipad", "watchos", "duo-inner-landscape", "mac", "tvos"):
        state.setdefault("crossScreenMockupsByDevice", {})[deck] = []
    with open(PROJECT, "w") as handle:
        json.dump(state, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print("wrote %s (%s active)" % (os.path.relpath(PROJECT), args.device))


if __name__ == "__main__":
    main()
