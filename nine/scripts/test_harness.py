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
                mock.patch.object(simrig, "warm_up_bridge", lambda udid: None), \
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
            mock.patch.object(simrig, "warm_up_bridge", lambda udid: None),
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


if __name__ == "__main__":
    unittest.main()
