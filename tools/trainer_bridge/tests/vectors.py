"""Golden vectors: tests/vectors_local.json (transcribed from BRIEF 4.3) and, when present,
the shared tests/vectors/ftms.json that trainer-core writes for the GDScript codec."""

from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
LOCAL = HERE / "vectors_local.json"
SHARED = HERE.parent.parent.parent / "tests" / "vectors" / "ftms.json"

# Field names other codecs may use for the same Indoor Bike Data values.
ALIASES = {
    "power_w": ("power_w", "power", "instantaneous_power", "inst_power_w"),
    "cadence_rpm": ("cadence_rpm", "cadence", "instantaneous_cadence", "inst_cadence_rpm"),
    "speed_kmh": ("speed_kmh", "speed", "instantaneous_speed", "inst_speed_kmh"),
    "distance_m": ("distance_m", "total_distance_m", "distance"),
    "heart_rate_bpm": ("heart_rate_bpm", "heart_rate", "hr_bpm"),
    "resistance_level": ("resistance_level", "resistance"),
    "elapsed_s": ("elapsed_s", "elapsed_time_s", "elapsed_time"),
}


def load_local() -> dict:
    with open(LOCAL, encoding="utf-8") as f:
        return json.load(f)


def _hex(text: str):
    try:
        return bytes.fromhex(text.replace(" ", ""))
    except ValueError:
        return None


def _payload(entry: dict):
    for key in ("hex", "bytes_hex", "data_hex"):
        if isinstance(entry.get(key), str):
            return _hex(entry[key])
    for key in ("bytes", "data"):
        value = entry.get(key)
        if isinstance(value, list) and all(isinstance(b, int) and 0 <= b < 256 for b in value):
            return bytes(value)
        if isinstance(value, str):
            return _hex(value)
    return None


def _expected(entry: dict):
    for key in ("expect", "expected", "parsed", "record", "fields"):
        if isinstance(entry.get(key), dict):
            return entry[key]
    return None


def _is_bike(path: str, entry: dict) -> bool:
    tags = " ".join(str(entry.get(k, "")) for k in ("kind", "type", "characteristic", "uuid", "char"))
    text = (path + " " + tags).lower()
    return "bike" in text or "2ad2" in text


def load_shared():
    """The shared tests/vectors/ftms.json as a dict, or (None, reason) when it is missing."""
    if not SHARED.exists():
        return None, "tests/vectors/ftms.json is not in this checkout yet (trainer-core writes it)"
    try:
        return json.loads(SHARED.read_text(encoding="utf-8")), ""
    except ValueError as exc:
        return None, "tests/vectors/ftms.json is not JSON: %s" % exc


def shared_bike_cases():
    """([(name, payload, {our_key: expected_value})], "") for every comparable Indoor Bike Data
    case in the shared file, or (None, reason) when it is missing or has none."""
    if not SHARED.exists():
        return None, "tests/vectors/ftms.json is not in this checkout yet (trainer-core writes it)"
    try:
        data = json.loads(SHARED.read_text(encoding="utf-8"))
    except ValueError as exc:
        return None, "tests/vectors/ftms.json is not JSON: %s" % exc
    cases = []

    def walk(node, path: str) -> None:
        if isinstance(node, dict):
            payload, expected = _payload(node), _expected(node)
            if payload is not None and expected is not None and _is_bike(path, node):
                mapped = {}
                for ours, names in ALIASES.items():
                    for n in names:
                        value = expected.get(n)
                        if isinstance(value, (int, float)) and not isinstance(value, bool):
                            mapped[ours] = value
                            break
                if mapped:
                    cases.append((str(node.get("name", path)), payload, mapped))
                return
            for k, v in node.items():
                walk(v, path + "/" + str(k))
        elif isinstance(node, list):
            for i, v in enumerate(node):
                walk(v, "%s[%d]" % (path, i))

    walk(data, "")
    if not cases:
        return None, "tests/vectors/ftms.json has no Indoor Bike Data case in a shape these tests understand"
    return cases, ""
