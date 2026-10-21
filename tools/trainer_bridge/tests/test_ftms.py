"""FTMS parsers and encoders against golden vectors (BRIEF 4.3)."""

import math
import unittest

from trainer_bridge import ftms

from .vectors import load_local, shared_bike_cases

STATE_KEYS = {"flags", "more_data", "truncated"}
EVERY_FIELD = "fe1fc4096009b400aa00393000fbfffa00f000640058020a8c375802b004"


class VectorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.v = load_local()

    def assertRecord(self, got: dict, expect: dict, name: str) -> None:
        for key, value in expect.items():
            self.assertIn(key, got, "%s: missing %s in %s" % (name, key, got))
            if isinstance(value, float):
                self.assertTrue(math.isclose(got[key], value, abs_tol=1e-6),
                                "%s: %s %r != %r" % (name, key, got[key], value))
            else:
                self.assertEqual(got[key], value, "%s: %s" % (name, key))

    def test_indoor_bike_data(self) -> None:
        for case in self.v["indoor_bike_data"]:
            got = ftms.parse_indoor_bike_data(bytes.fromhex(case["hex"]))
            self.assertRecord(got, case["expect"], case["name"])
            self.assertEqual(set(got) - STATE_KEYS, set(case["expect"]) - STATE_KEYS,
                             case["name"] + ": exact field set")

    def test_feature(self) -> None:
        for case in self.v["feature"]:
            self.assertRecord(ftms.parse_feature(bytes.fromhex(case["hex"])), case["expect"], case["name"])

    def test_ranges(self) -> None:
        for case in self.v["power_range"]:
            self.assertRecord(ftms.parse_power_range(bytes.fromhex(case["hex"])), case["expect"], case["name"])
        for case in self.v["resistance_range"]:
            self.assertRecord(ftms.parse_resistance_range(bytes.fromhex(case["hex"])), case["expect"], case["name"])

    def test_control_point_encoding(self) -> None:
        for case in self.v["control_point"]:
            encode = getattr(ftms, "encode_" + case["encode"])
            self.assertEqual(encode(*case["args"]).hex(), case["hex"], case["name"])

    def test_control_responses_and_status(self) -> None:
        for case in self.v["control_response"]:
            self.assertRecord(ftms.parse_control_response(bytes.fromhex(case["hex"])), case["expect"], case["name"])
        for case in self.v["machine_status"]:
            self.assertRecord(ftms.parse_machine_status(bytes.fromhex(case["hex"])), case["expect"], case["name"])

    def test_shared_vectors(self) -> None:
        cases, why = shared_bike_cases()
        if cases is None:
            self.skipTest(why)
        for name, payload, expected in cases:
            got = ftms.parse_indoor_bike_data(payload)
            for key, value in expected.items():
                self.assertIn(key, got, name)
                self.assertTrue(math.isclose(float(got[key]), float(value), abs_tol=0.01), "%s: %s" % (name, key))


class ParserEdgeTest(unittest.TestCase):
    def test_never_raises_on_short_or_odd_input(self) -> None:
        for n in range(0, 40):
            data = bytes([0xFF] * n)
            ftms.parse_indoor_bike_data(data)
            ftms.parse_feature(data)
            ftms.parse_power_range(data)
            ftms.parse_resistance_range(data)
            ftms.parse_machine_status(data)
            ftms.parse_control_response(data)

    def test_every_flag_truncated_at_every_length(self) -> None:
        full = bytes.fromhex(EVERY_FIELD)
        for n in range(2, len(full)):
            self.assertTrue(ftms.parse_indoor_bike_data(full[:n])["truncated"], n)
        self.assertFalse(ftms.parse_indoor_bike_data(full)["truncated"])

    def test_uuids(self) -> None:
        full = "00002ad2-0000-1000-8000-00805f9b34fb"
        self.assertEqual(ftms.expand_uuid("2AD2"), full)
        self.assertEqual(ftms.expand_uuid("0x2ad2"), full)
        self.assertEqual(ftms.expand_uuid(full.upper()), full)
        self.assertEqual(ftms.expand_uuid("00001826"), "00001826-0000-1000-8000-00805f9b34fb")
        self.assertTrue(ftms.same_uuid("1826", "00001826-0000-1000-8000-00805F9B34FB"))
        self.assertFalse(ftms.same_uuid("1826", "1818"))

    def test_simulation_clamps_bytes(self) -> None:
        self.assertEqual(ftms.encode_simulation(0, 0, crr=1.0, cw=5.0)[-2:], bytes([255, 255]))
        self.assertEqual(ftms.encode_simulation(0, 0, crr=-1.0, cw=-1.0)[-2:], bytes([0, 0]))

    def test_format_bike_data(self) -> None:
        line = ftms.format_bike_data(ftms.parse_indoor_bike_data(bytes.fromhex("4400c409b400c800")))
        self.assertEqual(line, "power 200 W, cadence 90.0 rpm, speed 25.00 km/h")
        self.assertIn("truncated", ftms.format_bike_data({"truncated": True}))


if __name__ == "__main__":
    unittest.main()
