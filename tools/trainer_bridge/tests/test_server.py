"""The GATT proxy over a real WebSocket on 127.0.0.1 (ephemeral port) with a fake backend.
Skipped when the websockets package is not installed."""

import asyncio
import contextlib
import json
import os
import unittest

from trainer_bridge import ftms, server

from .fake_backend import FakeBackend

try:
    from websockets.asyncio.client import connect
    from websockets.exceptions import ConnectionClosed
    HAVE_WEBSOCKETS = True
except ImportError:  # pragma: no cover
    HAVE_WEBSOCKETS = False

FTMS = ftms.expand_uuid("1826")
FEATURE = ftms.expand_uuid("2acc")
IBD = ftms.expand_uuid("2ad2")
CP = ftms.expand_uuid("2ad9")


@unittest.skipUnless(HAVE_WEBSOCKETS, "websockets is not installed")
class ServerTest(unittest.IsolatedAsyncioTestCase):
    allow_writes = False

    async def asyncSetUp(self) -> None:
        self.backend = FakeBackend()
        self.events: list = []
        self.next_id = 1
        ready = asyncio.get_running_loop().create_future()
        self.task = asyncio.create_task(server.serve(self.backend, port=0, ready=ready, allow_writes=self.allow_writes))
        self.port = await asyncio.wait_for(ready, 5)
        self.ws = await connect("ws://127.0.0.1:%d" % self.port)

    async def asyncTearDown(self) -> None:
        await self.ws.close()
        self.task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await self.task

    async def request(self, op: str, **fields) -> dict:
        req_id = self.next_id
        self.next_id += 1
        msg = {"id": req_id, "op": op}
        msg.update(fields)
        await self.ws.send(json.dumps(msg))
        while True:
            reply = json.loads(await asyncio.wait_for(self.ws.recv(), 5))
            if "event" in reply:
                self.events.append(reply)
                continue
            self.assertEqual(reply["id"], req_id)
            return reply

    async def wait_event(self, name: str) -> dict:
        for e in self.events:
            if e["event"] == name:
                self.events.remove(e)
                return e
        while True:
            msg = json.loads(await asyncio.wait_for(self.ws.recv(), 5))
            if msg.get("event") == name:
                return msg
            self.events.append(msg)

    async def test_hello_and_init(self) -> None:
        hello = await self.request("hello", proto=1, client="wattlands")
        self.assertTrue(hello["ok"])
        self.assertEqual(hello["result"]["name"], "wattlands-trainer-bridge")
        self.assertEqual(hello["result"]["proto"], 1)
        self.assertFalse(hello["result"]["writes_allowed"])
        init = await self.request("init")
        self.assertEqual(init["result"], {"adapter": True, "error": ""})

    async def test_init_without_adapter(self) -> None:
        self.backend.adapter = False
        init = await self.request("init")
        self.assertTrue(init["ok"])
        self.assertEqual(init["result"], {"adapter": False, "error": "no Bluetooth adapter"})

    async def test_scan_streams_devices(self) -> None:
        reply = await self.request("scan", seconds=0)
        self.assertTrue(reply["ok"])
        first = await self.wait_event("device")
        second = await self.wait_event("device")
        await self.wait_event("scan_stopped")
        self.assertEqual(first["address"], "C4:9D:A1:00:2B:7E")
        self.assertEqual(first["services"], [FTMS, ftms.expand_uuid("180a")])
        self.assertEqual(second["name"], "HRM-Pro")
        bad = await self.request("scan", seconds=-1)
        self.assertFalse(bad["ok"])

    async def test_connect_discover_read_subscribe_notify(self) -> None:
        conn = await self.request("connect", address="C4:9D:A1:00:2B:7E")
        self.assertEqual(conn["result"], {"address": "C4:9D:A1:00:2B:7E", "name": "KICKR CORE 2B7E"})
        disc = await self.request("discover")
        svc = disc["result"]["services"][0]
        self.assertEqual(svc["uuid"], FTMS)
        self.assertIn({"uuid": CP, "properties": ["indicate", "write"]}, svc["characteristics"])
        read = await self.request("read", service="1826", char="2ACC")
        self.assertEqual(read["result"], {"char": FEATURE, "data": "824000000ce00000"})
        self.assertIn(("read", FTMS, FEATURE), self.backend.calls, "UUIDs expanded before the backend")
        sub = await self.request("subscribe", service="0x1826", char="2ad2")
        self.assertEqual(sub["result"], {"char": IBD})
        note = await self.wait_event("notify")
        self.assertEqual(note, {"event": "notify", "char": IBD, "data": "4400c409b400c800"})
        self.backend.notify("2ad2", bytes.fromhex("4400c409b400fa00"))
        note = await self.wait_event("notify")
        self.assertEqual(note["data"], "4400c409b400fa00")

    async def test_read_failure_is_an_error_reply(self) -> None:
        await self.request("connect", address="AA")
        reply = await self.request("read", service="1826", char="2a00")
        self.assertFalse(reply["ok"])
        self.assertIn("read failed", reply["error"])

    async def test_connect_failure(self) -> None:
        self.backend.connect_error = "device not found"
        reply = await self.request("connect", address="AA")
        self.assertEqual((reply["ok"], reply["error"]), (False, "device not found"))
        missing = await self.request("connect")
        self.assertFalse(missing["ok"])

    async def test_disconnect_events(self) -> None:
        await self.request("connect", address="AA:BB")
        self.backend.drop("remote")
        gone = await self.wait_event("disconnected")
        self.assertEqual(gone, {"event": "disconnected", "address": "AA:BB", "reason": "remote"})
        await self.request("connect", address="AA:BB")
        reply = await self.request("disconnect")
        self.assertTrue(reply["ok"])
        gone = await self.wait_event("disconnected")
        self.assertEqual(gone["reason"], "local")

    async def test_connect_again_is_idempotent_and_switching_releases(self) -> None:
        await self.request("connect", address="AA:BB")
        again = await self.request("connect", address="aa:bb")
        self.assertTrue(again["ok"])
        self.assertEqual(again["result"], {"address": "AA:BB", "name": "KICKR CORE 2B7E"})
        self.assertEqual(self.backend.ops().count("connect"), 1, "no second link to the same trainer")
        other = await self.request("connect", address="CC:DD")
        self.assertEqual(other["result"]["address"], "CC:DD")
        self.assertEqual(self.backend.ops()[-2:], ["disconnect", "connect"], "the old link is released first")
        self.backend.drop("remote")
        await self.wait_event("disconnected")
        await self.request("connect", address="CC:DD")
        self.assertEqual(self.backend.ops().count("connect"), 3, "after a drop it connects again")

    async def test_writes_refused_when_locked(self) -> None:
        await self.request("connect", address="AA")
        reply = await self.request("write", service="1826", char="2ad9", data="00", with_response=True)
        self.assertEqual((reply["ok"], reply["error"]), (False, "hardware control locked"))
        self.assertEqual(self.backend.writes, [])

    async def test_bad_requests(self) -> None:
        await self.ws.send("not json")
        reply = json.loads(await asyncio.wait_for(self.ws.recv(), 5))
        self.assertEqual((reply["id"], reply["ok"]), (0, False))
        unknown = await self.request("format_disk")
        self.assertFalse(unknown["ok"])
        self.assertIn("unknown op", unknown["error"])

    async def test_one_client_at_a_time(self) -> None:
        second = await connect("ws://127.0.0.1:%d" % self.port)
        with self.assertRaises(ConnectionClosed):
            await asyncio.wait_for(second.recv(), 5)
        self.assertEqual(second.close_code, 1013)
        hello = await self.request("hello")
        self.assertTrue(hello["ok"], "the first client keeps working")

    async def test_client_leaving_releases_the_trainer(self) -> None:
        await self.request("connect", address="AA")
        await self.ws.close()
        for _ in range(100):
            if "disconnect" in self.backend.ops():
                break
            await asyncio.sleep(0.01)
        self.assertIn("disconnect", self.backend.ops())
        self.assertIn("stop_scan", self.backend.ops())


