"""A GattBackend double: records every call, never touches Bluetooth."""

from __future__ import annotations

import asyncio
from typing import Optional

from trainer_bridge import ftms
from trainer_bridge.backend import BackendError

KICKR = {"address": "C4:9D:A1:00:2B:7E", "name": "KICKR CORE 2B7E", "rssi": -58, "services": ["1826", "180A"]}
HRM = {"address": "11:22:33:44:55:66", "name": "HRM-Pro", "rssi": -70, "services": ["180D"]}

FTMS_SERVICES = [{
    "uuid": "1826",
    "characteristics": [
        {"uuid": "2ACC", "properties": ["read"]},
        {"uuid": "2AD2", "properties": ["notify"]},
        {"uuid": "2AD6", "properties": ["read"]},
        {"uuid": "2AD8", "properties": ["read"]},
        {"uuid": "2AD9", "properties": ["write", "indicate"]},
        {"uuid": "2ADA", "properties": ["notify"]},
    ],
}]

READS = {
    ftms.expand_uuid("2acc"): bytes.fromhex("824000000ce00000"),
    ftms.expand_uuid("2ad8"): bytes.fromhex("000008070100"),
    ftms.expand_uuid("2ad6"): bytes.fromhex("0000e8030100"),
    ftms.expand_uuid("2a29"): b"Wahoo Fitness",
    ftms.expand_uuid("2a26"): b"4.2.1",
}

BIKE_SAMPLE = bytes.fromhex("4400c409b400c800")


class FakeBackend:
    def __init__(self) -> None:
        self.calls: list = []
        self.adapter = True
        self.adapter_error = "no Bluetooth adapter"
        self.devices = [KICKR, HRM]
        self.connect_error: Optional[str] = None
        self.reads = dict(READS)
        self.writes: list = []
        self.subscriptions: dict = {}
        # Control point result code sent back for every write (None: no response).
        self.cp_result: Optional[int] = 0x01
        self._on_disconnect = None
        self._address = ""
        self._stop: Optional[asyncio.Event] = None

    def ops(self) -> list:
        return [c[0] for c in self.calls]

    def set_disconnect_callback(self, cb) -> None:
        self._on_disconnect = cb

    async def init(self):
        self.calls.append(("init",))
        return (True, "") if self.adapter else (False, self.adapter_error)

    async def scan(self, seconds, on_device) -> None:
        self.calls.append(("scan", seconds))
        for d in self.devices:
            on_device(dict(d))
        self._stop = asyncio.Event()
        if seconds > 0:
            try:
                await asyncio.wait_for(self._stop.wait(), timeout=seconds)
            except asyncio.TimeoutError:
                pass
        self._stop = None

    async def stop_scan(self) -> None:
        self.calls.append(("stop_scan",))
        if self._stop is not None:
            self._stop.set()

    async def connect(self, address):
        self.calls.append(("connect", address))
        if self.connect_error:
            raise BackendError(self.connect_error)
        self._address = address
        return {"address": address, "name": "KICKR CORE 2B7E"}

    async def disconnect(self) -> None:
        self.calls.append(("disconnect",))

    async def discover(self):
        self.calls.append(("discover",))
        return FTMS_SERVICES

    async def read(self, service, char):
        self.calls.append(("read", service, char))
        key = ftms.expand_uuid(char)
        if key not in self.reads:
            raise BackendError("read failed: %s" % key)
        return self.reads[key]

    async def write(self, service, char, data, with_response) -> None:
        self.calls.append(("write", service, char, bytes(data), with_response))
        self.writes.append(bytes(data))
        cb = self.subscriptions.get(ftms.expand_uuid("2ad9"))
        if cb is not None and self.cp_result is not None and ftms.same_uuid(char, "2ad9"):
            cb(ftms.expand_uuid("2ad9"), bytes([0x80, data[0], self.cp_result]))

    async def subscribe(self, service, char, on_notify) -> None:
        self.calls.append(("subscribe", service, char))
        self.subscriptions[ftms.expand_uuid(char)] = on_notify
        if ftms.same_uuid(char, "2ad2"):
            on_notify(char, BIKE_SAMPLE)

    # helpers
    def notify(self, char: str, data: bytes) -> None:
        self.subscriptions[ftms.expand_uuid(char)](ftms.expand_uuid(char), data)

    def drop(self, reason: str = "remote") -> None:
        if self._on_disconnect is not None:
            self._on_disconnect(self._address, reason)
