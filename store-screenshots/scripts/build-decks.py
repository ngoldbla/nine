#!/usr/bin/env python3
"""Write Nine's store decks into app-store-screenshots.json from copy/store-copy.json.

    python3 scripts/build-decks.py [--device iphone|duo-inner-landscape]

Two decks, ten locales each:
  iphone               9 slides, 1320x2868 (the 6.9" set; ASC scales the rest)
  duo-inner-landscape  4 slides, 2853x2007 (iPhone Duo, open)

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
OPEN = A + "duo-inner/landscape/%02d.png"      # English only: see README
FOLDED = A + "duo-outer/portrait/%02d.png"


def t(x, y, w, h, z=4):
    return {"x": x, "y": y, "width": w, "height": h, "rotation": 0, "zIndex": z}


def img(id, src, x, y, w, h, fit="contain", z=3):
    return {"id": id, "src": src, "fit": fit, "transform": t(x, y, w, h, z)}


def copy(deck, key):
    block = COPY[deck][key]
    return ({lang: block[lang][0] for lang in LOCALES},
            {lang: block[lang][1] for lang in LOCALES})


def slide(deck, key, layout, screenshot="", **extra):
    label, headline = copy(deck, key)
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


def iphone_deck():
    devices = (framed("mac", "devices/mac.png", "mac", 3540, 2300, (329, 218, 2880, 1864), 40, 880, 1240, 1)
               + framed("tv", "devices/tv.png", "tv", 4300, 2780, (103, 119, 3840, 2160), 40, 1760, 1000, 3)
               + framed("watch", "devices/watch.png", "watch", 600, 960, (89, 223, 422, 514), 900, 2060, 400, 5))
    badges = ["achievement-solve-first", "achievement-solve-ten", "achievement-solve-fifty",
              "achievement-sharp-first", "achievement-swift", "leaderboard-points"]
    badge_imgs = [img("b%d" % i, A + "gamecenter/%s.png" % b,
                      150 + (i % 2) * 540, 900 + (i // 2) * 560, 480, 480) for i, b in enumerate(badges)]
    rows = COPY["closerRows"]
    text = []
    for i in range(len(rows["en"])):
        y = 1000 + i * 225
        text.append({"id": "k%d" % i, "text": {l: rows[l][i][0] for l in LOCALES},
                     "transform": t(120, y, 1080, 50), "fontSize": 34, "fontWeight": 600,
                     "color": "#54ADFA", "align": "center"})
        text.append({"id": "v%d" % i, "text": {l: rows[l][i][1] for l in LOCALES},
                     "transform": t(120, y + 54, 1080, 90), "fontSize": 64, "fontWeight": 500,
                     "color": "#F5F5F7", "align": "center"})
    top = t(100, 260, 1120, 560)
    return [
        slide("iphone", "hero", "hero", SHOT % 1),
        slide("iphone", "coach", "device-bottom", SHOT % 2),
        slide("iphone", "variants", "hero", SHOT % 3),
        slide("iphone", "colors", "two-devices", SHOT % 4, screenshotSecondary=SHOT % 5, inverted=True),
        slide("iphone", "devices", "no-device", transforms={"caption": top}, imageElements=devices),
        # Two players on one puzzle: Nine's -parlor-demo session, dark and light.
        slide("iphone", "together", "two-devices", SHOT % 6, screenshotSecondary=SHOT % 9),
        slide("iphone", "gamecenter", "no-device", transforms={"caption": top}, imageElements=badge_imgs),
        # The locale's own home screen in front of another language's (08).
        slide("iphone", "languages", "two-devices", SHOT % 7, screenshotSecondary=SHOT % 8),
        slide("iphone", "closer", "no-device", transforms={"caption": top}, textElements=text),
    ]


def duo_deck():
    return [
        slide("duo", "hero", "hero", OPEN % 1),
        slide("duo", "coach", "device-bottom", OPEN % 2),
        slide("duo", "both", "two-devices", OPEN % 4, screenshotSecondary=FOLDED % 4, inverted=True),
        slide("duo", "school", "hero", OPEN % 3),
    ]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", default="iphone", choices=("iphone", "duo-inner-landscape"))
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
    state["slidesByDevice"]["duo-inner-landscape"] = duo_deck()
    for deck in ("iphone", "duo-inner-landscape"):
        state.setdefault("crossScreenMockupsByDevice", {})[deck] = []
    with open(PROJECT, "w") as handle:
        json.dump(state, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print("wrote %s (%s active)" % (os.path.relpath(PROJECT), args.device))


if __name__ == "__main__":
    main()
