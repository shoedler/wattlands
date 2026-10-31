# Dependencies

Every third-party dependency, merged from `docs/deps.d/` (one record per dependency, with source, version, license and SHA-256 sums). Third-party code is vendored from GitHub releases or pinned commits, never from the in-editor Asset Store (BRIEF 1). `docs/THIRD_PARTY_NOTICES.txt` is the notice file the Windows build ships.

## In the app

| Dependency | Version | License | Where | Used for | Record |
| --- | --- | --- | --- | --- | --- |
| Godot Engine | 4.7.2 stable (.NET build used here for running and testing; the standard Windows templates for exports) | MIT (plus the engine's own third-party notices) | Installed separately | Engine and runtime | `docs/decisions/lead.md` |
| GDBLE | v0.6.0 (tag commit `ecae959`) | MIT; the DLL statically links btleplug 0.12 (MIT/Apache-2.0/BSD-3-Clause) and godot-rust `godot` 0.5.2 (MPL-2.0) | `addons/gdble/` (Windows and Linux x86_64 libraries) | Bluetooth LE GDExtension | `docs/deps.d/gdble.md` |
| Microsoft Visual C++ 2015-2022 x64 runtime | system | Microsoft redistributable terms | Installed on most PCs; `tools/export_windows.mjs --with-vcruntime` can ship `vcruntime140.dll` next to the exe | Needed by the GDBLE DLL | `docs/THIRD_PARTY_NOTICES.txt` |

Fonts and audio: Atkinson Hyperlegible was not downloaded in this run; the theme uses Godot's default font (BRIEF 3.9 fallback). Every sound is made from recipes in this repository (no samples, no CC0 packs). Dropping the two Atkinson Hyperlegible `.ttf` files and `OFL.txt` into `addons/wattlands/ui/theme/fonts/` switches the theme with no code change (`docs/decisions/ui-hud.md`).

## Servers and tools (not shipped with the app)

| Dependency | Version | License | Where | Used for | Record |
| --- | --- | --- | --- | --- | --- |
| Node.js | 22.12 or newer on PATH (26.12 here; on 22.12-22.17 the relay needs `--experimental-strip-types`, which the tools pass) | MIT | Installed separately | Relay, mock Strava, mock fal, art pipeline, e2e harness, tool wrappers | — |
| ws | 8.22.0 | MIT | `server/relay/package.json` + lockfile, `npm ci` | The relay's preferred WebSocket layer (a zero-dependency RFC 6455 server is the fallback) | `docs/deps.d/ws.md` |
| @garmin/fitsdk | 21.218.0 | Garmin FIT Protocol License (not open source; internal use, no redistribution) | `tools/fit_check/package.json` + lockfile, `npm ci` | Decoding FIT files in tests (`tools/fit_check`); the app's encoder shares no code with it | `docs/deps.d/garmin-fitsdk.md` |
| GUT (Godot Unit Test) | 9.7.1 (`aeb5d4f`) | MIT | `addons/gut/` (excluded from exports) | Unit tests | `docs/deps.d/gut.md` |
| gdtoolkit (gdlint, gdformat) | 4.5.0, pinned in `tools/lib/run_tests.mjs` | MIT | `uvx`, not vendored | Lint in the static gate (skipped when unavailable) | `docs/deps.d/gdtoolkit.md` |
| bleak, websockets, PyInstaller | bleak not installable on Python 3.15 here; websockets 17.3; PyInstaller 6.22.3 | MIT; BSD-3-Clause; GPL-2.0+ with the bootloader exception | `tools/trainer_bridge`, installed at use time | The optional Python trainer bridge and probe (P1) | `docs/deps.d/trainer_bridge.md` |

Optional tools: Python 3.12+ with uv (the trainer bridge and linting), Docker (the relay image).
