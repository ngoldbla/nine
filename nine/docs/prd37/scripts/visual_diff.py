#!/usr/bin/env python3
"""Throwaway: main vs branch screenshots of the launch-reachable scenes on
iPhone 17 Pro and iPad Pro 11" (iOS 26.5), light and dark, then a pixel diff.

    visual_diff.py <main.app> <branch.app> <outdir>
"""
import os
import sys
import time

import numpy as np
from PIL import Image

sys.path.insert(0, "/Users/aquilops/nine/nine/scripts")
os.environ["NINE_SIMSLIM"] = "0"
import ninestate  # noqa: E402
import simrig  # noqa: E402

BUNDLE = "com.couchsuite.nine"
main_app, branch_app, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)
runtime = simrig.ios_runtime("26.5")
DEVICES = [("iphone", "Nine-Shotlist-iPhone", "iPhone 17 Pro"),
           ("ipad", "Nine-Shotlist-iPad", "iPad Pro 11-inch (M5)")]
SCENES = {"game": True, "home": False}  # resumeOnLaunch

for key, name, dtype in DEVICES:
    udid = simrig.prepare_simulator(runtime, name, dtype, erase=True)
    for tag, app in (("main", main_app), ("branch", branch_app)):
        simrig.run(["xcrun", "simctl", "install", udid, app])
        for appearance in ("light", "dark"):
            simrig.run(["xcrun", "simctl", "ui", udid, "appearance", appearance], check=False)
            for scene, resume in SCENES.items():
                prefs = dict(ninestate.PREFS_ERRORS_ON, resumeOnLaunch=resume)
                simrig.relaunch(udid, BUNDLE, ninestate.quiet_blobs(prefs))
                # Ready means the scene's own element is in the tree, not a clock.
                ready = False
                for _ in range(60):
                    tree = simrig.describe(udid, tolerate=True) or {"entries": []}
                    labels = [e.get("label", "") for e in tree["entries"]]
                    if (resume and "Row 1, column 1" in labels) or \
                       (not resume and any(l.startswith("Gentle") for l in labels)):
                        ready = True
                        break
                    time.sleep(2)
                if not ready:
                    print("NOT READY: %s %s %s %s" % (key, tag, appearance, scene))
                time.sleep(3)  # let launch animations settle
                path = os.path.join(out, "%s-%s-%s-%s.png" % (key, appearance, scene, tag))
                simrig.run(["xcrun", "simctl", "io", udid, "screenshot", "--type=png", path])

print("%-26s %10s %10s %8s" % ("shot", "px>8", "px>32", "max"))
for f in sorted(os.listdir(out)):
    if not f.endswith("-main.png"):
        continue
    a = np.asarray(Image.open(os.path.join(out, f)).convert("RGB"), dtype=np.int16)
    b = np.asarray(Image.open(os.path.join(out, f.replace("-main", "-branch"))).convert("RGB"), dtype=np.int16)
    if a.shape != b.shape:
        print("%-26s SIZE %s vs %s" % (f[:-9], a.shape, b.shape))
        continue
    d = np.abs(a - b).max(axis=2)
    total = d.size
    print("%-26s %9.3f%% %9.3f%% %8d" % (f[:-9], 100 * (d > 8).sum() / total,
                                         100 * (d > 32).sum() / total, d.max()))
