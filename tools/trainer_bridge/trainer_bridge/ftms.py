"""FTMS parsing and encoding (BRIEF 4.3), pure functions with no Bluetooth dependency.

Little-endian throughout. 16-bit UUIDs sit on the Bluetooth base UUID
0000xxxx-0000-1000-8000-00805f9b34fb. Every parser bounds-checks every field: a short
record never raises, it stops and reports ``truncated``.

The probe uses these parsers to print what the trainer reports; the bridge itself never
parses GATT payloads (it forwards bytes), so the app's GDScript FtmsCodec stays the one
codec the game relies on.
"""

from __future__ import annotations

import math
import struct

BASE_UUID_SUFFIX = "-0000-1000-8000-00805f9b34fb"

FTMS_SERVICE = "1826"
FEATURE = "2acc"
INDOOR_BIKE_DATA = "2ad2"
RESISTANCE_RANGE = "2ad6"
POWER_RANGE = "2ad8"
CONTROL_POINT = "2ad9"
MACHINE_STATUS = "2ada"
DEVICE_INFORMATION = "180a"
CYCLING_POWER = "1818"

# Device Information characteristics the probe reads (all optional, UTF-8 strings).
DEVICE_INFO_CHARS = {
    "2a29": "manufacturer",
    "2a24": "model",
    "2a25": "serial",
    "2a27": "hardware",
    "2a26": "firmware",
    "2a28": "software",
}

MACHINE_FEATURE_BITS = {
    0: "average_speed",
    1: "cadence",
    2: "total_distance",
    3: "inclination",
    4: "elevation_gain",
    5: "pace",
    6: "step_count",
    7: "resistance_level",
    8: "stride_count",
    9: "expended_energy",
    10: "heart_rate",
    11: "metabolic_equivalent",
    12: "elapsed_time",
    13: "remaining_time",
    14: "power_measurement",
    15: "force_on_belt_and_power_output",
    16: "user_data_retention",
}

TARGET_FEATURE_BITS = {
    0: "speed",
    1: "inclination",
    2: "resistance",
    3: "power",
    4: "heart_rate",
    5: "expended_energy",
    6: "step_number",
    7: "stride_number",
    8: "distance",
    9: "training_time",
    10: "time_in_two_hr_zones",
    11: "time_in_three_hr_zones",
    12: "time_in_five_hr_zones",
    13: "indoor_bike_simulation",
    14: "wheel_circumference",
    15: "spin_down",
    16: "targeted_cadence",
}

OP_REQUEST_CONTROL = 0x00
OP_RESET = 0x01
OP_SET_TARGET_RESISTANCE = 0x04
OP_SET_TARGET_POWER = 0x05
OP_START_OR_RESUME = 0x07
OP_STOP_OR_PAUSE = 0x08
OP_SET_INDOOR_BIKE_SIMULATION = 0x11
OP_RESPONSE = 0x80

RESULT_NAMES = {
    0x01: "success",
    0x02: "not_supported",
    0x03: "invalid_parameter",
    0x04: "operation_failed",
    0x05: "control_not_permitted",
}

MACHINE_STATUS_NAMES = {
    0x01: "reset",
    0x02: "stopped_or_paused_by_user",
    0x03: "stopped_by_safety_key",
    0x04: "started_or_resumed_by_user",
    0x05: "target_speed_changed",
    0x06: "target_incline_changed",
    0x07: "target_resistance_changed",
    0x08: "target_power_changed",
    0x12: "indoor_bike_simulation_changed",
    0x13: "wheel_circumference_changed",
    0x14: "spin_down_status",
    0x15: "targeted_cadence_changed",
    0xFF: "control_permission_lost",
}

# Defaults (BRIEF 4.5).
DEFAULT_CRR = 0.004
DEFAULT_CW = 0.51


def expand_uuid(uuid: str) -> str:
    """Expand a 16-bit ("2AD2", "0x2ad2") or 32-bit UUID to the lower-case 128-bit form."""
    u = uuid.strip().lower()
    if u.startswith("0x"):
        u = u[2:]
    if len(u) == 4:
        return "0000" + u + BASE_UUID_SUFFIX
    if len(u) == 8:
        return u + BASE_UUID_SUFFIX
    return u


def same_uuid(a: str, b: str) -> bool:
    return expand_uuid(a) == expand_uuid(b)


class _Reader:
    """Bounds-checked little-endian reader."""

    def __init__(self, data: bytes) -> None:
        self.data = bytes(data)
        self.pos = 0
        self.truncated = False

    def take(self, fmt: str, size: int):
        if self.truncated or self.pos + size > len(self.data):
            self.truncated = True
            return None
        value = struct.unpack_from("<" + fmt, self.data, self.pos)[0]
        self.pos += size
        return value

    def uint24(self):
        if self.truncated or self.pos + 3 > len(self.data):
            self.truncated = True
            return None
        b = self.data[self.pos : self.pos + 3]
        self.pos += 3
        return b[0] | (b[1] << 8) | (b[2] << 16)