@unittest.skipUnless(HAVE_WEBSOCKETS, "websockets is not installed")
class UnlockedServerTest(ServerTest):
    """The same server with writes allowed (as with --allow-hw); the backend is a fake."""

    allow_writes = True

    async def test_writes_refused_when_locked(self) -> None:
        await self.request("connect", address="AA")
        reply = await self.request("write", service="1826", char="2ad9", data="05c800", with_response=True)
        self.assertEqual(reply["result"], {"char": CP})
        self.assertEqual(self.backend.calls[-1], ("write", FTMS, CP, b"\x05\xc8\x00", True))
        bad = await self.request("write", service="1826", char="2ad9", data="xyz")
        self.assertFalse(bad["ok"])

    async def test_hello_and_init(self) -> None:
        hello = await self.request("hello")
        self.assertTrue(hello["result"]["writes_allowed"])


@unittest.skipUnless(HAVE_WEBSOCKETS, "websockets is not installed")
class TwoClientTest(unittest.IsolatedAsyncioTestCase):
    """A trainer and a heart rate sensor: two sockets, each with its own backend."""

    async def start(self, factory) -> int:
        self.first = FakeBackend()
        ready = asyncio.get_running_loop().create_future()
        self.task = asyncio.create_task(server.serve(
            self.first, port=0, ready=ready, allow_writes=False, backend_factory=factory))
        return await asyncio.wait_for(ready, 5)

    async def asyncTearDown(self) -> None:
        self.task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await self.task

    async def call(self, ws, req_id: int, op: str, **fields) -> dict:
        msg = {"id": req_id, "op": op}
        msg.update(fields)
        await ws.send(json.dumps(msg))
        while True:
            reply = json.loads(await asyncio.wait_for(ws.recv(), 5))
            if "event" not in reply:
                return reply

    async def test_second_client_gets_its_own_backend(self) -> None:
        made: list = []

        def factory():
            made.append(FakeBackend())
            return made[-1]

        port = await self.start(factory)
        url = "ws://127.0.0.1:%d" % port
        async with connect(url) as trainer, connect(url) as hr:
            self.assertTrue((await self.call(trainer, 1, "connect", address="AA"))["ok"])
            self.assertTrue((await self.call(hr, 1, "connect", address="BB"))["ok"])
            self.assertEqual(len(made), 1)
            self.assertIn(("connect", "AA"), self.first.calls)
            self.assertIn(("connect", "BB"), made[0].calls)
            write = await self.call(hr, 2, "write", service="180d", char="2a37", data="00")
            self.assertFalse(write["ok"])
            self.assertEqual(write["error"], server.HW_MESSAGE)
            third = await connect(url)
            with self.assertRaises(ConnectionClosed):
                await asyncio.wait_for(third.recv(), 5)

    async def test_without_a_factory_a_second_client_is_busy(self) -> None:
        port = await self.start(None)
        url = "ws://127.0.0.1:%d" % port
        async with connect(url) as first:
            self.assertTrue((await self.call(first, 1, "hello"))["ok"])
            second = await connect(url)
            with self.assertRaises(ConnectionClosed):
                await asyncio.wait_for(second.recv(), 5)


class LockTest(unittest.TestCase):
    def test_default_follows_the_environment(self) -> None:
        bridge = server.BridgeServer(FakeBackend())
        self.assertEqual(bridge.allow_writes, os.environ.get("WATTLANDS_NO_HW_CONTROL") != "1")
        self.assertTrue(server.hw_locked({"WATTLANDS_NO_HW_CONTROL": "1"}))
        self.assertFalse(server.hw_locked({}))

    def test_listens_on_loopback_only(self) -> None:
        self.assertEqual(server.HOST, "127.0.0.1")


if __name__ == "__main__":
    unittest.main()
