#!/usr/bin/env python3
"""Throwaway driver for the PRD-37 device session (not committed).

    duo_session.py install            # install the 27.1 build, seed the quiet game, launch
    duo_session.py shot <name>        # screenshot both Duo panels as <name>-inner/-outer.png
"""
import os
import subprocess
import sys

REPO = "/Users/aquilops/nine/nine"
sys.path.insert(0, os.path.join(REPO, "scripts"))
os.environ["DEVELOPER_DIR"] = "/Applications/Xcode-27.1.app/Contents/Developer"

import ninestate  # noqa: E402
import simrig  # noqa: E402

UDID = "5B8C0158-1D1D-4893-AD33-C669512D1100"
APP = os.path.join(REPO, "build271/Build/Products/Debug-iphonesimulator/Nine.app")
OUT = "/private/tmp/claude-501/-Users-aquilops-nine/39f5188e-4357-417b-a0c5-7844ac940113/scratchpad/duo-shots"
BUNDLE = "com.couchsuite.nine"


def install():
    simrig.run(["xcrun", "simctl", "install", UDID, APP])
    simrig.pin_status_bar(UDID)
    simrig.relaunch(UDID, BUNDLE, ninestate.quiet_blobs(ninestate.PREFS_ERRORS_ON))
    print("launched")


def shot(name):
    os.makedirs(OUT, exist_ok=True)
    for display, suffix in (("primary-1", "inner"), ("primary", "outer")):
        path = os.path.join(OUT, "%s-%s.png" % (name, suffix))
        subprocess.run(["xcrun", "simctl", "io", UDID, "screenshot",
                        "--display=" + display, path], capture_output=True)
        print(path)


if __name__ == "__main__":
    {"install": lambda: install(), "shot": lambda: shot(sys.argv[2])}[sys.argv[1]]()
