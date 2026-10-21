"""GATT backends for the bridge and the probe.

``GattBackend`` is the small async surface the server and the probe use. ``BleakBackend``
implements it with bleak (imported lazily, so the protocol, the parsers and the tests run
without bleak installed). Tests use their own fake backend; nothing in the test suite
ever opens a Bluetooth adapter.
"""

from __future__ import annotations

import asyncio
from typing import Callable, Optional, Protocol

from . import ftms

DeviceCallback = Callable[[dict], None]
NotifyCallback = Callable[[str, bytes], None]
DisconnectCallback = Callable[[str, str], None]


class BackendError(RuntimeError):
    """A GATT operation failed; the message goes to the client as the error text."""


class GattBackend(Protocol):
    async def init(self) -> tuple[bool, str]: ...

    async def scan(self, seconds: float, on_device: DeviceCallback) -> None: ...

    async def stop_scan(self) -> None: ...

    async def connect(self, address: str) -> dict: ...

    async def disconnect(self) -> None: ...

    async def discover(self) -> list: ...

    async def read(self, service: str, char: str) -> bytes: ...

    async def write(self, service: str, char: str, data: bytes, with_response: bool) -> None: ...

    async def subscribe(self, service: str, char: str, on_notify: NotifyCallback) -> None: ...

    def set_disconnect_callback(self, cb: Optional[DisconnectCallback]) -> None: ...


def bleak_available() -> bool:
    try:
        import bleak  # noqa: F401
    except Exception:
        return False
    return True


class BleakBackend:
    """GattBackend over bleak (Windows WinRT, Linux BlueZ, macOS CoreBluetooth)."""

    def __init__(self) -> None:
        self._client = None
        self._address = ""
        self._scan_stop: Optional[asyncio.Event] = None
        self._on_disconnect: Optional[DisconnectCallback] = None
        self._closing = False

    def set_disconnect_callback(self, cb: Optional[DisconnectCallback]) -> None:
        self._on_disconnect = cb

    async def init(self) -> tuple[bool, str]:
        try:
            from bleak import BleakScanner
        except Exception as exc:  # bleak missing or broken
            return False, "bleak is not installed (%s)" % exc
        try:
            scanner = BleakScanner()
            await scanner.start()
            await scanner.stop()
        except Exception as exc:
            return False, "no Bluetooth adapter (%s)" % exc
        return True, ""

    async def scan(self, seconds: float, on_device: DeviceCallback) -> None:
        from bleak import BleakScanner

        def detected(device, adv) -> None:
            on_device({
                "address": device.address,
                "name": adv.local_name or device.name or "",
                "rssi": adv.rssi if adv.rssi is not None else -127,
                "services": [ftms.expand_uuid(u) for u in (adv.service_uuids or [])],
            })

        self._scan_stop = asyncio.Event()
        scanner = BleakScanner(detection_callback=detected)
        await scanner.start()
        try:
            if seconds > 0:
                try:
                    await asyncio.wait_for(self._scan_stop.wait(), timeout=seconds)
                except asyncio.TimeoutError:
                    pass
            else:
                await self._scan_stop.wait()
        finally:
            await scanner.stop()
            self._scan_stop = None

    async def stop_scan(self) -> None:
        if self._scan_stop is not None:
            self._scan_stop.set()

    async def connect(self, address: str) -> dict:
        from bleak import BleakClient

        def gone(_client) -> None:
            if self._on_disconnect is not None:
                self._on_disconnect(self._address, "local" if self._closing else "remote")

        self._closing = False
        self._address = address
        self._client = BleakClient(address, disconnected_callback=gone)
        try:
            await self._client.connect()
        except Exception as exc:
            self._client = None
            raise BackendError("connect failed: %s" % exc) from None
        name = getattr(self._client, "name", "") or ""
        return {"address": address, "name": name}

    async def disconnect(self) -> None:
        if self._client is None:
            return
        self._closing = True
        try:
            await self._client.disconnect()
        finally:
            self._client = None

    def _char(self, service: str, char: str):
        if self._client is None or not getattr(self._client, "is_connected", False):
            raise BackendError("not connected")
        svc = self._client.services.get_service(ftms.expand_uuid(service))
        if svc is None:
            raise BackendError("service %s not found" % ftms.expand_uuid(service))
        chr_ = svc.get_characteristic(ftms.expand_uuid(char))
        if chr_ is None:
            raise BackendError("characteristic %s not found" % ftms.expand_uuid(char))
        return chr_

    async def discover(self) -> list:
        if self._client is None:
            raise BackendError("not connected")
        out = []
        for svc in self._client.services:
            out.append({
                "uuid": ftms.expand_uuid(svc.uuid),
                "characteristics": [
                    {"uuid": ftms.expand_uuid(c.uuid), "properties": sorted(c.properties)}
                    for c in svc.characteristics
                ],
            })
        return out

    async def read(self, service: str, char: str) -> bytes:
        try:
            return bytes(await self._client.read_gatt_char(self._char(service, char)))
        except BackendError:
            raise
        except Exception as exc:
            raise BackendError("read failed: %s" % exc) from None

    async def write(self, service: str, char: str, data: bytes, with_response: bool) -> None:
        try:
            await self._client.write_gatt_char(self._char(service, char), data, response=with_response)
        except BackendError:
            raise
        except Exception as exc:
            raise BackendError("write failed: %s" % exc) from None

    async def subscribe(self, service: str, char: str, on_notify: NotifyCallback) -> None:
        target = self._char(service, char)
        uuid = ftms.expand_uuid(char)

        def got(_sender, data: bytearray) -> None:
            on_notify(uuid, bytes(data))

        # bleak enables indications when the characteristic only supports Indicate
        # (0x2AD9), notifications otherwise.
        try:
            await self._client.start_notify(target, got)
        except Exception as exc:
            raise BackendError("subscribe failed: %s" % exc) from None

