# GDBLE 0.6.0

- Upstream: https://github.com/Fantety/GDBLE (Rust GDExtension for Bluetooth Low Energy on btleplug; default branch `master`).
- Version: 0.6.0 (`BUILD_INFO.json` says `"version": "0.6.0"`, `"release_ready": true`, `"incomplete": []`).
- Release: `v0.6.0`, published 2026-10-18T06:30:55Z, not a draft or prerelease. Asset `gdble-v0.6.0.zip` uploaded by `github-actions[bot]`.
- Tag: `v0.6.0` is an annotated tag, object `873c57c70fbdf788803dde627002d9c4ae88481d`, which points to commit `ecae959ef60b631b3538fad4745ddc482ade8740` ("build: sync complete addon verified on GitHub runners", 2026-10-18).
  - That commit is 3 commits ahead of `13c49c745a3ba8ea854e4d004272eb8b32ca439a` (the minimum BRIEF 4.2 names) and 0 behind, so it contains it.
  - The binaries were built from commit `690a833f6c5b114b5e8adaad322789c9e8d38f44` (the tag commit's parent), source digest `eac97287ca3f62975d079b9e2b2f2c67984314d6f2f3282d0e9cacdcb6fc023e`, toolchain rustc 1.99.1, per `BUILD_INFO.json`. The tag commit only commits those built artifacts and docs.
- Archive: https://github.com/Fantety/GDBLE/releases/download/v0.6.0/gdble-v0.6.0.zip, downloaded 2026-10-21, 8,888,137 bytes.
  - SHA-256: `af11f727b7031a54b3348d47e461f6fa99912afd8bd0b134cf7396eeacd19c91`. This matches the digest GitHub publishes for the asset.
  - Every entry of the upstream `addons/gdble/SHA256SUMS` verified OK (11 of 11), and every kept file's git blob matches the same path at the tag commit.
- License: MIT, Copyright (c) 2025 Fantety. Kept at `addons/gdble/LICENSE` (SHA-256 `496415eeccc29d5bcd0f2d8dc9436ff4b0c08c37241606a63929a089802320f1`, identical to the archive's root `LICENSE`). The binaries statically link Rust crates with their own licenses; per upstream's `Cargo.toml` at the tag the main ones are btleplug 0.12 (`license = "MIT/Apache-2.0/BSD-3-Clause"` in its `Cargo.toml`) and godot-rust `godot` 0.5.2 (MPL-2.0, github.com/godot-rust/gdext). MPL-2.0 is file-level copyleft: shipping the DLL means telling users where the MPL-covered source is (crates.io / that repo). The credits fragment should name GDBLE (MIT), btleplug and godot-rust (MPL-2.0).
- Vendored into: `addons/gdble/`. Date: 2026-10-21.
- Why 0.6.0: BRIEF 4.2 says v0.5.5 aborts Godot 4.7.2's first headless import on a fresh `.godot` cache. v0.6.0 is a tagged release at or after main's `13c49c7`, so it is the pinned choice. It imports cleanly: the first headless import of the main checkout on a fresh `.godot` cache exits 0 on Godot 4.7.2 (see "Import check" below), so neither BRIEF 4.2 fallback (main's prebuilt addon, or v0.5.5 with a double import) is needed.

## Kept files (SHA-256)

| File | Bytes | SHA-256 | Changed? |
| --- | --- | --- | --- |
| `libgdble.windows.x86_64.dll` | 4,962,816 | `e49a840864255b9ed37cf43a3136d63a662cafa241815a3cf8045fa641f3c97d` | no |
| `libgdble.linux.x86_64.so` | 5,485,848 | `ba36ffb492fd4fcce82bb177005fcfc0fd5268bf89047e120581dfa42948bea2` | no |
| `BUILD_INFO.json` | 3,921 | `390220aa8e078bf3304eb4312dd1f473b6a092f1b71b7c4bad80296547610cef` | no |
| `LICENSE` | 1,064 | `496415eeccc29d5bcd0f2d8dc9436ff4b0c08c37241606a63929a089802320f1` | no |
| `gdble.gdextension` | 401 | `0f72cae272862e2cfddff76308f2da1b19596ba509e99b3c7ab6383b99552576` | yes, see below (upstream `fd7c86a346f2b85ccf3cf0b83bc2eee4f804453de2d870e67a84068099ac2a83`) |
| `docs/API_CONTRACT.md` | 8,482 | `0d43bf67142cfcf2b46460341463d9a7781c35e6e9aef5ea9ae711000b26d5b0` | no (upstream `docs/API_CONTRACT.md`) |
| `docs/README_EN.md` | 33,855 | `f3ca5a78b8317bbd5aa6b4d55c1e17327e545949528e5cadac6b1ebf4454005a` | no (upstream root `README_EN.md`) |
| `gdble.gdextension.uid` | 20 | `e371b77056b577b7959cf93939f1211ddb6b462ee2d348e2392e64325c9bf523` | added locally: written by the first Godot import, `uid://daj40y0ysg0l8`; commit it |

The two docs are upstream's API reference, kept for `addons/wattlands/trainer/ble/gdble_transport.gd`. Godot does not import `.md` files.

Git tree for `addons/gdble` (all mode 100644):

- the 7 vendored files, before any Godot import: `09200c38ab9bdc39c34e32a78a5ef7e77d1a18f2`;
- with `gdble.gdextension.uid` added by the first import (8 files, the state to commit): `b9f97530f34f35c7290e35d06ed996b40ba1d78f`. Check after the commit with `git rev-parse HEAD:addons/gdble`.

Godot 4.4+ gives every `.gdextension` a random UID on its first import, so the `.uid` file is committed like every other `*.uid` (BRIEF 2). Later imports keep it unchanged.

## Import check (2026-10-21)

Godot 4.7.2 .NET build (`4.7.2.stable.mono.official.ed1daf0bf`) through `tools/godot.sh`, Windows 11, Git Bash. Logs are in `build/vendor/` (gitignored scratch).

- `rm -rf .godot && tools/godot.sh --headless --path . --import` on the main checkout: **exit 0** in about 4 s, first try. The log prints `Initialize godot-rust (API v4.2.stable.official, runtime v4.7.2.stable.mono.official, safeguards balanced)` during "Verifying GDExtensions", then registers the project's 154 script classes, imports 38 files and finishes with no error, warning or abort line. `.godot/extension_list.cfg` lists `res://addons/gdble/gdble.gdextension`, and `.godot/global_script_class_cache.cfg` exists.
- An incremental import and a second import on a fresh cache also exit 0 and change no file in the working tree.
- Every later headless run (the probes below and the GUT runs) prints the same godot-rust line first and exits 0. Loading the library does no Bluetooth work; nothing here called `initialize()` or a scan.
- The .NET build created only an empty `.godot/mono/metadata/` directory (gitignored). It did not touch `project.godot` and wrote no `.csproj` or `.sln`.

## ClassDB surface of 0.6.0 (verified 2026-10-21)

Read with `ClassDB.class_get_method_list(cls, true)` and `ClassDB.class_get_signal_list(cls, true)` (no inheritance) from a headless `-s` probe. GDBLE registers exactly two classes (`ClassDB.class_get_api_type` = `API_EXTENSION`): `BluetoothManager` and `BleDevice`. Both are instantiable and expose no properties and no integer constants; error codes arrive as strings in `ble_event` dictionaries.

**BluetoothManager** (extends `Node`), 13 methods:

| Method | Returns | In BRIEF 4.2 |
| --- | --- | --- |
| `initialize()` | `int` | yes |
| `start_scan(timeout_seconds: float)` | `int` | yes |
| `stop_scan()` | `int` (const) | yes |
| `connect_device(address: String)` | `BleDevice` | yes |
| `get_device(address: String)` | `BleDevice` (const) | yes |
| `get_or_create_device(address: String)` | `BleDevice` | new |
| `disconnect_device(address: String)` | `int` | new |
| `get_adapter_info()` | `Dictionary` (const) | new |
| `get_connected_devices()` | `Array[BleDevice]` (const) | new |
| `get_discovered_devices()` | `Array[Dictionary]` (const) | new |
| `is_initialized()` | `bool` (const) | new |
| `is_debug_mode()` | `bool` (const) | new |
| `set_debug_mode(enabled: bool)` | `void` (const) | new |

10 signals: `adapter_initialized(success: bool, error: String)`, `device_discovered(device_info: Dictionary)`, `device_connected(address: String)` and `device_disconnected(address: String)` (all in BRIEF 4.2), plus the new `ble_event(event: Dictionary)`, `device_connecting(address: String)`, `device_updated(device_info: Dictionary)`, `error_occurred(error_message: String)`, `scan_started()` and `scan_stopped()`.

**BleDevice** (extends `RefCounted`), 11 methods:

| Method | Returns | In BRIEF 4.2 |
| --- | --- | --- |
| `connect_async()` | `int` | yes |
| `discover_services()` | `int` | yes |
| `read_characteristic(service_uuid: String, char_uuid: String)` | `int` | yes |
| `write_characteristic(service_uuid: String, char_uuid: String, data: PackedByteArray, with_response: bool)` | `int` | yes |
| `subscribe_characteristic(service_uuid: String, char_uuid: String)` | `int` | yes |
| `disconnect()` | `int` | yes, but see the name clash below |
| `unsubscribe_characteristic(service_uuid: String, char_uuid: String)` | `int` | new |
| `get_address()` | `String` (const) | new |
| `get_name()` | `String` (const) | new |
| `get_services()` | `Array[Dictionary]` (const) | new |
| `is_connected()` | `bool` (const) | new, see the name clash below |

9 signals: `connected()`, `disconnected()`, `connection_failed(error: String)`, `services_discovered(services: Array[Dictionary])`, `characteristic_read(char_uuid: String, data: PackedByteArray)`, `characteristic_written(char_uuid: String)`, `characteristic_notified(char_uuid: String, data: PackedByteArray)` and `operation_failed(operation: String, error: String)` (all in BRIEF 4.2), plus the new `ble_event(event: Dictionary)`.

**Compared with the 0.5.x surface in BRIEF 4.2:** every listed method and signal exists under the same name with the same argument count (methods 1, 0, 0, 1, 1 on the manager and 0, 0, 2, 4, 2, 0 on the device; signals 2, 1, 1, 1 and 0, 0, 1, 1, 2, 1, 2, 2). Nothing is removed or renamed and no listed argument changed type. The only change to a listed member is the return type: every action method (`initialize`, `start_scan`, `stop_scan`, `connect_async`, `discover_services`, `read_`/`write_`/`subscribe_characteristic`, `disconnect`) returns an `int` operation id, which callers may ignore. The rest of the surface is additive.

**Name clash with `Object`.** `BleDevice.disconnect()` and `BleDevice.is_connected()` take no arguments, but `Object` already has `disconnect(signal, callable)` and `is_connected(signal, callable)`. When the device is held as `RefCounted` or `Object` (as CLAUDE.md requires), GDScript's analyzer checks those calls against `Object` and refuses to compile: `Parse Error: Too few arguments for "disconnect()" call. Expected at least 2 but received 0.` (same for `is_connected()`). A probe confirmed:

- `d.disconnect()` and `d.is_connected()` on `d: RefCounted` or `d: Object`: parse error;
- `d.call(&"disconnect")` and `d.call(&"is_connected")`: compile, and at run time dispatch to GDBLE's zero-argument methods (a bare `ClassDB.instantiate("BleDevice")` returned `false` from `call(&"is_connected")`);
- an untyped `d` also compiles, but static typing is the rule.

So `gdble_transport.gd` calls every GDBLE method through `call(&"name", ...)` and connects signals by name (`d.connect(&"connected", cb)`). `d.connected.connect(cb)` also compiles on a `RefCounted`, but only as an unsafe dynamic access.


## Removed files (SHA-256 from the release)

| File | Bytes | SHA-256 | Why |
| --- | --- | --- | --- |
| `libgdble.macos.arm64.dylib` | 4,242,896 | `2c486ca7e7b22d02f89bac155c107425d2c5b163bbd76e3e3209099bd30c01e9` | macOS is not a target; 4.2 MB |
| `libgdble.macos.x86_64.dylib` | 4,368,368 | `87a1b9f6cb7ff470d0bc7ae8bfe00c8eea290aedb034d64539cb95b8340331b1` | macOS is not a target; 4.4 MB |
| `android/gdble-release.aar` | 2,949,593 | `4835b6ccaf8807cc5d72053424f0eb68ba5eeebb381dbbb983106f1b9b3b0976` | Android is not a target; 2.9 MB |
| `android/btleplug-release.aar` | 37,829 | `81274641a835c9980b3169c826ddea11ae92e60a4d8c27a762e1df68e6d74480` | Android only |
| `gdble.gdap` | 175 | `72c3afdc7b0a3a1fe3f01b70e6cb000d41290f569092c0e10a82823fb6f1c371` | Android plugin config |
| `permission_startup.gd` | 2,705 | `a8e8e6d320b3814da0998abe3c69996c39b85bc9d9e2bdf45005e07ff4cf1105` | Android permission helper (untyped GDScript) |
| `SHA256SUMS` | 964 | (manifest, reproduced below) | It lists the removed files and the unmodified `.gdextension`, so it would no longer verify |
| Archive root: `README.md`, `docs/` except `API_CONTRACT.md` | | | Chinese README duplicate, build and release notes |

Upstream `addons/gdble/SHA256SUMS`, verbatim:

```
390220aa8e078bf3304eb4312dd1f473b6a092f1b71b7c4bad80296547610cef  BUILD_INFO.json
496415eeccc29d5bcd0f2d8dc9436ff4b0c08c37241606a63929a089802320f1  LICENSE
81274641a835c9980b3169c826ddea11ae92e60a4d8c27a762e1df68e6d74480  android/btleplug-release.aar
4835b6ccaf8807cc5d72053424f0eb68ba5eeebb381dbbb983106f1b9b3b0976  android/gdble-release.aar
72c3afdc7b0a3a1fe3f01b70e6cb000d41290f569092c0e10a82823fb6f1c371  gdble.gdap
fd7c86a346f2b85ccf3cf0b83bc2eee4f804453de2d870e67a84068099ac2a83  gdble.gdextension
ba36ffb492fd4fcce82bb177005fcfc0fd5268bf89047e120581dfa42948bea2  libgdble.linux.x86_64.so
2c486ca7e7b22d02f89bac155c107425d2c5b163bbd76e3e3209099bd30c01e9  libgdble.macos.arm64.dylib
87a1b9f6cb7ff470d0bc7ae8bfe00c8eea290aedb034d64539cb95b8340331b1  libgdble.macos.x86_64.dylib
e49a840864255b9ed37cf43a3136d63a662cafa241815a3cf8045fa641f3c97d  libgdble.windows.x86_64.dll
a8e8e6d320b3814da0998abe3c69996c39b85bc9d9e2bdf45005e07ff4cf1105  permission_startup.gd
```

## Local modifications

One file is edited, `gdble.gdextension`, and one file is added, `gdble.gdextension.uid` (written by Godot's first import, see "Kept files"). The edit:

```diff
 [configuration]
 entry_symbol = "gdext_rust_init"
 compatibility_minimum = "4.2"
-reloadable = true
-android_aar_plugin = true
+reloadable = false

 [libraries]
 linux.debug.x86_64 =     "res://addons/gdble/libgdble.linux.x86_64.so"
 linux.release.x86_64 =   "res://addons/gdble/libgdble.linux.x86_64.so"
 windows.debug.x86_64 =   "res://addons/gdble/libgdble.windows.x86_64.dll"
 windows.release.x86_64 = "res://addons/gdble/libgdble.windows.x86_64.dll"
-macos.debug =            "res://addons/gdble/libgdble.macos.x86_64.dylib"
-macos.release =          "res://addons/gdble/libgdble.macos.x86_64.dylib"
-macos.debug.arm64 =      "res://addons/gdble/libgdble.macos.arm64.dylib"
-macos.release.arm64 =    "res://addons/gdble/libgdble.macos.arm64.dylib"
-android.debug.arm64 =     "res://addons/gdble/libgdble.so"
-android.release.arm64 =   "res://addons/gdble/libgdble.so"
-android.debug.x86_64 =    "res://addons/gdble/libgdble.so"
-android.release.x86_64 =  "res://addons/gdble/libgdble.so"
```

- `reloadable = false`: BRIEF 4.2. A hot-reloaded BLE extension would drop the trainer session mid-ride.
- The macOS and Android entries pointed at files that are no longer vendored, so they are removed with them. Windows x86_64 (the target) and Linux x86_64 (CI) remain.

## API notes for `gdble_transport.gd`

From `addons/gdble/docs/README_EN.md` and `API_CONTRACT.md`; BRIEF 4.2 still decides what the transport uses.

- Every 0.5.x class name, method parameter and signal BRIEF 4.2 lists is still present (verified in ClassDB, see above).
- Call `disconnect` and `is_connected` on a device only as `call(&"disconnect")` and `call(&"is_connected")`; the direct forms don't compile on a `RefCounted` (see "Name clash" above).
- Methods that returned `void` in 0.5.x now return an `int` operation id, which may be ignored.
- `connect_device(addr)` is a factory alias for `get_or_create_device(addr)`; it does not connect. Call `connect_async()` on the returned device. It returns `null` for an invalid address or before the adapter is initialized.
- Connect signals before calling a method: invalid arguments and queue rejections emit their failure synchronously, before the call returns.
- No automatic reconnect. After an adapter power-off (`ADAPTER_UNAVAILABLE`), call `initialize()` again. After a notification-buffer overflow (`EVENT_OVERFLOW`) or `SERVICES_CHANGED`, discover and subscribe again.
- UUIDs in events are canonical lower case.
- Subscribing to the same characteristic UUID under two services fails with `AMBIGUOUS_CHARACTERISTIC`.
- The Manager drains at most 256 events per frame.

## Updating

Download the new release asset, check its SHA-256 against GitHub's published digest and its `SHA256SUMS`, copy the Windows and Linux x86_64 libraries, `BUILD_INFO.json`, `LICENSE` and the two docs, reapply the `.gdextension` changes above, keep `gdble.gdextension.uid`, run the first headless import on a fresh `.godot` cache (BRIEF 4.2), run `tests/ble/test_gdble_surface.gd`, compare the ClassDB surface with the tables above, and update this file.
