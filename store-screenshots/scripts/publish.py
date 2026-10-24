#!/usr/bin/env python3
"""File the editor's exports as the upload-ready set in fastlane/screenshots/marketing.

    python3 scripts/publish.py [--iphone zip] [--ipad zip] [--watch zip] [--duo zip]

Each device given replaces that device's files in every locale and leaves the
others alone, so one deck can be re-exported without re-rendering the rest.
Writes fastlane/screenshots/marketing/<App Store locale>/:
  01-iphone-hero.jpg … 09-iphone-closer.jpg   6.9" iPhone, 1320x2868
  11-ipad-hero.jpg … 19-ipad-closer.jpg       13" iPad, 2064x2752
  21-duo-hero.jpg …                           iPhone Duo open, 2853x2007
  31-watch-hero.jpg … 34-watch-home.jpg       Apple Watch Ultra 3, 422x514

JPEG at quality 92, which App Store Connect accepts: the PNGs are ~1.4 MB a
slide and this repo's history cannot be rewritten to drop them later (see
CLAUDE.md, build numbers). Only the largest size of each display is kept; App
Store Connect scales it to the smaller ones.

If the Duo captures exist in English only (see the folder README), pass
--duo-english-only: the coach and Technique School slides, whose screens show
English text, are then filed for en-US alone.
"""
import argparse
import glob
import os
import subprocess
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(os.path.dirname(ROOT), "fastlane", "screenshots", "marketing")

# Editor locale → App Store Connect locale.
ASC = {"en": "en-US", "de": "de-DE", "es": "es-ES", "fr": "fr-FR", "it": "it",
       "ja": "ja", "ko": "ko", "nl": "nl-NL", "pt-BR": "pt-BR", "zh-Hans": "zh-Hans"}
IOS = ["hero", "coach", "variants", "colors", "devices", "together", "gamecenter",
       "languages", "closer"]
# device → (editor deck, export size, first file number, file label, slide keys)
DECKS = {
    "iphone": ("iphone", "1320x2868", 1, "iphone", IOS),
    "ipad": ("ipad", "2064x2752", 11, "ipad", IOS),
    "duo": ("duo-inner-landscape", "2853x2007", 21, "duo", ["hero", "coach", "both", "school"]),
    "watch": ("watchos", "422x514", 31, "watch", ["hero", "box", "solved", "home"]),
}
DUO_LANGUAGE_FREE = {"hero", "both"}


def jpeg(src, dst):
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "92", src,
                    "--out", dst], check=True, capture_output=True)


def slides(tmp, zip_path, deck, size):
    with zipfile.ZipFile(zip_path) as archive:
        archive.extractall(tmp)
    base = os.path.join(tmp, "ios", deck, size)
    for lang in sorted(os.listdir(base)):
        for name in sorted(os.listdir(os.path.join(base, lang))):
            yield lang, int(name[:2]), os.path.join(base, lang, name)


def main():
    parser = argparse.ArgumentParser()
    for device in DECKS:
        parser.add_argument("--" + device, metavar="ZIP")
    parser.add_argument("--duo-english-only", action="store_true")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        for device, (deck, size, first, label, keys) in DECKS.items():
            zip_path = getattr(args, device)
            if not zip_path:
                continue
            for old in glob.glob(os.path.join(OUT, "*", "[0-9][0-9]-%s-*.jpg" % label)):
                os.remove(old)
            for lang, n, path in slides(os.path.join(tmp, device), zip_path, deck, size):
                key = keys[n - 1]
                if (device == "duo" and args.duo_english_only and lang != "en"
                        and key not in DUO_LANGUAGE_FREE):
                    continue
                dest = os.path.join(OUT, ASC[lang])
                os.makedirs(dest, exist_ok=True)
                jpeg(path, os.path.join(dest, "%02d-%s-%s.jpg" % (first + n - 1, label, key)))
    for loc in sorted(os.listdir(OUT)):
        if os.path.isdir(os.path.join(OUT, loc)):
            print(loc, len(os.listdir(os.path.join(OUT, loc))))


if __name__ == "__main__":
    main()