def parse_indoor_bike_data(data: bytes) -> dict:
    """Indoor Bike Data (0x2AD2). Returns the fields present, in SI-ish units:

    speed_kmh, avg_speed_kmh, cadence_rpm, avg_cadence_rpm, distance_m, resistance_level,
    power_w, avg_power_w, energy_total_kcal, energy_per_hour_kcal, energy_per_min_kcal,
    heart_rate_bpm, met, elapsed_s, remaining_s; plus flags, more_data (bit 0 set: this
    notification carries no instantaneous speed) and truncated.
    """
    r = _Reader(data)
    flags = r.take("H", 2)
    out: dict = {"flags": 0, "more_data": False, "truncated": False}
    if flags is None:
        out["truncated"] = True
        return out
    out["flags"] = flags
    out["more_data"] = bool(flags & 0x0001)

    def put(key: str, value, scale: float | None = None) -> None:
        if value is not None:
            out[key] = value * scale if scale is not None else value

    if not flags & 0x0001:
        put("speed_kmh", r.take("H", 2), 0.01)
    if flags & 0x0002:
        put("avg_speed_kmh", r.take("H", 2), 0.01)
    if flags & 0x0004:
        put("cadence_rpm", r.take("H", 2), 0.5)
    if flags & 0x0008:
        put("avg_cadence_rpm", r.take("H", 2), 0.5)
    if flags & 0x0010:
        put("distance_m", r.uint24())
    if flags & 0x0020:
        put("resistance_level", r.take("h", 2))
    if flags & 0x0040:
        put("power_w", r.take("h", 2))
    if flags & 0x0080:
        put("avg_power_w", r.take("h", 2))
    if flags & 0x0100:
        put("energy_total_kcal", r.take("H", 2))
        put("energy_per_hour_kcal", r.take("H", 2))
        put("energy_per_min_kcal", r.take("B", 1))
    if flags & 0x0200:
        put("heart_rate_bpm", r.take("B", 1))
    if flags & 0x0400:
        put("met", r.take("B", 1), 0.1)
    if flags & 0x0800:
        put("elapsed_s", r.take("H", 2))
    if flags & 0x1000:
        put("remaining_s", r.take("H", 2))
    out["truncated"] = r.truncated
    for key in ("speed_kmh", "avg_speed_kmh", "met"):
        if key in out:
            out[key] = round(out[key], 4)
    return out


def _bit_names(value: int, names: dict) -> list[str]:
    return [names[b] for b in sorted(names) if value & (1 << b)]


def parse_feature(data: bytes) -> dict:
    """Fitness Machine Feature (0x2ACC): two uint32 bit fields, plus their names."""
    r = _Reader(data)
    machine = r.take("I", 4)
    target = r.take("I", 4)
    machine = machine or 0
    target = target or 0
    return {
        "machine": machine,
        "target": target,
        "machine_features": _bit_names(machine, MACHINE_FEATURE_BITS),
        "target_features": _bit_names(target, TARGET_FEATURE_BITS),
        "truncated": r.truncated,
    }


def parse_power_range(data: bytes) -> dict:
    """Supported Power Range (0x2AD8): sint16 min W, sint16 max W, uint16 step W."""
    r = _Reader(data)
    lo, hi, step = r.take("h", 2), r.take("h", 2), r.take("H", 2)
    if r.truncated:
        return {"truncated": True}
    return {"min_w": lo, "max_w": hi, "step_w": step, "truncated": False}


def parse_resistance_range(data: bytes) -> dict:
    """Supported Resistance Level Range (0x2AD6): sint16 min, sint16 max, uint16 step, 0.1."""
    r = _Reader(data)
    lo, hi, step = r.take("h", 2), r.take("h", 2), r.take("H", 2)
    if r.truncated:
        return {"truncated": True}
    return {
        "min": round(lo * 0.1, 4),
        "max": round(hi * 0.1, 4),
        "step": round(step * 0.1, 4),
        "truncated": False,
    }


# Machine Status parameters per op code, as the GDScript FtmsCodec decodes them:
# (key, struct format, size, divisor). W4: the shared vectors check both codecs.
_STATUS_FIELDS = {
    0x02: (("stop_pause", "B", 1, 1),),
    0x07: (("target_resistance", "B", 1, 10),),
    0x08: (("target_power_w", "h", 2, 1),),
    0x12: (("wind_mps", "h", 2, 1000), ("grade_pct", "h", 2, 100), ("crr", "B", 1, 10000),
           ("cw", "B", 1, 100)),
    0x14: (("spin_down_status", "B", 1, 1),),
    0x15: (("target_cadence_rpm", "H", 2, 2),),
}


