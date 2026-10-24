#!/usr/bin/env python3
"""File the editor's exports as the upload-ready set in fastlane/screenshots/marketing.

    python3 scripts/publish.py <iphone-export.zip> <duo-export.zip>

Writes fastlane/screenshots/marketing/<App Store locale>/:
  01-iphone-hero.jpg … 09-iphone-closer.jpg   6.9" iPhone, 1320x2868
  21-duo-hero.jpg …                           iPhone Duo open, 2853x2007

JPEG at quality 92, which App Store Connect accepts: the PNGs are ~1.4 MB a
slide and this repo's history cannot be rewritten to drop them later (see
CLAUDE.md, build numbers). Only the 6.9" iPhone size is kept; App Store
Connect scales it to the smaller iPhones.

The Duo captures exist in English only (no tool can unfold the simulator), so
the coach and Technique School slides, whose screens show English text, are
filed for en-US alone; every other locale gets the two board-only Duo slides.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(os.path.dirname(ROOT), "fastlane", "screenshots", "marketing")

# Editor locale → App Store Connect locale.
ASC = {"en": "en-US", "de": "de-DE", "es": "es-ES", "fr": "fr-FR", "it": "it",
       "ja": "ja", "ko": "ko", "nl": "nl-NL", "pt-BR": "pt-BR", "zh-Hans": "zh-Hans"}
IPHONE = ["hero", "coach", "variants", "colors", "devices", "together", "gamecenter",
          "languages", "closer"]
DUO = ["hero", "coach", "both", "school"]
DUO_LANGUAGE_FREE = {"hero", "both"}


def jpeg(src, dst):
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "92", src,
                    "--out", dst], check=True, capture_output=True)


def slides(tmp, zip_path, device, size):
    with zipfile.ZipFile(zip_path) as archive:
        archive.extractall(tmp)
    base = os.path.join(tmp, "ios", device, size)
    for lang in sorted(os.listdir(base)):
        for name in sorted(os.listdir(os.path.join(base, lang))):
            yield lang, int(name[:2]), os.path.join(base, lang, name)


def main():
    iphone_zip, duo_zip = sys.argv[1:3]
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    with tempfile.TemporaryDirectory() as tmp:
        for lang, n, path in slides(os.path.join(tmp, "i"), iphone_zip, "iphone", "1320x2868"):
            dest = os.path.join(OUT, ASC[lang])
            os.makedirs(dest, exist_ok=True)
            jpeg(path, os.path.join(dest, "%02d-iphone-%s.jpg" % (n, IPHONE[n - 1])))
        for lang, n, path in slides(os.path.join(tmp, "d"), duo_zip, "duo-inner-landscape", "2853x2007"):
            key = DUO[n - 1]
            if lang != "en" and key not in DUO_LANGUAGE_FREE:
                continue
            jpeg(path, os.path.join(OUT, ASC[lang], "%02d-duo-%s.jpg" % (20 + n, key)))
    for loc in sorted(os.listdir(OUT)):
        print(loc, len(os.listdir(os.path.join(OUT, loc))))


if __name__ == "__main__":
    main()
