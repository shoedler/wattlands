# Credits

Third-party code, fonts, audio and generated art used by Wattlands. Platform entries are merged here from `docs/credits.d/` fragments by the lead; games added after v0.1.0 keep their entries in `docs/credits.d/<id>.md`. Versions, sources and SHA-256 sums are in `docs/DEPENDENCIES.md` and `docs/deps.d/`.

## Code

- Godot Engine 4.7.2, MIT, https://godotengine.org/license (with the engine's own third-party notices).
- GDBLE v0.6.0, MIT, Copyright (c) 2025 Fantety, https://github.com/Fantety/GDBLE (Bluetooth LE GDExtension). Its DLL statically links btleplug 0.12 (MIT/Apache-2.0/BSD-3-Clause, https://github.com/deviceplug/btleplug) and godot-rust `godot` 0.5.2 (MPL-2.0, source at https://github.com/godot-rust/gdext).
- GUT 9.7.1 (Godot Unit Test), MIT, https://github.com/bitwes/Gut (tests only).
- ws 8.22.0, MIT, https://github.com/websockets/ws (relay server; the relay also runs without it).
- @garmin/fitsdk 21.218.0, Garmin FIT Protocol License, https://www.npmjs.com/package/@garmin/fitsdk (test tool only: tools/fit_check; installed by npm ci, never shipped).

The Windows build ships `docs/THIRD_PARTY_NOTICES.txt` next to the executable.
