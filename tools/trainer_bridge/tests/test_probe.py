"""The probe (BRIEF 4.2) against a fake backend: read-only by default, control only with
--allow-control plus the typed confirmation and never under WATTLANDS_NO_HW_CONTROL=1."""

import asyncio
import unittest

from trainer_bridge import ftms, probe

from .fake_backend import HRM, FakeBackend


def run(coro):
    return asyncio.run(coro)


class ProbeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.backend = FakeBackend()
        self.lines: list = []

    def probe(self, **kwargs) -> int:
        kwargs.setdefault("seconds", 0)
        kwargs.setdefault("scan_seconds", 0)
        kwargs.setdefault("out", self.lines.append)
        return run(probe.run_probe(self.backend, **kwargs))

    def text(self) -> str:
        return "\n".join(self.lines)

    def test_read_only_by_default(self) -> None:
        self.assertEqual(self.probe(), 0)
        self.assertEqual(self.backend.writes, [], "nothing written")
        subscribed = [c[2] for c in self.backend.calls if c[0] == "subscribe"]
        self.assertEqual(subscribed, [ftms.INDOOR_BIKE_DATA, ftms.MACHINE_STATUS], "no control point indications")
        self.assertIn(("connect", "C4:9D:A1:00:2B:7E"), self.backend.calls, "first FTMS trainer")
        self.assertIn("found C4:9D:A1:00:2B:7E", self.text())
        self.assertNotIn("HRM-Pro", self.text(), "the scan filter drops non-trainers")
        self.assertIn("'max_w': 1800", self.text())
        self.assertIn("indoor_bike_simulation", self.text())
        self.assertIn("power 200 W, cadence 90.0 rpm, speed 25.00 km/h", self.text())
        self.assertIn("firmware", self.text())
        self.assertEqual(self.backend.ops()[-1], "disconnect")

    def test_explicit_address(self) -> None:
        self.assertEqual(self.probe(address="AA:BB:CC:DD:EE:FF"), 0)
        self.assertIn(("connect", "AA:BB:CC:DD:EE:FF"), self.backend.calls)

    def test_no_adapter(self) -> None:
        self.backend.adapter = False
        self.assertEqual(self.probe(), 2)
        self.assertIn("no Bluetooth adapter", self.text())

    def test_no_trainer(self) -> None:
        self.backend.devices = [HRM]
        self.assertEqual(self.probe(), 2)
        self.assertIn("no trainer found", self.text())

    def test_connect_failure(self) -> None:
        self.backend.connect_error = "unreachable"
        self.assertEqual(self.probe(), 4)

    def test_allow_control_refused_under_the_lock(self) -> None:
        asked = []
        code = self.probe(allow_control=True, env={"WATTLANDS_NO_HW_CONTROL": "1"},
                          ask=lambda p: asked.append(p) or probe.CONFIRM_PHRASE)
        self.assertEqual(code, 3)
        self.assertEqual(asked, [], "not even asked")
        self.assertEqual(self.backend.calls, [], "the adapter was never touched")
        self.assertIn("hardware control locked", self.text())

    def test_allow_control_needs_the_typed_phrase(self) -> None:
        for typed in ("", "yes", probe.CONFIRM_PHRASE.lower()):
            self.backend = FakeBackend()
            self.assertEqual(self.probe(allow_control=True, env={}, ask=lambda _p, t=typed: t), 3)
            self.assertEqual(self.backend.calls, [])

    def test_allow_control_eof_is_a_refusal(self) -> None:
        def eof(_p):
            raise EOFError

        self.assertEqual(self.probe(allow_control=True, env={}, ask=eof), 3)
        self.assertEqual(self.backend.writes, [])

    def test_allow_control_sends_only_request_control_and_sim_flat(self) -> None:
        # The fake backend stands in for the trainer; no adapter is involved.
        code = self.probe(allow_control=True, env={}, ask=lambda _p: probe.CONFIRM_PHRASE)
        self.assertEqual(code, 0)
        self.assertEqual([w.hex() for w in self.backend.writes], ["00", "11000000002833"])
        ops = [c[0] + ":" + (c[2] if len(c) > 2 else "") for c in self.backend.calls
               if c[0] in ("subscribe", "write")]
        self.assertEqual(ops.index("subscribe:" + ftms.CONTROL_POINT) < ops.index("write:" + ftms.CONTROL_POINT), True,
                         "indications enabled before the first write")
        self.assertIn("success", self.text())

    def test_control_not_permitted_stops(self) -> None:
        self.backend.cp_result = 0x05
        self.assertEqual(self.probe(allow_control=True, env={}, ask=lambda _p: probe.CONFIRM_PHRASE), 0)
        self.assertEqual([w.hex() for w in self.backend.writes], ["00"])
        self.assertIn("another app may hold control", self.text())

    def test_is_trainer(self) -> None:
        self.assertTrue(probe.is_trainer({"name": "", "services": ["00001826-0000-1000-8000-00805F9B34FB"]}))
        self.assertTrue(probe.is_trainer({"name": "Kickr Core", "services": []}))
        self.assertFalse(probe.is_trainer({"name": None, "services": ["180d"]}))


if __name__ == "__main__":
    unittest.main()