def parse_machine_status(data: bytes) -> dict:
    """Machine Status (0x2ADA): op code, its parameter bytes and, for the codes FTMS defines
    parameters for, the decoded values (truncated when they are short)."""
    if len(data) < 1:
        return {"code": -1, "name": "empty", "params": "", "truncated": True}
    code = data[0]
    out = {
        "code": code,
        "name": MACHINE_STATUS_NAMES.get(code, "unknown"),
        "params": bytes(data[1:]).hex(),
        "truncated": False,
    }
    r = _Reader(data[1:])
    for key, fmt, size, divisor in _STATUS_FIELDS.get(code, ()):
        value = r.take(fmt, size)
        if value is None:
            out["truncated"] = True
            break
        out[key] = value if divisor == 1 else round(value / divisor, 6)
    return out


def parse_control_response(data: bytes) -> dict:
    """Control Point response indication: 0x80, request op code, result code, parameters.
    request_opcode and params (hex) match the GDScript FtmsCodec's keys (W4)."""
    if len(data) < 3 or data[0] != OP_RESPONSE:
        return {"request": -1, "request_opcode": -1, "result": -1, "result_name": "malformed",
                "params": "", "truncated": len(data) < 3}
    return {
        "request": data[1],
        "request_opcode": data[1],
        "result": data[2],
        "result_name": RESULT_NAMES.get(data[2], "unknown"),
        "params": bytes(data[3:]).hex(),
        "truncated": False,
    }


# Set Target Resistance Level encodings (the GDScript FtmsCodec's names).
RESISTANCE_UINT8 = "uint8_0.1"
RESISTANCE_SINT16 = "sint16_0.1"


def _scaled(value: float, scale: float, lo: int, hi: int) -> int:
    """value x scale, clamped to [lo, hi] and rounded half away from zero (NaN -> 0), exactly
    as the GDScript FtmsCodec._scaled does (W4: Python's round() rounds ties to even)."""
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return max(lo, min(hi, 0))
    x = max(float(lo), min(float(hi), float(value) * scale))
    n = math.floor(abs(x) + 0.5)
    return max(lo, min(hi, int(n if x >= 0 else -n)))


def encode_request_control() -> bytes:
    return bytes([OP_REQUEST_CONTROL])


def encode_reset() -> bytes:
    return bytes([OP_RESET])


def encode_target_power(watts: int) -> bytes:
    """Set Target Power: sint16 W, clamped to 0..32767 (a negative target is never sent)."""
    return struct.pack("<Bh", OP_SET_TARGET_POWER, max(0, min(32767, int(watts))))


def encode_target_resistance(level: float, encoding: str = RESISTANCE_UINT8) -> bytes:
    """Set Target Resistance Level in 0.1 steps: uint8 (default, 0..25.5) or sint16 (BRIEF 4.3;
    kept configurable in the app)."""
    if encoding == RESISTANCE_SINT16:
        return struct.pack("<Bh", OP_SET_TARGET_RESISTANCE, _scaled(level, 10.0, -32768, 32767))
    if encoding != RESISTANCE_UINT8:
        raise ValueError("unknown resistance encoding %r" % encoding)
    return struct.pack("<BB", OP_SET_TARGET_RESISTANCE, _scaled(level, 10.0, 0, 255))


def encode_start() -> bytes:
    return bytes([OP_START_OR_RESUME])


def encode_stop(pause: bool = False) -> bytes:
    return bytes([OP_STOP_OR_PAUSE, 2 if pause else 1])


def encode_simulation(wind_mps: float = 0.0, grade_pct: float = 0.0,
                      crr: float = DEFAULT_CRR, cw: float = DEFAULT_CW) -> bytes:
    """Set Indoor Bike Simulation: sint16 wind 0.001 m/s, sint16 grade 0.01 %, uint8 crr
    0.0001, uint8 cw 0.01 kg/m."""
    return struct.pack(
        "<BhhBB",
        OP_SET_INDOOR_BIKE_SIMULATION,
        _scaled(wind_mps, 1000.0, -32768, 32767),
        _scaled(grade_pct, 100.0, -32768, 32767),
        _scaled(crr, 10000.0, 0, 255),
        _scaled(cw, 100.0, 0, 255),
    )


def format_bike_data(record: dict) -> str:
    """One readable line for the probe."""
    parts = []
    for key, label, fmt in (
        ("power_w", "power", "{:d} W"),
        ("cadence_rpm", "cadence", "{:.1f} rpm"),
        ("speed_kmh", "speed", "{:.2f} km/h"),
        ("distance_m", "distance", "{:d} m"),
        ("resistance_level", "resistance", "{:d}"),
        ("heart_rate_bpm", "hr", "{:d} bpm"),
        ("elapsed_s", "elapsed", "{:d} s"),
    ):
        if key in record:
            parts.append(label + " " + fmt.format(record[key]))
    if record.get("more_data"):
        parts.append("(more data follows)")
    if record.get("truncated"):
        parts.append("(truncated)")
    return ", ".join(parts) if parts else "(no fields)"
