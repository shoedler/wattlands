# Godot 4.7.2 (standard build) and its Windows export template

The Windows release build is exported with the standard (non-.NET) Godot 4.7.2 editor and the official export templates. The .NET editor in `C:/Projects/.tooling/` stays the development and test binary; neither is vendored into the repository.

- Upstream: https://github.com/godotengine/godot, release `4.7.2-stable` (`4.7.2.stable.official.ed1daf0bf`).
- License: MIT (Godot Engine contributors); its notices are part of `docs/THIRD_PARTY_NOTICES.txt`, which the export ships.
- Downloaded 2026-10-22 from https://github.com/godotengine/godot/releases/download/4.7.2-stable/ and checked against that release's `SHA512-SUMS.txt`.

## Editor

- `Godot_v4.7.2-stable_win64.exe.zip`, 86,013,866 bytes.
  - SHA-256: `731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953`
  - SHA-512 (matches `SHA512-SUMS.txt`): `83decd58fdf67b9d657958a1ae6bf1929c20785315a81effe245874cdc57acb709bf868e00778a96984338c1b29dafdb453c6847747694621c6ecf5da2259993`
- Unpacked to `C:/Projects/.tooling/Godot_v4.7.2-stable_win64/` (the export uses `Godot_v4.7.2-stable_win64_console.exe` as `GODOT`).

## Export template

- `windows_release_x86_64.exe` from `Godot_v4.7.2-stable_export_templates.tpz` (the `.tpz` passed its SHA-512 in `SHA512-SUMS.txt`: `ca4d71c4…84079`), 109,268,480 bytes.
  - SHA-256: `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562`
- The copy installed in `%APPDATA%/Godot/export_templates/4.7.2.stable/` hashes the same, so it is byte-identical to the official template. `node tools/export_windows.mjs` uses it.
