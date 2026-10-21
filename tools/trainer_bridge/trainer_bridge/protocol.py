"""The bridge's JSON protocol (one JSON object per WebSocket text frame).

    request   {"id": int, "op": str, ...fields}
    response  {"id": int, "ok": bool, "result": any, "error": str}
    event     {"event": str, ...fields}

Byte payloads are lower-case hex strings. UUIDs in requests may be 16-bit or full; the
bridge expands them (case-insensitive) before talking to the adapter and always answers
with lower-case 128-bit UUIDs. BridgeTransport (addons/wattlands/trainer/ble/
bridge_transport.gd) is the client; tools/trainer_bridge/README.md has the full table.
"""

from __future__ import annotations

import json

PROTO = 1
NAME = "wattlands-trainer-bridge"

OPS = (
    "hello",
    "init",
    "scan",
    "stop_scan",
    "connect",
    "disconnect",
    "discover",
    "read",
    "write",
    "subscribe",
)
EVENTS = ("device", "scan_stopped", "notify", "disconnected", "adapter")


class ProtocolError(ValueError):
    """A request that can't be answered (bad JSON, missing id or op, bad field)."""


def parse_request(text: str) -> dict:
    try:
        msg = json.loads(text)
    except (TypeError, ValueError) as exc:
        raise ProtocolError("not JSON: %s" % exc) from None
    if not isinstance(msg, dict):
        raise ProtocolError("not a JSON object")
    if not isinstance(msg.get("id"), int) or isinstance(msg.get("id"), bool):
        raise ProtocolError("missing integer id")
    if msg.get("op") not in OPS:
        raise ProtocolError("unknown op %r" % (msg.get("op"),))
    return msg


def response(req_id: int, ok: bool, result=None, error: str = "") -> str:
    return json.dumps({"id": req_id, "ok": ok, "result": result if result is not None else {}, "error": error})


def event(kind: str, /, **fields) -> str:
    """An event message; ``kind`` is positional-only so a ``name`` field stays a field."""
    msg = {"event": kind}
    msg.update(fields)
    return json.dumps(msg)


def encode_hex(data: bytes) -> str:
    return bytes(data).hex()


def decode_hex(text) -> bytes:
    if not isinstance(text, str):
        raise ProtocolError("data must be a hex string")
    try:
        return bytes.fromhex(text)
    except ValueError:
        raise ProtocolError("data is not hex") from None


def require_str(msg: dict, key: str) -> str:
    value = msg.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ProtocolError("missing %s" % key)
    return value.strip()
