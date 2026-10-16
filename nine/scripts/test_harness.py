"""Unit tests for the harness plumbing that runs no simulator.

    python3 -m unittest discover -s nine/scripts -p 'test_*.py'

Everything here stubs `simrig.run` and friends, so it answers in a second on
any Mac or Linux box: which simulators get slimmed, what `simslim` is asked,
what `shotlist.py` writes to its index. The harnesses themselves still need a
simulator; these pin the decisions they make before one is touched.
"""

import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import simrig  # noqa: E402

RUNTIME = {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5", "version": "26.5"}


class FakeSimctl:
    """Records every command; answers `simctl list` and `create`."""

    def __init__(self, devices=()):
        self.calls = []
        self.devices = list(devices)

    def __call__(self, args, check=True, capture=True):
        self.calls.append(list(args))
        if args[:4] == ["xcrun", "simctl", "list", "devices"]:
            return json.dumps({"devices": {RUNTIME["identifier"]: self.devices}})
        if args[:4] == ["xcrun", "simctl", "list", "devicetypes"]:
            return json.dumps({"devicetypes": [
                {"name": "iPhone 17 Pro", "identifier": "dt.iphone"},
                {"name": simrig.DUO, "identifier": "dt.duo"},
            ]})
        if args[:3] == ["xcrun", "simctl", "create"]:
            return "NEW-UDID\n"
        if args[:3] == ["xcrun", "simctl", "ui"] and len(args) == 5:
            return getattr(self, "answers", {}).get(("ui", "appearance"), "light\n")
        return ""

    def simslim_calls(self):
        return [c for c in self.calls if c and c[0] == "simslim"]


class PrepareSimulatorSlimming(unittest.TestCase):

    def prepare(self, device_type, devices=(), **kwargs):
        fake = FakeSimctl(devices)
        with mock.patch.object(simrig, "run", fake), \
                mock.patch.object(simrig, "warm_up_bridge", lambda udid, launch=None: None), \
                mock.patch.object(simrig.shutil, "which", lambda name: "/bin/" + name), \
                mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("NINE_SIMSLIM", None)
            simrig.prepare_simulator(RUNTIME, "Nine-Test", device_type, **kwargs)
        return fake

    def test_a_fresh_iphone_baseline_simulator_stays_stock(self):
        # Baselines were recorded stock and CI has no simslim.
        self.assertEqual(self.prepare("iPhone 17 Pro").simslim_calls(), [])

    def test_an_erased_iphone_baseline_simulator_stays_stock(self):
        fake = self.prepare("iPhone 17 Pro", devices=[{"name": "Nine-Test", "udid": "U"}])
        self.assertEqual(fake.simslim_calls(), [])

    def test_a_fresh_duo_is_slimmed_keeping_game_center(self):
        calls = self.prepare(simrig.DUO).simslim_calls()
        self.assertEqual(len(calls), 1)
        self.assertIn("--keep", calls[0])
        self.assertEqual(calls[0][calls[0].index("--keep") + 1], "com.apple.gamed")

    def test_an_explicit_slim_flag_wins(self):
        self.assertEqual(len(self.prepare("iPhone 17 Pro", slim=True).simslim_calls()), 1)
        self.assertEqual(self.prepare(simrig.DUO, slim=False).simslim_calls(), [])

    def test_a_reused_simulator_is_never_reslimmed(self):
        fake = self.prepare(simrig.DUO, devices=[{"name": "Nine-Test", "udid": "U"}],
                            erase=False)
        self.assertEqual(fake.simslim_calls(), [])


class Reslim(unittest.TestCase):

    def test_reslim_preserves_the_boot_state(self):
        fake = FakeSimctl()
        with mock.patch.object(simrig, "run", fake), \
                mock.patch.object(simrig.shutil, "which", lambda name: "/bin/" + name):
            os.environ.pop("NINE_SIMSLIM", None)
            simrig.reslim("U")
        call = fake.simslim_calls()[0]
        self.assertEqual(call[:3], ["simslim", "on", "U"])
        self.assertIn("--preserve-boot-state", call)


class ShotlistIndex(unittest.TestCase):

    def test_the_index_records_each_devices_runtime(self):
        import shotlist
        record = shotlist.index_record(
            {"iphone": "26.5", "duo-open": "27.1"},
            ["iphone-dark-game.png", "duo-open-dark-game.png"],
            [shotlist.SCENES_BY_NAME["game"]])
        self.assertEqual(record["runtimes"], {"iphone": "26.5", "duo-open": "27.1"})
        self.assertNotIn("runtime", record)
        self.assertEqual(record["shots"], ["iphone-dark-game.png", "duo-open-dark-game.png"])
        self.assertEqual(set(record["scenes"]), {"game"})
        self.assertIn("sim_use", record)


class StaleTouchRecovery(unittest.TestCase):
    """Over a long run the simulator's touch input goes stale: `sim-use tap`
    reports success and nothing happens, on `main` as on the branch, until a
    reboot (DEVIATIONS, PRD-37). A wait that times out *after a tap* is that
    signature; one before any tap is not, and must still fail at once."""

    def setUp(self):
        self.fake = FakeSimctl()
        patches = [
            mock.patch.object(simrig, "run", self.fake),
            mock.patch.object(simrig, "describe",
                              lambda udid, point=None, tolerate=False: {"entries": [{"label": "Home"}]}),
            mock.patch.object(simrig, "wait_until_dead", lambda udid, bundle: None),
            mock.patch.object(simrig, "seed", lambda udid, bundle, blobs: None),
            mock.patch.object(simrig, "warm_up_bridge", lambda udid, launch=None: None),
            mock.patch.object(simrig.time, "sleep", lambda s: None),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def test_a_timeout_after_a_tap_is_marked_as_one(self):
        simrig.relaunch("U", "b", {})
        simrig.tap("U", {"entries": [{"label": "Home", "frame": {"x": 0, "y": 0, "width": 10, "height": 10}}]}, "Home")
        with self.assertRaises(simrig.WaitTimeout) as caught:
            simrig.wait_for("U", "Place 1", timeout=0)
        self.assertTrue(caught.exception.after_tap)
        # Still a SystemExit: uncaught, it ends the run exactly as before.
        self.assertIsInstance(caught.exception, SystemExit)
        self.assertIn("timed out waiting for 'Place 1'", str(caught.exception.code))

    def test_a_relaunch_clears_the_mark(self):
        simrig.note_tap("U")
        simrig.relaunch("U", "b", {})
        with self.assertRaises(simrig.WaitTimeout) as caught:
            simrig.wait_for("U", "Row 1, column 1", timeout=0)
        self.assertFalse(caught.exception.after_tap)

    def scene_failing(self, times, after_tap=True):
        attempts = []

        def scene():
            attempts.append(1)
            if len(attempts) <= times:
                raise simrig.WaitTimeout("timed out", after_tap)
            return "captured"
        return scene, attempts

    def reboots(self):
        return [c for c in self.fake.calls if c[:3] == ["xcrun", "simctl", "shutdown"]]

    def test_one_stale_timeout_reboots_once_and_retries(self):
        scene, attempts = self.scene_failing(1)
        self.assertEqual(simrig.retrying_stale_touch("U", scene, "game-rose"), "captured")
        self.assertEqual(len(attempts), 2)
        self.assertEqual(len(self.reboots()), 1)

    def test_a_second_timeout_is_a_real_failure(self):
        scene, attempts = self.scene_failing(2)
        with self.assertRaises(simrig.WaitTimeout):
            simrig.retrying_stale_touch("U", scene, "game-rose")
        self.assertEqual(len(attempts), 2)
        self.assertEqual(len(self.reboots()), 1)

    def test_a_timeout_before_any_tap_is_not_retried(self):
        scene, attempts = self.scene_failing(1, after_tap=False)
        with self.assertRaises(simrig.WaitTimeout):
            simrig.retrying_stale_touch("U", scene, "game")
        self.assertEqual(len(attempts), 1)
        self.assertEqual(self.reboots(), [])

    def test_a_reboot_restores_what_the_run_pinned(self):
        self.fake.answers = {("ui", "appearance"): "dark\n"}
        simrig.reboot("U")
        verbs = [c[2] for c in self.fake.calls if c[:2] == ["xcrun", "simctl"]]
        self.assertEqual(verbs[:3], ["ui", "shutdown", "boot"])
        self.assertIn(["xcrun", "simctl", "ui", "U", "appearance", "dark"], self.fake.calls)
        self.assertTrue(any(c[2:4] == ["status_bar", "U"] for c in self.fake.calls))


class DuoScenes(unittest.TestCase):

    def test_launch_only_scenes_pass_no_argument(self):
        import shotlist
        self.assertEqual(shotlist.duo_launch("game"), (True, []))
        self.assertEqual(shotlist.duo_launch("home"), (False, []))

    def test_every_other_duo_scene_names_its_surface(self):
        import shotlist
        self.assertEqual(shotlist.duo_launch("prefs"), (True, ["-NineDebugSurface", "prefs"]))
        self.assertEqual(shotlist.duo_launch("coach"), (True, ["-NineDebugSurface", "coach"]))
        self.assertEqual(shotlist.duo_launch("history"), (False, ["-NineDebugSurface", "history"]))
        # The app's vocabulary (DebugSurface.swift) and the harness's agree.
        src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                                "Sources", "Shared", "DebugSurface.swift")).read()
        for surface, _ in shotlist.DUO_SCENES.values():
            if surface:
                self.assertRegex(src, r"case[^\n]*\b%s\b" % surface)


