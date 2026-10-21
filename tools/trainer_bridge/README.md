# Trainer bridge

A thin Bluetooth LE GATT proxy for Wattlands (BRIEF 4.2, P1 fallback) and a read-only `probe` for a real trainer. Python 3.12+, [bleak](https://github.com/hbldh/bleak) and [websockets](https://github.com/python-websockets/websockets).

The app normally talks to the trainer in-process through GDBLE (`GdbleTransport`). When the GDBLE library isn't loaded, or it finds no adapter, `FtmsConnectionManager` tries this bridge on `ws://127.0.0.1:8765` through `BridgeTransport` (`addons/wattlands/trainer/ble/bridge_transport.gd`). Both transports have the same surface, so `FtmsClient` and everything above it can't tell them apart.

## Install

```sh
# with uv (no virtualenv to manage)
uv run --with bleak --with websockets python -m trainer_bridge --help

# or with pip
python -m pip install bleak websockets
python -m trainer_bridge --help
```

Run the commands from this folder (`tools/trainer_bridge`).

bleak needs prebuilt `winrt-*` wheels on Windows. Use a Python version they exist for (3.12 or 3.13 at the time of writing). On Python 3.15 the wheels were missing on 2026-10-21 and pip tried to compile them, which needs Microsoft C++ Build Tools.

## Commands

| Command | What it does |
| --- | --- |
| `python -m trainer_bridge serve [--port 8765]` | Runs the GATT proxy on `ws://127.0.0.1:<port>` for the app. Loopback only, one client at a time. |
| `python -m trainer_bridge probe [--seconds 30] [--address AA:BB:...] [--scan-seconds 10]` | Scans for FTMS trainers (service 0x1826 or a name containing KICKR), connects to `--address` or the first one found, reads Device Information, Fitness Machine Feature, Supported Power Range and Supported Resistance Level Range, then prints parsed Indoor Bike Data and Machine Status for 30 s. Read-only. |
| `python -m trainer_bridge probe --allow-control` | The same, plus Request Control and SIM flat (grade 0), after you type the confirmation phrase `I AM ON THE TRAINER`. Refused outright while `WATTLANDS_NO_HW_CONTROL=1` is set. |

Exit codes of `probe`: 0 done, 2 no adapter or no trainer, 3 refused (lock or no confirmation), 4 connect failed.

Step 1 of `docs/HARDWARE_TEST_PLAN.md` uses the read-only probe. Close Zwift and the Wahoo app first: a trainer accepts one controlling app at a time.

## Safety

- The probe never writes unless `--allow-control` is given and the phrase is typed. Even then it only sends Request Control and SIM flat, the trainer's gentlest state.
- Hardware lock (BRIEF 1): while the bridge's environment has `WATTLANDS_NO_HW_CONTROL=1` (every automated run in this repo sets it through `tools/env.sh`), `serve` refuses every `write` with `hardware control locked`, and `probe --allow-control` refuses to start. Scanning, reading and subscribing still work. `BridgeTransport` refuses writes under the same lock on the app side, and `FtmsClient` refuses control writes before either.
- `serve` binds to 127.0.0.1 only, and `BridgeTransport` only connects to loopback URLs.
- When the app disconnects, the bridge stops scanning and releases the trainer.

## Protocol

One JSON object per WebSocket text frame. Byte payloads are lower-case hex. UUIDs in requests may be 16-bit (`"2AD2"`, `"0x2ad2"`) or full, in any case; the bridge expands them and always answers with lower-case 128-bit UUIDs.

```text
request   {"id": int, "op": str, ...fields}
response  {"id": int, "ok": bool, "result": any, "error": str}
event     {"event": str, ...fields}
```

| Op | Fields | Result |
| --- | --- | --- |
| `hello` | `proto` (1), `client` | `{name: "wattlands-trainer-bridge", version, proto: 1, writes_allowed}` |
| `init` | | `{adapter: bool, error: str}` |
| `scan` | `seconds` (0 = until `stop_scan`) | `{}`, then `device` events and one `scan_stopped` |
| `stop_scan` | | `{}` |
| `connect` | `address` | `{address, name}`; for the trainer already linked it answers again without a second link, and a different address releases the old link first |
| `disconnect` | | `{}`, then a `disconnected` event with reason `local` |
| `discover` | | `{services: [{uuid, characteristics: [{uuid, properties: [str]}]}]}` |
| `read` | `service`, `char` | `{char, data}` |
| `write` | `service`, `char`, `data`, `with_response` | `{char}`; error `hardware control locked` under the lock |
| `subscribe` | `service`, `char` | `{char}`, then `notify` events (indications for 0x2AD9) |

| Event | Fields |
| --- | --- |
| `device` | `address`, `name`, `rssi`, `services` |
| `scan_stopped` | |
| `notify` | `char`, `data` |
| `disconnected` | `address`, `reason` (`local` or `remote`) |
| `adapter` | `ok`, `error` |

Requests run in order. A failed request answers `ok: false` with an error text; a malformed one answers with `id` 0. The bridge never retries or reconnects: `FtmsConnectionManager` reconnects with backoff (1, 2, 4, 8, 15 s), re-running `initialize()` on `BridgeTransport` first when the bridge itself went away.

## Tests

The tests never open a Bluetooth adapter: the server and the probe run against a fake backend (`tests/fake_backend.py`), and the server tests use a real WebSocket on 127.0.0.1 with an ephemeral port.

```sh
. ../env.sh   # from tools/trainer_bridge: the repo's locks
uv run --no-project --with "websockets>=13" python -m unittest discover -s tests -t .
```

- `tests/test_ftms.py`: the FTMS parsers and encoders against golden vectors. `tests/vectors_local.json` is transcribed from BRIEF 4.3. When `tests/vectors/ftms.json` (written by trainer-core for the GDScript codec) is present, every Indoor Bike Data case in it that maps onto these field names is checked too; until then that test is skipped.
- `tests/test_protocol.py`: the message helpers.
- `tests/test_server.py`: the proxy end to end over WebSocket (skipped without websockets), locked and unlocked.
- `tests/test_probe.py`: read-only by default, the lock and the typed confirmation, and the exact two writes `--allow-control` sends.

## Windows exe

`trainer_bridge.spec` builds a one-file console exe with PyInstaller:

```sh
uv run --with bleak --with websockets --with pyinstaller pyinstaller --noconfirm --distpath ../../build/trainer_bridge/dist --workpath ../../build/trainer_bridge/work trainer_bridge.spec
```

The result is `build/trainer_bridge/dist/trainer_bridge.exe`, with the same commands (`trainer_bridge.exe serve`, `trainer_bridge.exe probe`). The app could start it with `OS.create_process`; it doesn't yet (see the ble ADRs).

## Files

- `trainer_bridge/ftms.py`: FTMS parsers and encoders (pure, bounds-checked).
- `trainer_bridge/protocol.py`: the JSON messages.
- `trainer_bridge/backend.py`: the async GATT surface and `BleakBackend` (bleak is imported lazily).
- `trainer_bridge/server.py`: the proxy.
- `trainer_bridge/probe.py`: the probe.
- `trainer_bridge/cli.py`, `__main__.py`, `bridge.py`: the command line and the PyInstaller entry point.
