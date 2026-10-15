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


if __name__ == "__main__":
    unittest.main()
