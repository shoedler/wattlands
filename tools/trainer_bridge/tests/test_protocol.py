"""The bridge's JSON protocol helpers."""

import json
import unittest

from trainer_bridge import protocol


class ProtocolTest(unittest.TestCase):
    def test_parse_request(self) -> None:
        msg = protocol.parse_request('{"id": 3, "op": "read", "service": "1826", "char": "2acc"}')
        self.assertEqual(msg["id"], 3)
        self.assertEqual(msg["op"], "read")

    def test_rejects_bad_requests(self) -> None:
        for text in ("nope", "[1]", '{"op": "read"}', '{"id": "1", "op": "read"}', '{"id": true, "op": "read"}',
                     '{"id": 1, "op": "format_disk"}', '{"id": 1}'):
            with self.assertRaises(protocol.ProtocolError, msg=text):
                protocol.parse_request(text)

    def test_response_and_event(self) -> None:
        self.assertEqual(json.loads(protocol.response(4, True, {"char": "x"})),
                         {"id": 4, "ok": True, "result": {"char": "x"}, "error": ""})
        self.assertEqual(json.loads(protocol.response(5, False, None, "boom")),
                         {"id": 5, "ok": False, "result": {}, "error": "boom"})
        self.assertEqual(json.loads(protocol.event("notify", char="c", data="00ff")),
                         {"event": "notify", "char": "c", "data": "00ff"})
        self.assertEqual(json.loads(protocol.event("device", name="KICKR", address="AA"))["name"], "KICKR")

    def test_hex(self) -> None:
        self.assertEqual(protocol.encode_hex(b"\x05\xc8\x00"), "05c800")
        self.assertEqual(protocol.decode_hex("05C800"), b"\x05\xc8\x00")
        for bad in ("abc", "zz", 5, None):
            with self.assertRaises(protocol.ProtocolError):
                protocol.decode_hex(bad)

    def test_require_str(self) -> None:
        self.assertEqual(protocol.require_str({"address": " AA "}, "address"), "AA")
        with self.assertRaises(protocol.ProtocolError):
            protocol.require_str({"address": ""}, "address")
        with self.assertRaises(protocol.ProtocolError):
            protocol.require_str({}, "address")


if __name__ == "__main__":
    unittest.main()
