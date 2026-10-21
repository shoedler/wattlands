# Trainer stack

How Wattlands talks to a Wahoo KICKR CORE over Bluetooth LE FTMS, and how the safety governor shapes every command. For developers. "BRIEF x.y" is a section of `docs/BRIEF.md`; the design rationale is in `docs/decisions/trainer-core.md`, `trainer-control.md`, `ble.md` and `platform.md`. Every constant below is quoted from the code on `main`.

**Hardware status:** none of this has run against a real trainer. Every automated run had the hardware lock on and used MockTrainer or a fake KICKR transport. See [section 8](#8-never-tested-on-hardware) and `docs/HARDWARE_TEST_PLAN.md`.

## 1. Layers (BRIEF 4.1)

```
BleTransport (contract)        GdbleTransport | BridgeTransport          trainer/ble/
  FtmsClient                   discovery, subscriptions, CP queue, parsing  trainer/ftms_client.gd
    TrainerDevice (contract)   FtmsTrainer | MockTrainer                  trainer/
      TrainerController        ERG/SIM/RESISTANCE/OFF, slew, ramps, coalescing  trainer/control/
        SafetyGovernor         every BRIEF 4.6 rule; the only holder of the controller  trainer/control/
          LocalRider           one per local rider and per bot; feeds samples, ticks  core/local_rider.gd
            GameHost           plans, phases, DirectiveRouter                sdk/
```

| Class | File | Owner | Role |
| --- | --- | --- | --- |
| `BleTransport` | `contracts/ble_transport.gd` | lead | Scan, connect, discover, read, write, subscribe; UUID helpers (`expand_uuid`, `same_uuid`, case-insensitive after expanding 16-bit UUIDs) |
| `GdbleTransport` | `trainer/ble/gdble_transport.gd` | ble | GDBLE 0.6.0 GDExtension; the only file that touches GDBLE |
| `BridgeTransport` | `trainer/ble/bridge_transport.gd` | ble | WebSocket client to `tools/trainer_bridge` on `ws://127.0.0.1:8765` |
| `FtmsConnectionManager` | `trainer/ble/connection_manager.gd` | ble | Backend choice, scan, connect, reconnect with backoff, last device |
| `FtmsCodec` | `trainer/ftms_codec.gd` | trainer-core | Pure static byte codec; golden vectors in `tests/vectors/ftms.json` |
| `FtmsClient` | `trainer/ftms_client.gd` | trainer-core | The BRIEF 4.4 flow, CP queue, Indoor Bike Data reassembly, CPS fallback, hardware lock |
| `FtmsTrainer` | `trainer/ftms_trainer.gd` | trainer-core | `TrainerDevice` over `FtmsClient`; the only caller of `write_control()` |
| `MockTrainer` | `trainer/mock_trainer.gd` | trainer-core | Simulated trainer plus rider (section 5) |
| `TrainerController` | `trainer/control/trainer_controller.gd` | trainer-control | Slew, ramped switches, one write per 0.5 s slot; the only caller of the device setters |
| `SafetyGovernor` | `trainer/control/safety_governor.gd` | trainer-control | BRIEF 4.6 (section 6) |
| `GovernorClamps`, `VirtualGears`, `CadenceEstimator` | `trainer/control/` | trainer-control | Floor/ceiling math, gears, cadence from speed |
| `LocalRider` | `core/local_rider.gd` | platform | Composes device, cadence estimator, gestures, governor, W′, speed model, recorder, telemetry |
| `WlTrainerService` | `core/trainer_service.gd` | platform | Autoload `TrainerService`: the app's device (FTMS or `--mock-trainer`) and its rider |

**Data up.** The device emits `TrainerSample {t, power_w, cadence_rpm, speed_kmh, distance_m, flags}`. Flags: `HAS_POWER` 1, `HAS_CADENCE` 2, `HAS_SPEED` 4, `CADENCE_ESTIMATED` 8, `POWER_FROM_CPS` 16, `HAS_DISTANCE` 32; an absent field is −1.

The LocalRider queues samples and processes them in its next tick, stamped with its own platform time: `CadenceEstimator.process()`, then `GestureRecognizer.on_sample()` (ERG mode from the governor), then `SafetyGovernor.on_sample()`. A sample older than 3 s counts as gone (0 W, no cadence or speed).

**Commands down.** The GameHost hands plans, phases and directives to `LocalRider` → `SafetyGovernor`. Each `governor.tick(dt)` computes the governed ERG target or SIM state and calls `TrainerController.command_erg/command_sim/command_off`. The controller decides when to write through `TrainerDevice.set_target_power/set_simulation/set_resistance/request_stop`. `FtmsTrainer` turns those calls into control-point payloads and passes them to `FtmsClient.write_control()`.

**Structure is enforced** (BRIEF 4.6.11). `tests/arch/test_no_bypass.gd` lexes every `.gd` under `res://addons/wattlands` and `res://src`, comments and strings stripped, and flags any reference to a guarded name outside its allowlist. That includes string literals used for dynamic calls.

| Guarded name | Allowed in |
| --- | --- |
| `set_target_power`, `set_simulation`, `set_resistance`, `request_stop` | `trainer_controller.gd` |
| `write_control` | `ftms_trainer.gd` |
| `write_characteristic` | `ftms_client.gd`, `gdble_transport.gd`, `bridge_transport.gd` |

**Time.** Everything advances in fixed 0.05 s steps (`Wl.SIM_DT`) on platform time. The governor also keeps game time, which stops while paused; phase ramps and directive expiry use it. Nothing in the stack reads the wall clock except the real-time drivers (`SimClock.advance` in `_process`) and socket timers. All system nodes run with `PROCESS_MODE_ALWAYS`; pause never uses `SceneTree.paused`.

## 2. FTMS as implemented (BRIEF 4.3)

Little-endian. 16-bit UUIDs sit on the base `0000xxxx-0000-1000-8000-00805f9b34fb` and are compared case-insensitively after expansion.

### 2.1 Services and characteristics

| UUID | Name | Use |
| --- | --- | --- |
| `1826` | Fitness Machine | Required |
| `2ACC` | Feature (read) | Required. uint32 machine features, uint32 target-setting features |
| `2AD2` | Indoor Bike Data (notify) | Telemetry |
| `2AD6` | Supported Resistance Level Range (read) | Optional; default 0–100, step 0.1 |
| `2AD8` | Supported Power Range (read) | Optional; default 0–1800 W, step 1. Its max feeds the governor's ceiling |
| `2AD9` | Control Point (write with response + indicate) | Subscribed last, so indications are on before Request Control |
| `2ADA` | Machine Status (notify) | 0xFF = control permission lost |
| `1818` / `2A63` | Cycling Power Measurement | Fallback power when machine bit 14 is missing |
| `180A` | Device Information | Optional, for diagnostics (manufacturer `2A29`, model `2A24`, …) |

Feature bits used:

- machine: 1 cadence, 2 total distance, 7 resistance level, 14 power measurement;
- target: 2 resistance, 3 power (ERG), 13 indoor bike simulation, 14 wheel circumference, 15 spin down, 16 targeted cadence.

### 2.2 Indoor Bike Data (`2AD2`)

uint16 flags, then each flagged field in bit order:

| Bit | Field | Encoding |
| --- | --- | --- |
| 0 | More Data, **inverted**: 0 means instantaneous speed follows | uint16, 0.01 km/h |
| 1 | average speed | uint16, 0.01 km/h |
| 2 | instantaneous cadence | uint16, 0.5 rpm |
| 3 | average cadence | uint16, 0.5 rpm |
| 4 | total distance | uint24, m |
| 5 | resistance level | sint16 |
| 6 | instantaneous power | sint16, W (FtmsTrainer turns a negative reading into 0 W) |
| 7 | average power | sint16, W |
| 8 | energy | uint16 kcal, uint16 kcal/h, uint8 kcal/min |
| 9 | heart rate | uint8, bpm |
| 10 | metabolic equivalent | uint8, 0.1 |
| 11 | elapsed time | uint16, s |
| 12 | remaining time | uint16, s |

Every field is bounds-checked; a short or malformed part logs `push_error` and returns `{}`. Trailing bytes and reserved bits 13–15 are ignored.

`BikeDataAssembler` merges parts until one arrives with More Data clear. A part that repeats a pending field flushes the pending record as incomplete, and so does reaching 8 parts. So a device that sets More Data on every notification still yields a record per notification, one notification late. Example: `4400ea0bb400c800` = 30.5 km/h, 90 rpm, 200 W.

### 2.3 Control point (`2AD9`)

Encoders round half away from zero and clamp to the field's range. Safety limits live in the governor, not the codec.

| Op | Name | Parameters | Example |
| --- | --- | --- | --- |
| `0x00` | Request Control | none | `00` |
| `0x01` | Reset | none | `01` |
| `0x04` | Set Target Resistance Level | uint8 0.1 (default) or sint16 0.1 (`FtmsTrainer.resistance_encoding`) | 12.5 → `047d` |
| `0x05` | Set Target Power (ERG) | sint16 W, clamped 0…32767 | 200 W → `05c800` |
| `0x07` | Start or Resume | none | `07` |
| `0x08` | Stop or Pause | uint8: 1 stop, 2 pause | Stop → `0801` |
| `0x11` | Set Indoor Bike Simulation (SIM) | sint16 wind 0.001 m/s, sint16 grade 0.01 %, uint8 crr 0.0001, uint8 cw 0.01 kg/m | flat, crr 0.004, cw 0.51 → `11000000002833`; grade 5.5 % → `11000026022833` |

- **Response indication**: `0x80`, the request op code, then a result: `0x01` success, `0x02` not supported, `0x03` invalid parameter, `0x04` operation failed, `0x05` control not permitted.
- **Machine Status codes parsed**: `0x01` reset, `0x02` stopped by user, `0x03` safety key, `0x04` started by user, `0x07` target resistance changed, `0x08` target power changed, `0x12` simulation changed, `0x14` spin down, `0x15` target cadence changed, `0xFF` control permission lost.

### 2.4 Connection flow (BRIEF 4.4)

`FtmsConnectionManager.start(true)` picks a backend: GDBLE if its library is loaded and the adapter initializes, else the bridge if `ws://127.0.0.1:8765` answers, else none. A backend that doesn't answer `initialize()` within 10 s counts as unavailable. "No adapter" is a `push_warning` and `STATUS_DISCONNECTED`, never an error.

1. **Scan.** Match a device that advertises `1826` or whose name contains "kickr" (any case). Auto-connect connects the remembered device (`Paths.last_device_path()`, `{address, name}`) the moment it is seen and rescans in 30 s windows until then; manual scans last 10 s. Without a remembered device, nothing auto-connects: the rider picks a trainer in Settings → Trainer.
2. **Connect.** `transport.connect_device(address)`, with a 30 s timeout.
3. **`FtmsClient.begin()`** runs states `discovering` → `reading` → `subscribing` → `requesting_control` → `setting_sim` → `ready`:
   - discover services (10 s timeout, then `failed`);
   - read `2ACC` (required), `2AD8` and `2AD6` (optional), and Device Information (optional), one at a time, each with a 2 s timeout and two retries;
   - subscribe `2AD2`, `2ADA`, `2A63` (CPS fallback only), then `2AD9` last; btleplug writes the CCCD as Indicate where supported;
   - wait 0.25 s (`SUBSCRIBE_SETTLE_S`; the transport has no subscribe acknowledgement);
   - Request Control. Success goes on; `0x05` means control lost; any other result means `failed`;
   - SIM flat (`11 0000 0000 28 33`). A refusal only logs a warning;
   - `client_ready`.
4. The whole setup must finish within 30 s (`SETUP_TIMEOUT_S`). Then the manager emits `trainer_ready(FtmsTrainer)` and saves the device as the last one.

**Under the hardware lock** the flow stops after subscribing: state `read_only`, a "hardware control locked" warning, then `client_ready`. Telemetry flows, `is_ready()` stays false and no write goes out.

### 2.5 Control-point queue (BRIEF 4.4, 4.5)

- **One write in flight.** Responses are matched by request op code; an unexpected response logs a warning and is ignored.
- **Timeouts.** 2 s per attempt, two retries (three sends, 6 s). Still unanswered: `failed("control point … unanswered after 3 attempts")` and the queue is dropped (the link is presumed dead).
- **Coalescing** (FtmsClient, the second layer after the controller's 0.5 s slots). A new Set Target Resistance/Power/Simulation write replaces the queue's last unsent write only when that write and the one before it (queued, or in flight) have the same op code; otherwise it is appended. Order is never changed, and the first write of each mode is never dropped. Request Control, Reset, Start and Stop are never coalesced.
- **Writes while not `ready`** are dropped with a warning ("not in control").

### 2.6 Reconnect and control loss

- **Backoff**: `backoff_delay(n)` = 1, 2, 4, 8, then 15 s for every later attempt. It applies to a lost link, a failed connect, a connect over 30 s and a setup that fails or takes over 30 s, and resets once the trainer is ready.
- **Reconnect**: the same `FtmsClient` and `FtmsTrainer` objects are reused. `begin()` runs again (rediscover, resubscribe, indications, Request Control, SIM flat), then `trainer_ready(device)` and `reconnected(device)` are emitted.
- **GATT reset**: a GDBLE `EVENT_OVERFLOW` or `SERVICES_CHANGED` on a ready trainer runs `begin()` without dropping the link.
- **Control lost** (Request Control `0x05` or Machine Status `0xFF` while in control): status `STATUS_CONTROL_LOST` with "Another app may hold control of the trainer (Zwift, the Wahoo app). Close it, then retry." There is **no automatic retry**, because grabbing control back would fight the other app. `retry_control()` runs `begin()` when the rider asks.
- **Under the hardware lock** a setup failure keeps the read-only link and stops instead of retrying.

## 3. Backends

### 3.1 GDBLE (BRIEF 4.2; `docs/deps.d/gdble.md`)

- **Version.** v0.6.0, tag commit `ecae959` (contains `13c49c7`), vendored in `addons/gdble/` with SHA-256 sums. Windows and Linux x86_64 libraries only; `reloadable = false`. The first headless import on a fresh `.godot` cache exits 0 on Godot 4.7.2.
- **Surface.** Verified with `ClassDB` on 2026-10-21 and checked by `tests/ble/test_gdble_surface.gd` whenever the class exists. Every 0.5.x method and signal BRIEF 4.2 lists exists with the same arity. Action methods now return an int operation id, which is ignored. `connect_device(addr)` is a factory: it returns a `BleDevice` and does **not** connect; `connect_async()` does.
- **No static types.** GDBLE classes are created with `ClassDB.instantiate("BluetoothManager")` and held as `Node`; devices are held as `RefCounted`. Every method is called by name with `call(&"…")` and every signal is connected by name. Only `gdble_transport.gd` touches GDBLE.
- **The `disconnect` quirk.** `BleDevice.disconnect()` and `is_connected()` take no arguments, but on a `RefCounted` the analyzer checks them against `Object.disconnect(signal, callable)` and `Object.is_connected(...)`. That is a parse error ("Too few arguments"). Always write `device.call(&"disconnect")` and `device.call(&"is_connected")`. The test double overrides `disconnect()` under `@warning_ignore("native_method_override")`.
- **Event handling.**
  - Signals are connected before any request (GDBLE rejects synchronously).
  - Device and manager connect/disconnect signals are both used and deduplicated, so each link change is reported once (reason `local` after `disconnect_device()`, else `remote`).
  - Every `start_scan()` replays GDBLE's discovery cache.
  - An adapter power-off reports a live link down first (`adapter lost`), then `adapter_ready(false)`.
- **No auto-reconnect** in GDBLE itself; the manager does it. `adapter_initialized(false, …)` means no adapter (about 10 ms without D-Bus).
- **Never exercised.** Nothing in the build called `initialize()` or a scan on a real adapter.

### 3.2 Bridge and probe (BRIEF 4.2, P1; `tools/trainer_bridge/`)

- **Bridge.** Python 3.12+, bleak and websockets. A thin GATT proxy on `ws://127.0.0.1:8765`, loopback only and one client at a time. Requests run in order (scans in the background), and the bridge releases the trainer when the app disconnects.
- **Protocol.** JSON text frames. Requests `{id, op, …}`, responses `{id, ok, result, error}`, events `{event, …}`; payloads are lower-case hex, UUIDs expanded and lower case.
  - Ops: `hello`, `init`, `scan`, `stop_scan`, `connect`, `disconnect`, `discover`, `read`, `write`, `subscribe`.
  - Events: `device`, `scan_stopped`, `notify`, `disconnected`, `adapter`.
  - The full table is in `tools/trainer_bridge/README.md`.
- **`BridgeTransport`** accepts loopback URLs only. Timeouts: open 3 s, request 10 s, connect 25 s. A connect that times out also sends `disconnect`.
- **Probe.** `python -m trainer_bridge probe [--seconds 30] [--address …] [--scan-seconds 10]`.
  - Read-only: scans, reads Device Information, Feature and both ranges, then prints parsed Indoor Bike Data and Machine Status for 30 s.
  - `--allow-control` adds Request Control and SIM flat only, after the typed phrase `I AM ON THE TRAINER`. It is refused under the hardware lock.
  - Exit codes: 0 done, 2 no adapter or trainer, 3 refused, 4 connect failed.
- **Exe.** `trainer_bridge.spec` builds a PyInstaller one-file exe.
- **Python status.** bleak could not be installed here (Python 3.15.0 only, and no `winrt-*` wheels for it), so the bleak backend, the probe on hardware and the PyInstaller exe with bleak are untested. websockets 17.3 and PyInstaller 6.22.3 worked; the proxy, protocol and probe are tested against a fake backend.
- **Not launched by the app.** A user starts `trainer_bridge serve`, and the manager finds it on its next `start()`.

## 4. The hardware lock (BRIEF 1, 4.6.10)

`WATTLANDS_NO_HW_CONTROL=1` (`Locks.hw_locked()`):

- **Who sets it**: `tools/env.sh`, `tools/env.ps1`, both Godot wrappers, `tools/run_tests` and the e2e, screenshot and game-sim scripts. Only `--allow-hw`, passed by a human following `docs/HARDWARE_TEST_PLAN.md`, drops it. The shipped game never sets it.
- **`FtmsClient`** refuses Request Control and every control-point write and logs "hardware control locked". The lock is checked when a write is requested and again right before the transport write. Scan, read and subscribe still work (`read_only` state).
- **Defence in depth**:
  - `GdbleTransport` and `BridgeTransport` refuse every write under the lock (`operation_failed("write", …)`);
  - the Python bridge refuses `write` when its own environment has the lock;
  - `probe --allow-control` refuses to start.
- **Tests never lift it.** Flow tests use `tests/trainer/unlocked_ftms_client.gd`, a test-only subclass that overrides `_is_hw_locked()` for one instance and talks only to `fake_kickr_transport.gd`.

## 5. MockTrainer (BRIEF 4.2)

`MockTrainer.from_spec(spec, ftp_w, options)` builds a simulated trainer and rider. It serves tests, `GameSimRunner`, bots (`erg:compliance=1.0`) and `--mock-trainer=<profile>` (bare: `erg`).

**Spec grammar.** Components are `name:key=value,…` joined with `+`; names and keys are case-insensitive, values are numbers. A component may repeat, each instance independent. An unknown name or key, a missing required key or a bad value logs `push_error` and falls back to `erg`.

### 5.1 Profiles

| Profile | Keys (default) | Behaviour |
| --- | --- | --- |
| `erg` | `compliance` 0–1 (1.0) | ERG: compliance × the commanded target (≤ `max_power_w`). Otherwise compliance × the centre of the published power band, else 90 % FTP. A spec without `erg` uses the follower at 1.0 |
| `zero` | none | 0 W, 0 rpm |
| `const` | `w` (required), `rpm` | Constant power; cadence `rpm` or the preferred cadence |
| `ramp` | `from_w`, `to_w`, `over_s` (required), `rpm` | Linear power ramp over profile time |
| `intervals` | `on_w`, `off_w` (required), `on_s` 60, `off_s` 60, `rpm` | Square wave, starting "on" at t = 0 |
| `noise` | `sd_w` 5, `sd_rpm` 2 | Seeded Gaussian noise on each sample's power and cadence while pedaling |
| `band` | `offset_rpm` 0 | Cadence follows the published cadence band's centre + offset: first-order lag τ 2 s plus Ornstein-Uhlenbeck noise (sd 0.6 rpm, τ 4 s) clamped to ±1.5 rpm. No band: the profile's rpm or the preferred cadence. ±(half the band width + n) holds the rider n rpm outside the band |
| `cadence_drop` | `rpm` (required); a start: `at_s`, or `at_phase` [+ `after_s`], or `at_target_pct` [+ `at_phase`, `after_s`]; `for_s` (rest of run) | Cadence becomes `rpm` (the lowest active drop wins; `rpm=0` means the rider stops at 0 W, otherwise power stays with the follower). `at_target_pct` waits until the commanded ERG target (after the unverified factor) is ≥ n % FTP. Each instance fires once; leaving `at_phase` before the drop starts re-arms it |
| `surge` | `every_s` 60, `for_s` 2, `lift` 0.2, `sim_pct` | Every `every_s` (first at `every_s`), cadence and reported speed × (1 + `lift`), extended until at least two notifications carried it, so the ERG surge gesture fires every time. `sim_pct=n` rides n % FTP whenever the trainer is in SIM |

**Precedence.**

- Power: the first scripted profile (`zero`, `const`, `ramp`, `intervals`) > `surge`'s `sim_pct` in SIM > the `erg` follower.
- Cadence: an active `cadence_drop` > `surge`'s lift (multiplies) > `band` > the profile's `rpm` > the preferred cadence.

Examples: `erg:compliance=0.85+band`; `erg+band:offset_rpm=-18`; `erg+cadence_drop:rpm=30,at_phase=4,after_s=20,for_s=30`; `erg+cadence_drop:rpm=30,at_phase=1,at_target_pct=60,for_s=30`; `erg+surge:every_s=60,for_s=2,lift=0.2,sim_pct=130`; `const:w=150,rpm=85+noise:sd_w=8`; `intervals:on_w=300,off_w=120,on_s=30,off_s=90`.

### 5.2 Options and rider model

- **Options**: `cp_w` (FTP), `wprime_j` (20000), `preferred_cadence_rpm` (90), `weight_kg` (75), `max_power_w` (1800), `seed`, `dropouts` (bool, or a chance per notification; 0.03 when true), `keyboard` (W/S ±10 W, A/D −/+5 rpm; nothing in the app sets it).
- **ERG follower**: second order (ω = 0.9 rad/s, damping 0.75). That is 63 % of a step after about 2 s (`ERG_TAU_S`), about 2.5 % overshoot, and within 2 % after about 6 s.
- **Fatigue**: a Skiba W′ balance on the mock's own power. When W′ hits 0 the follower gives only 0.95 × CP until 10 % of W′ is back, so time to failure is W′ / (P − CP): 150 % FTP fails after about 160 s at the defaults, and sub-CP targets never fail. Scripted profiles ignore fatigue.
- **Sprints**: outside ERG at ≥ 120 % FTP the follower's cadence rises 10 % (not for `band` riders). The reported cadence then lags its fall for 5 s (τ 1.5 s), like a trainer's estimate.
- **Speed**:
  - ERG, RESISTANCE and OFF: flywheel speed = cadence × 0.4 km/h per rpm.
  - SIM: a `SpeedModel` (weight + 8 kg) on the commanded grade and wind, seeded from the flywheel speed.
- **Pedaling**: the rider pedals while its goal power is above 0 and stops at once (0 W, 0 rpm) at 0.

### 5.3 Timing

- Notifications come every 0.9–1.1 s (seeded jitter), rounded like FTMS data (1 W, 0.5 rpm, 0.01 km/h).
- Dropouts are seeded gaps of 1.5–4 s. They never chain and never touch a surge or the 10 s before one.
- Control responses arrive on the next tick with `response_result` (success); after `simulate_control_lost()` every response is `0x05`.
- Profile time (`at_s`, surges, ramp, intervals) starts at creation. `restart_profile()` restarts it for a mock that rode through menus.
- `LocalRider.setup()` clears the mock's bands and sets its phase to −1.
- Simulated riders pedal from t = 0, so their warm-up starts at once; a `zero` rider never starts it.
- Everything advances only in `tick(dt)`, and every random stream derives from `seed`.

## 6. The safety governor (BRIEF 4.6)

One `SafetyGovernor` per rider (local riders, bots, every simulated rider). Applied ERG targets are whole watts: the governed target is rounded down, the floor rounded up, and every cap and counter compares the whole-watt value.

### 6.1 Each tick, in order

1. Advance platform time, and game time unless paused.
2. Process queued samples: 3 s power, speed, `not_pedaling`, the rescue windows, the warm-up start.
3. Update coasting, warm-up and channel expiry, and apply course grades at most every 0.5 s.
4. Decide the desired mode: SAFE (panic), else SIM (a SIM phase or a SIM block), else ERG (an ERG phase), else OFF (no phase).
5. Compute the governed ERG target or the stacked SIM state.
6. Update rescue.
7. Command the controller, which slews and writes.
8. Accrue the duration limits on the controller's applied target.
9. Publish `status()`.

ERG precedence (4.6.12):

```
pct = directive ERG channel, else the plan's target (with its ramp) at phase-elapsed game time
w   = pct × FTP × 0.85 (unverified)                  [unverified]
    → min(ceiling)                                   [ceiling]
    → min(105 %) if the phase is longer than 300 s   [long_phase]
    → min(120 %) if latched, min(105 %) if latched   [limit_120] [limit_105]
    ── rescue arms on this value (≥ floor(60 % FTP))
    → min(65 %) during warm-up                       [warmup]
    → min(50 %) in rescue hold; 50 % → w over 10 s in the ramp-back   [rescue]
    → floor if coasting, floor if paused             [coasting] [paused]
    → max(floor)                                     [floor]
controller: slew increases at 30 W/s, ramped entries [slew] [switch_ramp]
panic overrides everything                           [panic]
```

### 6.2 Rule by rule

| Rule | Implementation and constants | `clamped_by` / refusal |
| --- | --- | --- |
| 4.6.1 Floor | max(30 % FTP, 50 W), rounded up; wins over every cap and over rescue | `floor` |
| 4.6.1 Ceiling | min(150 % FTP, 1000 W, trainer max), rounded down. Trainer max is the device's `power_range().max_w`, else 1800 | `ceiling` |
| 4.6.1 Long phase | A phase whose worst-case length (`duration_s`, or `max_s` if open-ended) is > 300 s caps at floor(105 % FTP), directives included | `long_phase` |
| 4.6.1 Duration limits | Count ticks in ERG with the applied (slewed) whole-watt target > floor(105 %) (limit 300 s) and > floor(120 %) (limit 60 s). Reaching a limit latches that band's cap from the next tick. A run of ≥ 120 s (inclusive) in ERG at ≤ 90 % FTP resets both counters and latches. Any tick not in ERG (SIM, panic, a switch in progress) restarts the run and adds nothing. `s_left_105`/`s_left_120` go out in telemetry | `limit_105`, `limit_120` |
| 4.6.1 Unverified FTP | Target × 0.85 while `ftp_verified` is false | `unverified` |
| 4.6.1 `ramp_test` profile | No unverified factor, long-phase cap, 150 % cap or duration limits; ceiling min(1000 W, trainer max). Floor, slew, warm-up, rescue, coasting and panic stay. A rescue trigger ends the test (`ramp_test_ended("rescue")`) and 50 % stands until the next `set_plan()` | |
| 4.6.2 Slew | Controller: increases ≤ 30 W/s, decreases at once. `applied_target_w` is the slewed target, up to one write slot ahead of the trainer | `slew` |
| 4.6.3 Rescue | **Armed**: in ERG, not paused, no panic, with the whole-watt target after the factor and the 4.6.1 caps ≥ floor(60 % FTP). **Triggers**: cadence < 45 rpm for 3 s, or power < 75 % of the target last written to the trainer for 5 s, each held for the whole window while armed. **Hold**: min(target, 50 % FTP) until cadence ≥ 70 rpm for 3 s. **Ramp-back**: linear from 50 % to the current governed value over 10 s, slew still applying. A new trigger during the ramp restarts the hold; a SIM phase ends rescue. Signal `rescue_changed`; `rescue` goes out in telemetry | `rescue` |
| 4.6.4 Coasting | `not_pedaling` = power < 15 W and (no cadence or cadence < 20 rpm), timed from the first sample that meets it. At 3 s: ERG to the floor. At 10 s, while a phase runs: `pause_requested("coasting")` once (solo) or `afk_changed(true)` (multiplayer). A pedaling sample clears both | `coasting` |
| 4.6.5 Panic | `emergency_safe()` writes SIM grade 0, wind 0 at once, bypassing the write slot, and ends any haptic. Desired mode SAFE until `resume()`; the next ERG entry starts at the floor and slews up. A trainer bound during panic gets SIM flat at once | `panic` |
| 4.6.6 SIM stacking | Section 6.4 | `grade_range`, `grade_limit`, `haptic_limit`, `haptic_intensity`, `factor_bounds` |
| 4.6.7 Network | Hosts send directives; each client's own governor validates plans (`PlanValidator.validate` on every `plan` message) and clamps directives, then acks `{id, kind, applied, clamped_by, refused, reason}` in `Telemetry.acks` | |
| 4.6.8 Warm-up | 300 s of platform time from the first pedaling sample (pending, with 300 s remaining, before it). Resets after 1200 s with no pedaling sample; survives a reconnect. ERG ≤ floor(65 %); SIM total grade clamped to −2…+3 %; haptics dropped and a running haptic ended. `skip_warmup` turns it off | `warmup`, `haptic_in_warmup` |
| 4.6.9 Exit | `shutdown()` → controller writes SIM flat then Stop (`0x08 0x01`) back to back, at once. Run by `LocalRider.shutdown()`, `WlTrainerService.shutdown_all()` (quit, window close, `NOTIFICATION_CRASH`, tree exit; walks `LocalRider.live_riders()`) and on switching trainers. `App.quit()` waits 0.5 s of real time when a real trainer is connected | |
| 4.6.10 Tests | MockTrainer only; the hardware lock (section 4) | |
| 4.6.11 Structure | Section 1 and `test_no_bypass.gd` | |
| 4.6.12 Precedence | Section 6.1 | |
| 4.1 Pause | `set_game_paused(true)`: ERG floor or SIM flat (haptic removed); telemetry, rescue, coasting and panic keep working | `paused` |
| 4.5 Switch | While a ramped ERG ↔ SIM switch runs, or the ERG target climbs from a switch entry | `switch_ramp` |

### 6.3 Directive channels and expiry (BRIEF 3.6)

`apply_directive(EffortDirective)` returns, and emits through `directive_applied`, a record:

```
{id, kind ("request" | "course_grade"), requested, applied, clamped_by, refused, reason,
 dropped: [{channel, reason}], t, game_t, phase_index}
```

- **Channels**: ERG target (`target_pct`, `target_w` or `target_wkg`, one per request, converted to %FTP first), SIM block (`mode: SIM` in an ERG phase), `mode_grade`, haptic (`haptic`, `haptic_wind`), factors (`crr`, `cw`); the course grade is a separate call. A request changes only the channels it sets; a later request on a channel replaces it and its expiry.
- **Expiry**:
  - `duration_s` counts game time, snapped to 0.05 s; 0 means until the phase ends.
  - On expiry the ERG target goes back to the plan, a SIM block back to ERG, and mode grade and factors to none.
  - `start_phase()` and `set_plan()` clear every channel.
- **SIM block** (ERG phase, `mode: SIM`):
  - needs 10 s ≤ `duration_s` ≤ 30 s, no rescue, coasting, AFK, pause or panic, and ≥ 30 s of platform time since the governor's last ERG ↔ SIM change (plan phases and panic count);
  - `mode: SIM` while a block runs confirms it without extending it;
  - `mode: ERG` ends it early;
  - its end takes the mode grade and the haptic with it.
- **Haptic**:
  - grade and wind × intensity;
  - duration min(`duration_s`, 8 s) of game time, with a hard 8 s platform cap so a pause can't stretch it (0 or > 8 s → 8 s, `haptic_limit`);
  - refused while one is active or within 15 s (platform) of the end of the last applied one;
  - opting out ends a running haptic.
- **Factors**: each clamped to [0.5, 1.0] (they only lower resistance); a request replaces the whole pair (an unset factor goes back to 1.0).
- **Course grade**:
  - `set_course_grade()` is accepted only in a `grade_source: game` SIM phase;
  - the applied value moves at most every 0.5 s, to the newest value;
  - `course` phases follow `course_profile` by `set_course_distance()` (the rider's speed-model distance) minus the distance at the phase start, linear between points, holding the end grades.
- **Whole-request refusals**, checked in this order (`push_warning` plus a record): `bad_fields`, `no_phase`, `cooldown`, `erg_in_sim_phase` (`mode: ERG` or an ERG target in a SIM phase), `haptic_in_erg` (a haptic for a rider in ERG without a running block, even inside a block request: never a mode switch), `outside_range_pct`, `sim_block_length`, `sim_block_unsafe`, `switch_spacing`, `mode_grade_outside_sim`.
- **Haptic drops**: `haptics_off`, `haptic_in_warmup` and `haptic_cooldown` drop only the haptic and apply the rest. The request is refused only when nothing else was set.
- **Host side**: the `DirectiveRouter` pre-checks the same rules on game ticks (`PhaseTracker`) and refuses the whole request on the first failure (also `unknown_peer`, `haptics_off`). The host takes back a SIM block that the rider's governor refused.

### 6.4 SIM stacking (BRIEF 4.6.6)

```
scaled = (course grade + mode grade) × difficulty            (difficulty_pct, default 50)
base   = scaled + gear offset(scaled)
base   = clamp(base, max(grade_min, -10), min(grade_max, 16))      [grade_range]   user range −5…+10
hap    = clamp(haptic × intensity, -3, +3)                          [haptic_intensity] [haptic_limit]
wind   = clamp(haptic_wind × intensity, ±w_max)                    [haptic_limit]
total  = clamp(base + hap, -10, +16)                                [grade_limit]
total  = clamp(total, -2, +3) during warm-up                         [warmup]
paused: total 0, wind 0;  panic: SIM flat
crr    = 0.004 × crr factor;  cw = 0.51 × cw factor                 [factor_bounds]
```

The course grade counts only in SIM phases whose `grade_source` isn't `flat`.

The wind bound `w_max` keeps `cw × ((v + w)² − v²)` within the force of +3 % grade on 83 kg, minus what the haptic grade already used; grade and wind share one +3 % budget. It uses the latest reported speed, or 20 m/s when unknown, the conservative case. At 30 km/h with no haptic grade, `w_max` ≈ 2.5 m/s; at the 20 m/s default it is ≈ 1.2 m/s.

A haptic for a rider in ERG is refused, never turned into a mode switch.

### 6.5 Virtual gears and the approximation (BRIEF 4.5; `VirtualGears`)

- **Range.** 24 gears; gear 12 is neutral (offset 0). `shift_up`/`shift_down` move ±1 only while the rider is in SIM (a SIM phase or block); the gear is kept across phases and starts at 12 with every new governor (each session).
- **Tuning.** Each gear is a fixed grade offset, tuned so gear g multiplies the FTMS-model resistance `F = m·g·(crr·cosθ + sinθ) + cw·v²` at a reference of 30 km/h, 83 kg, crr 0.004 and cw 0.51 by 1.07^(g − 12). The offset is the grade change that adds `(1.07^(g−12) − 1) × F_ref`, where `F_ref` is the force at the base grade, or the flat-road force for descents, so gears never vanish downhill.

  Offsets at the reference:

  | Base grade | Gear 1 | Gear 6 | Gear 11 | Gear 13 | Gear 18 | Gear 24 |
  | --- | --- | --- | --- | --- | --- | --- |
  | 0 % | −2.49 | −1.59 | −0.31 | +0.33 | +2.38 | +5.96 |
  | 2 % | −3.54 | −2.25 | −0.44 | +0.47 | +3.39 | +8.51 |
  | 5 % | −5.12 | −3.26 | −0.64 | +0.69 | +4.92 | +12.46 |

  The user's range clamp follows, so gear 24 on a 5 % base stops at +10 %.
- **Approximation.** At 30 km/h every step is exactly 7 % at any base grade ≥ 0. At other constant flywheel speeds the step drifts: 8–17 % at 25 km/h, 4–6 % at 35 km/h, 2–4.5 % at 45 km/h. Low gears at low speed reach zero resistance like any descent. Fixed offsets were chosen over speed-tracking ones because they are deterministic and cost no extra writes.
- **Display.** The HUD gear widget shows the gear whenever the trainer is in SIM.

### 6.6 Cadence estimation (BRIEF 4.5; `CadenceEstimator`)

LocalRider runs every sample through it before gestures and the governor.

- **Present and fresh**: passed through.
- **Learning**: at ≥ 40 rpm and ≥ 5 km/h the km/h-per-rpm ratio is learned as an exponential average (α 0.1). A repeated value while speed moved > 5 % teaches nothing.
- **Absent**: estimated as speed / ratio, with `HAS_CADENCE` and `CADENCE_ESTIMATED` set.
- **Stale**: a reported cadence unchanged for more than `stale_s` (3 s) while speed moved > 15 % is replaced the same way.
- **No ratio or no speed yet**: the sample passes unchanged.
- **Calibration**: `start_calibration(90)` sets the ratio from the mean speed over 10 s at 90 rpm.
- **ERG gestures** use relative flywheel speed and need no calibration.

### 6.7 Mode-switch ramps (BRIEF 4.5; `TrainerController`)

- **ERG → SIM**, each step in its own write slot: (1) ERG at max(floor, min(applied target, 3 s power)), skipped when that isn't below the written target; (2) SIM grade 0, wind 0; (3) the stacked SIM state.
- **SIM → ERG**: (1) SIM grade 0, wind 0, skipped if already flat; (2) ERG at max(floor, min(3 s power, governed target)), so never above the planned or directed target; (3) slew up at 30 W/s.
- **First ERG command.** After connecting (the flow left SIM flat) it uses the same entry. After a panic resume the entry is the floor.
- **3 s power.** The time-weighted mean of the last 3 s of samples, each held until the next. `setup()` clears it, so a rebind enters from the floor.
- **Spacing.** The PlanValidator warns when two plan switches are < 30 s apart (the cool-down included). Directive blocks are held to the 30 s spacing in section 6.3; the two switches bracketing one block are exempt.

### 6.8 Coalescing (BRIEF 4.5)

- **Controller.** At most one write per 0.5 s slot (`MIN_WRITE_INTERVAL_S`), so at most 2 per second. Each write is computed from the newest command when the slot opens, so superseded commands are never written and the newest always is.
- **No-op writes are skipped.** An ERG write happens only when the whole-watt slewed target changes; a SIM write only when the state differs at FTMS resolution (grade 0.01 %, wind 0.001 m/s, crr 0.0001, cw 0.01). During a slew that is one write every 0.5 s, 15 W apart.
- **Panic and shutdown** write at once; the next ordinary write still waits 0.5 s.
- **Second layer.** FtmsClient's tail replacement (section 2.5).
- **Upstream.** The host coalesces `course_grade` to one per 10 game ticks (2 Hz), and `NetSession` holds `course_grade`, `cadence_band` and `power_band` messages to one per kind per peer per 100 ms.

### 6.9 Status and telemetry

`status()` holds:

- mode and targets: `mode` (written), `desired_mode`, `applied_target_w` (slewed, 0 outside ERG), `applied_pct`, `governed_target_w`, `written_target_w`, `planned_pct`, `power_3s_w`;
- SIM state: `applied_grade_pct`, `written_grade_pct`, `course_grade_pct`, `mode_grade_pct`, `base_grade_pct`, `wind_mps`, `crr`, `cw`, `haptic_active`, `haptic_pct`;
- clamps and rider state: `clamped_by`, `rescue`, `rescue_ramp`, `coasting`, `afk`, `paused`, `panic`, `warmup_active`, `warmup_remaining_s`;
- limits: `s_left_105`, `s_left_120`, `latched_105`, `latched_120`;
- phase and profile: `gear`, `phase_index`, `phase_elapsed_s`, `sim_block_active`, `last_switch_t`, `profile`, `test_ended`, `shut_down`, `ftp_w`, `ftp_verified`, `t`, `game_t`.

`LocalRider` copies the relevant fields into `Telemetry` every tick.

## 7. Configuration path

`LocalRider._make_governor_params()` configures each governor: `ftp_w`, `ftp_verified`, `haptics_on` and `haptic_intensity` from the slot; `difficulty_pct`, `grade_min_pct`, `grade_max_pct` and `weight_kg` (for `target_wkg`) from the profile; `skip_warmup` from the options, else the profile; `multiplayer` from the session role; `trainer_max_w` from `device.power_range().max_w`; `profile` `normal`, or `ramp_test` for the FTP test. `crr` and `cw` keep their defaults (0.004, 0.51), and `system_mass_kg` (83, for the wind bound) isn't passed. Out-of-range values are clamped with `push_warning`; a non-positive FTP or an unknown profile is a `push_error` and the old value stays.

## 8. Never tested on hardware

Everything below ran only against MockTrainer, `fake_kickr_transport.gd`, the bridge's fake backend or golden vectors. `docs/HARDWARE_TEST_PLAN.md` (probe, connect, SIM flat, ERG 100 W, slew, rescue, coasting and panic, mode switches, Workout, two-PC multiplayer, disconnect and reconnect, Strava) and `src/games/workout/HARDWARE_TEST.md` cover them.

- **GDBLE.** `initialize()`, scanning, connecting, CCCD writes and notifications on a real Windows adapter; the dedup of device and manager signals; adapter power-off; GATT reset recovery.
- **The bridge.** Its bleak backend, the probe on a real trainer and the PyInstaller exe with bleak.
- **The KICKR itself.** Feature bits, the ranges' real values and Device Information; whether its Indoor Bike Data sets More Data; Request Control and `0x05` with Zwift or the Wahoo app holding control; Machine Status `0xFF`; response latency against the 2 s timeout and the 0.25 s settle delay.
- **ERG behaviour.** Settling and overshoot against the mock's τ ≈ 2 s model; the ramped switches against the documented pre-1.5.5 firmware spike; slew feel at 30 W/s.
- **SIM feel.** Virtual gear steps on a real flywheel, the haptic wind bound and the 0.5 s write slots.
- **Cadence.** The KICKR's cadence estimate and its lag after sprints; the `CadenceEstimator` ratio on real speed.
- **Rules timed on real data.** Rescue, coasting and gestures on real ~1 Hz notification jitter.
- **Reconnect.** Real link loss, backoff and restore.
- **Exit.** The exit path's SIM flat + Stop reaching the trainer within the 0.5 s quit grace.

## 9. Known differences and gaps

1. **Double ticking in the app.**
   - `AppServices.set_menu_ticking()` calls `TrainerService.set_menu_ticking()`, which doesn't exist, and nothing calls `TrainerService.set_external_tick(true)`.
   - So in windowed sessions (GameHost in real time) and in the FTP test (the screen's `step_fixed`), the TrainerService's `_process` keeps ticking the same `LocalRider` that the session also ticks, and the rider's platform time runs at about 2× wall time. In wall time that halves the governor's windows (rescue 3 s/5 s, coasting 3 s/10 s, warm-up 300 s, duration limits, haptic 8 s), makes slew effectively 60 W/s, lets the 0.5 s slots write up to 4 times a second, runs the governor's phase ramps ahead of the GameHost's phase clock, makes MockTrainer notify at ~2 Hz and the recorder write two records per wall second.
   - `GameSimRunner` (headless sims, conformance) doesn't use the TrainerService and is unaffected.
   - Separately, a headless scripted peer (`--host`/`--join` under a headless display server) builds its GameHost with `realtime` false, and nothing steps it.
2. **No restore after a reconnect** (BRIEF 4.4 "restore the last safe mode").
   - The connection manager reuses the `FtmsTrainer` object, so `TrainerService` doesn't rebind, and nothing listens to `reconnected`.
   - `begin()` leaves the trainer at SIM flat while the controller still believes its last written state. Writes made while the link was down were dropped by `FtmsClient`.
   - The trainer stays SIM flat (safe) until the governed target or SIM state next changes.
3. **No reset after a session.**
   - Because ticking is never handed over (item 1), the session's rider and governor stay the menu rider after the results or End ride.
   - The governor keeps commanding the last plan phase in menus under the normal rules: the cool-down's 50 % FTP, or the interrupted phase's target after End ride. The platform ADR intends menus to ride free at SIM flat.
   - Without a plan, a fresh menu governor writes nothing at all (`command_off`), so the trainer keeps whatever was written last.
4. **Warm-up restarts per session.** Every session sets the rider up with a new governor, so the warm-up counts from the first stroke of each session rather than from the trainer connecting (BRIEF 4.6.8); duration-limit counters and the gear reset too.
5. **Rescue uses min(target, 50 % FTP)** and never raises a lower target; BRIEF 4.6.12 says "50 % FTP instead".
6. **Haptic grade is bounded to −3…+3 %**, not only +3 % (stricter than BRIEF 4.6.6).
7. **Host and governor disagree on haptics in a block.** The host's `DirectiveRouter` treats any `mode: SIM` request in an ERG phase as opening a block, even while one runs. It checks length and spacing again, where the governor only confirms. A haptic sent as `{mode: SIM, haptic, duration_s ≤ 8}` during a running block is therefore refused by the host (`sim_block_length`) though the governor would accept it. Send haptics inside a block without `mode`.
8. **MockTrainer keyboard control** (BRIEF 4.2) exists but nothing in the app enables it. Its W/S keys would also collide with the up/down bindings.
9. **The app doesn't launch the bridge**, and RESISTANCE mode (P1) is implemented in the controller but nothing commands it.
