### Bluetooth (ble)

- `GdbleTransport`: the trainer over the vendored GDBLE 0.6.0 (`ClassDB.instantiate`, every call by name), with exactly-once link events, UUID expansion, no-adapter as a warning, adapter loss and GATT resets from `ble_event`, and writes refused under the hardware lock.
- `BridgeTransport`: the same surface over the Python trainer bridge on `ws://127.0.0.1:8765` (loopback only), with open and request timeouts.
- `FtmsConnectionManager`: backend choice (GDBLE, then the bridge, then a clear "no adapter" status), the 0x1826 / KICKR scan filter, connect -> `FtmsClient.attach` + `begin()` -> `trainer_ready`, the last device remembered and auto-connected, reconnect with 1, 2, 4, 8, 15 s backoff followed by `reconnected(device)` so the governor restores its last safe mode, and "another app may hold control" on control lost.
- `tools/trainer_bridge`: the Python GATT proxy (bleak + websockets), a read-only `probe` (control only with `--allow-control`, a typed phrase and no hardware lock), FTMS parsers with golden vectors, unittest suites, a README and a PyInstaller spec.
- Tests: `tests/ble/` (GDBLE surface introspection, transport mapping with a fake GDBLE, the bridge transport against an in-process WebSocket server, the manager with fake transports and client).
