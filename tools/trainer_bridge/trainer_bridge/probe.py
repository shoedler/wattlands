"""``probe``: a read-only look at a real trainer (BRIEF 4.2, docs/HARDWARE_TEST_PLAN.md step 1).

It scans for FTMS devices (advertised 0x1826 or a name containing KICKR), connects to the
one given with --address (or the first found), reads Device Information, the Fitness
Machine Feature, the Supported Power Range and the Supported Resistance Level Range, then
prints parsed Indoor Bike Data (and Machine Status) for --seconds (default 30).

Read-only unless --allow-control is given AND the person at the trainer types the
confirmation phrase. Even then it only sends Request Control and SIM flat (grade 0), the
gentlest state the trainer has. --allow-control is refused outright while
WATTLANDS_NO_HW_CONTROL=1 is set (every automated run in this repo sets it).
"""

from __future__ import annotations

import asyncio
from typing import Callable, Optional

from . import ftms
from .backend import BackendError, GattBackend
from .server import HW_ENV, HW_MESSAGE, hw_locked

CONFIRM_PHRASE = "I AM ON THE TRAINER"
SCAN_SECONDS = 10.0
RESPONSE_TIMEOUT_S = 2.0


def is_trainer(info: dict) -> bool:
    for u in info.get("services") or []:
        if ftms.same_uuid(str(u), ftms.FTMS_SERVICE):
            return True
    return "kickr" in str(info.get("name") or "").lower()


async def run_probe(
    backend: GattBackend,
    seconds: float = 30.0,
    address: Optional[str] = None,
    allow_control: bool = False,
    ask: Callable[[str], str] = input,
    out: Callable[[str], None] = print,
    env: Optional[dict] = None,
    scan_seconds: float = SCAN_SECONDS,
) -> int:
    """Returns a process exit code: 0 ok, 2 no adapter or no trainer, 3 refused, 4 failed."""
    control = False
    if allow_control:
        if hw_locked(env):
            out("refused: %s (%s=1 is set); the probe stays read-only" % (HW_MESSAGE, HW_ENV))
            return 3
        out("--allow-control sends Request Control and SIM flat (grade 0) to the trainer.")
        out("Only do this sitting on the bike with the trainer clear. Type %r to continue:" % CONFIRM_PHRASE)
        try:
            typed = ask("> ")
        except EOFError:
            typed = ""
        if typed.strip() != CONFIRM_PHRASE:
            out("refused: confirmation not typed; nothing was sent")
            return 3
        control = True

    ok, error = await backend.init()
    if not ok:
        out("no Bluetooth adapter: %s" % error)
        return 2

    found: dict = {}

    def seen(info: dict) -> None:
        if is_trainer(info):
            key = str(info.get("address", "")).lower()
            if key and key not in found:
                found[key] = info
                out("found %s  %s  rssi %s" % (info.get("address"), info.get("name") or "?", info.get("rssi")))

    out("scanning %d s for FTMS trainers (service 0x1826 or a KICKR name)..." % int(scan_seconds))
    await backend.scan(scan_seconds, seen)
    target = address
    if target is None:
        if not found:
            out("no trainer found")
            return 2
        target = str(next(iter(found.values()))["address"])

    out("connecting to %s ..." % target)
    try:
        info = await backend.connect(target)
    except BackendError as exc:
        out("connect failed: %s" % exc)
        return 4
    out("connected: %s" % (info.get("name") or target))
    try:
        await _read_static(backend, out)
        records = await _stream(backend, seconds, control, out)
    finally:
        await backend.disconnect()
    out("done: %d bike data records" % records)
    return 0


async def _read_static(backend: GattBackend, out: Callable[[str], None]) -> None:
    for uuid, label in ftms.DEVICE_INFO_CHARS.items():
        try:
            raw = await backend.read(ftms.DEVICE_INFORMATION, uuid)
            out("%-12s %s" % (label, raw.decode("utf-8", "replace").strip("\x00 ")))
        except BackendError:
            pass
    for uuid, label, parse in (
        (ftms.FEATURE, "features", ftms.parse_feature),
        (ftms.POWER_RANGE, "power range", ftms.parse_power_range),
        (ftms.RESISTANCE_RANGE, "resistance", ftms.parse_resistance_range),
    ):
        try:
            raw = await backend.read(ftms.FTMS_SERVICE, uuid)
            out("%-12s %s  (%s)" % (label, parse(raw), raw.hex()))
        except BackendError as exc:
            out("%-12s unavailable (%s)" % (label, exc))


async def _stream(backend: GattBackend, seconds: float, control: bool, out: Callable[[str], None]) -> int:
    count = 0
    responses: asyncio.Queue = asyncio.Queue()

    def notified(uuid: str, data: bytes) -> None:
        nonlocal count
        if ftms.same_uuid(uuid, ftms.INDOOR_BIKE_DATA):
            count += 1
            out("bike data   %s  (%s)" % (ftms.format_bike_data(ftms.parse_indoor_bike_data(data)), data.hex()))
        elif ftms.same_uuid(uuid, ftms.MACHINE_STATUS):
            out("status      %s" % ftms.parse_machine_status(data))
        elif ftms.same_uuid(uuid, ftms.CONTROL_POINT):
            responses.put_nowait(ftms.parse_control_response(data))

    await backend.subscribe(ftms.FTMS_SERVICE, ftms.INDOOR_BIKE_DATA, notified)
    try:
        await backend.subscribe(ftms.FTMS_SERVICE, ftms.MACHINE_STATUS, notified)
    except BackendError as exc:
        out("machine status unavailable (%s)" % exc)
    if control:
        # Indications first (BRIEF 4.4), then Request Control, then SIM flat.
        await backend.subscribe(ftms.FTMS_SERVICE, ftms.CONTROL_POINT, notified)
        for label, payload in (("request control", ftms.encode_request_control()),
                               ("SIM flat", ftms.encode_simulation(0.0, 0.0))):
            await backend.write(ftms.FTMS_SERVICE, ftms.CONTROL_POINT, payload, True)
            try:
                res = await asyncio.wait_for(responses.get(), timeout=RESPONSE_TIMEOUT_S)
                out("%-15s %s" % (label, res))
                if res.get("result") == 0x05:
                    out("another app may hold control (Zwift, the Wahoo app); stopping here")
                    break
            except asyncio.TimeoutError:
                out("%-15s no response within %d s" % (label, int(RESPONSE_TIMEOUT_S)))
                break
    out("printing Indoor Bike Data for %d s ..." % int(seconds))
    await asyncio.sleep(seconds)
    return count
