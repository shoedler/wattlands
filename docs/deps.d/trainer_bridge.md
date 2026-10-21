# Python packages for tools/trainer_bridge (optional, not vendored)

The trainer bridge (BRIEF 4.2, P1) is an optional tool. Its packages are installed at use time with uv or pip and are never vendored into the repo or shipped with the app, so there are no archives or SHA-256 sums to record. The app itself has no Python dependency.

| Package | Used for | License | Source | Version checked here |
| --- | --- | --- | --- | --- |
| bleak | Bluetooth LE (WinRT on Windows, BlueZ on Linux), `BleakBackend` only | MIT | https://github.com/hbldh/bleak | not installable here: 3.0.2 needs `winrt-*` wheels that don't exist for Python 3.15.0 and fell back to a source build needing Microsoft C++ Build Tools (2026-10-21) |
| websockets | The bridge's WebSocket server, and the server tests' client | BSD-3-Clause | https://github.com/python-websockets/websockets | 17.3 (`>=13` required for `websockets.asyncio`) |
| PyInstaller | `trainer_bridge.spec`, the one-file Windows exe (build time only) | GPL-2.0-or-later with the bootloader exception (the built exe may carry any license) | https://github.com/pyinstaller/pyinstaller | 6.22.3; the spec built `trainer_bridge.exe` (without bleak) on 2026-10-21 |

A shipped `trainer_bridge.exe` bundles bleak, websockets and the Python runtime (PSF license); the credits for such a build would list all three.
