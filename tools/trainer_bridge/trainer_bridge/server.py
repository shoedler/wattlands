"""The GATT proxy: a WebSocket server on ws://127.0.0.1:8765 for BridgeTransport.

One client at a time (the app). Requests run in order; a scan runs in the background and
streams ``device`` events, then ``scan_stopped``. Notifications arrive as ``notify``
events, and every link loss (requested or not) as one ``disconnected`` event. When the
client goes away the bridge stops scanning and releases the trainer.

Hardware lock (BRIEF 1): when the bridge's own environment has WATTLANDS_NO_HW_CONTROL=1,
every ``write`` is refused with "hardware control locked" (scan, read and subscribe still
work). The server only ever listens on 127.0.0.1.
"""

from __future__ import annotations

import asyncio
import math
import os
import sys
from typing import Callable, Optional

from . import __version__, ftms
from .backend import BackendError, GattBackend
from .protocol import (
    NAME,
    PROTO,
    ProtocolError,
    decode_hex,
    encode_hex,
    event,
    parse_request,
    require_str,
    response,
)

HOST = "127.0.0.1"
DEFAULT_PORT = 8765
HW_ENV = "WATTLANDS_NO_HW_CONTROL"
HW_MESSAGE = "hardware control locked"


def hw_locked(env: Optional[dict] = None) -> bool:
    return (os.environ if env is None else env).get(HW_ENV) == "1"


def _log(text: str) -> None:
    print("trainer_bridge: " + text, file=sys.stderr, flush=True)


