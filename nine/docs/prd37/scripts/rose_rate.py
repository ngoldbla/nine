#!/usr/bin/env python3
"""Throwaway: how often does tapping the first empty cell open the rose?

    rose_rate.py <app> <tries>

Uses the AX harness's own pieces on its own iPhone 17 Pro / iOS 26.5 simulator,
so the only variable is the app.
"""
import os
import sys
import time

sys.path.insert(0, "/Users/aquilops/nine/nine/scripts")
import ninestate  # noqa: E402
import simrig  # noqa: E402

BUNDLE = "com.couchsuite.nine"
app, tries = sys.argv[1], int(sys.argv[2])
os.environ["NINE_SIMSLIM"] = "0"
runtime = simrig.ios_runtime("26.5")
udid = simrig.prepare_simulator(runtime, "Nine-AX", "iPhone 17 Pro", erase=False)
simrig.run(["xcrun", "simctl", "install", udid, app])
opened = 0
for i in range(tries):
    simrig.relaunch(udid, BUNDLE, ninestate.quiet_blobs(ninestate.PREFS_ERRORS_ON))
    data = simrig.wait_for(udid, "Row 1, column 1")
    empty = {"label": "Row 1, column 6"}   # the fixture's first empty cell
    simrig.tap(udid, data, empty["label"])
    seen = False
    deadline = time.time() + 15
    while time.time() < deadline:
        tree = simrig.describe(udid, tolerate=True) or {"entries": []}
        if any(e.get("label") == "Place 1" for e in tree["entries"]):
            seen = True
            break
        time.sleep(1)
    opened += seen
    print("try %d: tapped %r -> rose %s" % (i + 1, empty["label"], "OPEN" if seen else "missing"))
    if not seen:
        simrig.run(["xcrun", "simctl", "io", udid, "screenshot",
                    "/private/tmp/claude-501/-Users-aquilops-nine/39f5188e-4357-417b-a0c5-7844ac940113/scratchpad/rose-miss-%d.png" % (i + 1)])
print("opened %d/%d" % (opened, tries))