class DuoSettle(unittest.TestCase):

    def test_a_blank_panel_with_only_the_status_bar_is_not_drawn(self):
        # Measured: light-drawer was a white panel and the 9:41 pill alone
        # passed the old whole-frame contrast test.
        from PIL import Image, ImageDraw
        import shotlist
        blank = Image.new("L", (951, 669), 255)
        ImageDraw.Draw(blank).rectangle((880, 10, 940, 110), fill=0)   # the pill
        self.assertFalse(shotlist.panel_drawn(blank))
        drawn = blank.copy()
        ImageDraw.Draw(drawn).rectangle((100, 40, 650, 590), fill=40)  # a board
        self.assertTrue(shotlist.panel_drawn(drawn))


class DuoBridgeWarmUp(unittest.TestCase):
    """Measured: on the iOS 27.1 Duo, `describe-ui` answers "No translation
    object" for SpringBoard indefinitely (300 s on a fresh, folded
    Nine-AX-Duo) but reads an app. So the Duo warms up inside Settings."""

    def run_prepare(self, device_type):
        fake = FakeSimctl()
        warmed = []
        with mock.patch.object(simrig, "run", fake), \
                mock.patch.object(simrig, "warm_up_bridge",
                                  lambda udid, launch=None: warmed.append(launch)), \
                mock.patch.object(simrig.shutil, "which", lambda name: None):
            simrig.prepare_simulator(RUNTIME, "Nine-Test", device_type)
        return warmed

    def test_the_duo_warms_up_inside_an_app(self):
        self.assertEqual(self.run_prepare(simrig.DUO), [simrig.DUO_WARM_UP_APP])

    def test_the_iphone_warms_up_as_before(self):
        self.assertEqual(self.run_prepare("iPhone 17 Pro"), [None])

    def test_a_warm_up_in_an_app_launches_it_and_puts_it_away(self):
        fake = FakeSimctl()
        with mock.patch.object(simrig, "run", fake), \
                mock.patch.object(simrig, "describe", lambda udid, point=None, tolerate=False: {"entries": []}):
            simrig.warm_up_bridge("U", launch="com.apple.Preferences")
        verbs = [c[2:5] for c in fake.calls if c[:2] == ["xcrun", "simctl"]]
        self.assertEqual(verbs, [["launch", "U", "com.apple.Preferences"],
                                 ["terminate", "U", "com.apple.Preferences"]])


class DuoDisplays(unittest.TestCase):
    """Measured: `simctl io screenshot` with no `--display` returned the
    outer panel on Nine-AX-Duo and the dark inner one (2007 px) on a folded
    Nine-Contrast-Duo, so every Duo capture names its panel."""

    def test_each_posture_names_its_panel(self):
        self.assertEqual(simrig.screenshot_display("open"), "primary-1")
        self.assertEqual(simrig.screenshot_display("closed"), "primary")
        self.assertIsNone(simrig.screenshot_display(None))

    def test_screenshot_args_carry_the_panel(self):
        self.assertEqual(simrig.screenshot_args("U", "/p.bmp", "bmp", "closed"),
                         ["xcrun", "simctl", "io", "U", "screenshot", "--type=bmp",
                          "--display=primary", "/p.bmp"])
        self.assertEqual(simrig.screenshot_args("U", "/p.bmp", "bmp", None),
                         ["xcrun", "simctl", "io", "U", "screenshot", "--type=bmp", "/p.bmp"])


if __name__ == "__main__":
    unittest.main()