class BridgeServer:
    def __init__(self, backend: GattBackend, allow_writes: Optional[bool] = None,
                 log: Callable[[str], None] = _log) -> None:
        self.backend = backend
        self.allow_writes = (not hw_locked()) if allow_writes is None else allow_writes
        self.log = log
        self._ws = None
        self._address = ""
        self._linked = False
        self._scan_task: Optional[asyncio.Task] = None
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._pending_sends: set = set()

    # --- connection -------------------------------------------------------------------

    async def handler(self, ws) -> None:
        from websockets.exceptions import ConnectionClosed

        if self._ws is not None:
            await ws.close(1013, "busy: the bridge serves one client at a time")
            return
        self._ws = ws
        self._loop = asyncio.get_running_loop()
        self.backend.set_disconnect_callback(self._on_backend_disconnect)
        try:
            async for text in ws:
                if isinstance(text, str):
                    await self.handle_text(text)
        except ConnectionClosed:
            pass
        finally:
            self._ws = None
            await self._release()

    async def _release(self) -> None:
        if self._scan_task is not None:
            self._scan_task.cancel()
            self._scan_task = None
        try:
            await self.backend.stop_scan()
            if self._linked:
                self._linked = False
                await self.backend.disconnect()
        except Exception as exc:  # pragma: no cover - best effort on shutdown
            self.log("release failed: %s" % exc)

    async def _send(self, text: str) -> None:
        ws = self._ws
        if ws is None:
            return
        try:
            await ws.send(text)
        except Exception:
            pass

    def _emit(self, text: str) -> None:
        """Send from a backend callback (may run outside the event loop's thread)."""
        loop = self._loop
        if loop is None:
            return

        def schedule() -> None:
            task = asyncio.ensure_future(self._send(text))
            self._pending_sends.add(task)
            task.add_done_callback(self._pending_sends.discard)

        try:
            if loop.is_running() and _in_loop_thread(loop):
                schedule()
            else:
                loop.call_soon_threadsafe(schedule)
        except RuntimeError:
            pass

    def _on_backend_disconnect(self, address: str, reason: str) -> None:
        if not self._linked:
            return
        self._linked = False
        self._emit(event("disconnected", address=address or self._address, reason=reason or "remote"))

    # --- requests ---------------------------------------------------------------------

    async def handle_text(self, text: str) -> None:
        try:
            msg = parse_request(text)
        except ProtocolError as exc:
            await self._send(response(_loose_id(text), False, None, str(exc)))
            return
        op = msg["op"]
        try:
            result = await getattr(self, "_op_" + op)(msg)
        except (ProtocolError, BackendError) as exc:
            await self._send(response(msg["id"], False, None, str(exc)))
            return
        except Exception as exc:
            self.log("%s failed: %r" % (op, exc))
            await self._send(response(msg["id"], False, None, "%s failed: %s" % (op, exc)))
            return
        await self._send(response(msg["id"], True, result))

    async def _op_hello(self, _msg: dict) -> dict:
        return {"name": NAME, "version": __version__, "proto": PROTO, "writes_allowed": self.allow_writes}

    async def _op_init(self, _msg: dict) -> dict:
        ok, error = await self.backend.init()
        return {"adapter": bool(ok), "error": "" if ok else str(error)}

    async def _op_scan(self, msg: dict) -> dict:
        seconds = msg.get("seconds", 10.0)
        if not isinstance(seconds, (int, float)) or isinstance(seconds, bool) \
                or not math.isfinite(seconds) or seconds < 0:
            raise ProtocolError("seconds must be a number >= 0")
        if self._scan_task is not None and not self._scan_task.done():
            await self.backend.stop_scan()
            self._scan_task.cancel()
        self._scan_task = asyncio.ensure_future(self._run_scan(float(seconds)))
        return {}

    async def _run_scan(self, seconds: float) -> None:
        def found(info: dict) -> None:
            self._emit(event(
                "device",
                address=str(info.get("address", "")),
                name=info.get("name") or "",
                rssi=info.get("rssi") if isinstance(info.get("rssi"), int) else -127,
                services=[ftms.expand_uuid(str(u)) for u in info.get("services", [])],
            ))

        try:
            await self.backend.scan(seconds, found)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            self.log("scan failed: %s" % exc)
        await self._send(event("scan_stopped"))

    async def _op_stop_scan(self, _msg: dict) -> dict:
        await self.backend.stop_scan()
        return {}

    async def _op_connect(self, msg: dict) -> dict:
        address = require_str(msg, "address")
        result = await self.backend.connect(address)
        self._address = str(result.get("address") or address)
        self._linked = True
        return {"address": self._address, "name": str(result.get("name") or "")}

    async def _op_disconnect(self, _msg: dict) -> dict:
        await self.backend.disconnect()
        if self._linked:
            self._linked = False
            await self._send(event("disconnected", address=self._address, reason="local"))
        return {}

    async def _op_discover(self, _msg: dict) -> dict:
        services = await self.backend.discover()
        out = []
        for svc in services:
            out.append({
                "uuid": ftms.expand_uuid(str(svc.get("uuid", ""))),
                "characteristics": [
                    {"uuid": ftms.expand_uuid(str(c.get("uuid", ""))),
                     "properties": sorted(str(p) for p in c.get("properties", []))}
                    for c in svc.get("characteristics", [])
                ],
            })
        return {"services": out}

    async def _op_read(self, msg: dict) -> dict:
        service = ftms.expand_uuid(require_str(msg, "service"))
        char = ftms.expand_uuid(require_str(msg, "char"))
        data = await self.backend.read(service, char)
        return {"char": char, "data": encode_hex(data)}

    async def _op_write(self, msg: dict) -> dict:
        service = ftms.expand_uuid(require_str(msg, "service"))
        char = ftms.expand_uuid(require_str(msg, "char"))
        if not self.allow_writes:
            self.log("%s: write to %s refused" % (HW_MESSAGE, char))
            raise ProtocolError(HW_MESSAGE)
        data = decode_hex(msg.get("data"))
        await self.backend.write(service, char, data, bool(msg.get("with_response", True)))
        return {"char": char}

    async def _op_subscribe(self, msg: dict) -> dict:
        service = ftms.expand_uuid(require_str(msg, "service"))
        char = ftms.expand_uuid(require_str(msg, "char"))

        def notified(uuid: str, data: bytes) -> None:
            self._emit(event("notify", char=ftms.expand_uuid(uuid), data=encode_hex(data)))

        await self.backend.subscribe(service, char, notified)
        return {"char": char}


def _loose_id(text: str) -> int:
    import json

    try:
        msg = json.loads(text)
    except Exception:
        return 0
    if isinstance(msg, dict) and isinstance(msg.get("id"), int) and not isinstance(msg.get("id"), bool):
        return msg["id"]
    return 0


def _in_loop_thread(loop: asyncio.AbstractEventLoop) -> bool:
    try:
        return asyncio.get_running_loop() is loop
    except RuntimeError:
        return False


async def serve(backend: GattBackend, port: int = DEFAULT_PORT, ready: Optional[asyncio.Future] = None,
                allow_writes: Optional[bool] = None) -> None:
    """Run the bridge until cancelled. ``ready`` (optional) receives the bound port."""
    from websockets.asyncio.server import serve as ws_serve

    bridge = BridgeServer(backend, allow_writes=allow_writes)
    async with ws_serve(bridge.handler, HOST, port, max_size=1 << 20) as server:
        bound = server.sockets[0].getsockname()[1] if server.sockets else port
        if ready is not None and not ready.done():
            ready.set_result(bound)
        else:
            _log("listening on ws://%s:%d%s" % (HOST, bound, "" if bridge.allow_writes else " (" + HW_MESSAGE + ")"))
        await asyncio.Future()
