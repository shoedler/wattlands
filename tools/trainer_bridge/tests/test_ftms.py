"""FTMS parsers and encoders against golden vectors (BRIEF 4.3)."""

import math
import unittest

from trainer_bridge import ftms

from .vectors import load_local, load_shared, shared_bike_cases

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


# BRIEF 4.3: "Keep byte-exact golden vectors in tests/vectors/ftms.json and reuse them in the
# Python tests." W4 (ftms-ble-5): every shared encode case and every parse case of a kind this
# codec implements runs here, not only the Indoor Bike Data parse cases, so the two codecs can't
# drift apart (W3 found 7 mismatches: unclamped target power, ties rounded to even, raising on
# out-of-range SIM fields).
SHARED_ENCODERS = {
    "request_control": lambda a: ftms.encode_request_control(),
    "reset": lambda a: ftms.encode_reset(),
    "start_resume": lambda a: ftms.encode_start(),
    "stop_pause": lambda a: ftms.encode_stop(a["param"] == 2),
    "target_power": lambda a: ftms.encode_target_power(a["watts"]),
    "target_resistance": lambda a: ftms.encode_target_resistance(a["level"], a["encoding"]),
    "indoor_bike_simulation": lambda a: ftms.encode_simulation(a["wind_mps"], a["grade_pct"], a["crr"], a["cw"]),
}

SHARED_PARSERS = {
    "feature": ftms.parse_feature,
    "power_range": ftms.parse_power_range,
    "resistance_range": ftms.parse_resistance_range,
    "control_response": ftms.parse_control_response,
    "machine_status": ftms.parse_machine_status,
    "indoor_bike_data": ftms.parse_indoor_bike_data,
}


# Indoor Bike Data keys the GDScript codec names differently (the bridge's own names stay).
BIKE_KEYS = {"total_energy_kcal": "energy_total_kcal", "energy_per_minute_kcal": "energy_per_min_kcal"}


def _invalid(kind: str, got: dict) -> bool:
    if got.get("truncated"):
        return True
    return kind == "control_response" and got.get("result_name") == "malformed"


class SharedVectorTest(unittest.TestCase):
    def setUp(self) -> None:
        doc, why = load_shared()
        if doc is None:
            self.skipTest(why)
        self.doc = doc

    def test_every_shared_encode_case(self) -> None:
        seen = set()
        for case in self.doc["encode"]:
            encode = SHARED_ENCODERS.get(case["op"])
            if encode is None:
                continue
            seen.add(case["op"])
            with self.subTest(case=case["name"]):
                self.assertEqual(encode(case["args"]).hex(), case["hex"], case["name"])
        self.assertEqual(seen, set(SHARED_ENCODERS), "every encoder this codec has is covered")

    def test_every_shared_parse_case(self) -> None:
        seen = set()
        for case in self.doc["parse"]:
            parse = SHARED_PARSERS.get(case["kind"])
            if parse is None:
                continue
            seen.add(case["kind"])
            with self.subTest(case=case["name"]):
                got = parse(bytes.fromhex(case["hex"]))
                if not case["valid"]:
                    self.assertTrue(_invalid(case["kind"], got), "%s: accepted %s" % (case["name"], got))
                    continue
                self.assertFalse(_invalid(case["kind"], got), "%s: rejected %s" % (case["name"], got))
                for shared_key, value in case["expect"].items():
                    key = BIKE_KEYS.get(shared_key, shared_key) if case["kind"] == "indoor_bike_data" else shared_key
                    self.assertIn(key, got, "%s: missing %s in %s" % (case["name"], key, got))
                    if isinstance(value, bool) or isinstance(value, str):
                        self.assertEqual(got[key], value, "%s: %s" % (case["name"], key))
                    else:
                        self.assertTrue(math.isclose(float(got[key]), float(value), abs_tol=1e-6),
                                        "%s: %s %r != %r" % (case["name"], key, got[key], value))
        self.assertEqual(seen, set(SHARED_PARSERS), "every parser this codec has is covered")

    def test_rounding_and_clamping_match_the_gdscript_codec(self) -> None:
        self.assertEqual(ftms.encode_target_power(-5).hex(), "050000")
        self.assertEqual(ftms.encode_target_power(40000).hex(), "05ff7f")
        self.assertEqual(ftms.encode_target_resistance(1.25).hex(), "040d", "a tie rounds away from zero")
        self.assertEqual(ftms.encode_simulation(0.0, -0.125).hex(), "110000f3ff2833")
        self.assertEqual(ftms.encode_simulation(40.0, 400.0, 0.03, 3.0).hex(), "11ff7fff7fffff")
        self.assertEqual(ftms.encode_simulation(float("nan"), 0.0).hex(), "11000000002833")
        with self.assertRaises(ValueError):
            ftms.encode_target_resistance(1.0, "uint4")


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
