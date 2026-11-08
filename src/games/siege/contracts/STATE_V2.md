# Siege v2 state interface (what the view and HUD read)

The rules builder owns `contracts/` and may add fields; it must keep these names and meanings. The view builder reads only these (through `SiegeState` on every peer; clients rebuild them from the snapshot in docs/games/siege.md 2.6). Units: m, s, W, gold. World coordinates as in `SiegePath`.

## Shared foundations (already on the branch)

- `SiegePath` (`contracts/siege_path.gd`): the v2 map. Use `SiegePath.load_file("res://content/siege/maps/rotae.json")` or `state.path`. It provides `point_at(prog, lat)`, `dir_at`, `to_art(Vector3) -> Vector2` (art pixels), `depth(Vector3)`, `muzzle(id, yaw_deg)`, `station_pos`, `pads`, `wheels`, `bridge_from_m`, `bridge_to_m`, `moat_edge_m`, `staging` and `length_m`.
- `SiegeBallistics` (`combat/siege_ballistics.gd`): `step`, `land`, `solve_angle`, `solve_speed`, `spread`.
- `SiegeHashRng` (`combat/siege_hash_rng.gd`): per-shot spread from a seed.

## Ids (`SiegeIds`)

- Stations (rider targets 0..4):
  - `STATION_MINE` 0 (also kept as `TARGET_GEN`);
  - `STATION_BALLISTA` 1;
  - `STATION_ONAGER` 2;
  - `STATION_ARROWS` 3;
  - `STATION_TAR` 4;
  - `STATION_COUNT` 5;
  - `STATION_NAMES` `["mine", "ballista", "onager", "arrows", "tar"]`.
- Pads 1..4: `PAD_COUNT` 4. Pad weapon types: `PAD_NONE` 0, `PAD_SCORPION` 1, `PAD_CALTROP` 2 (P1).
- Enemies:
  - `ENEMY_SPEAR` 1;
  - `ENEMY_SHIELD` 2;
  - `ENEMY_CHARIOT` 3;
  - `ENEMY_RAM` 4;
  - `ENEMY_TOWER` 5;
  - `ENEMY_NAMES` `["", "spear", "shield", "chariot", "ram", "tower"]`.
- Enemy states: `EN_WALK` 0, `EN_BATTER` 1 (a ram at the gate), `EN_RETREAT` 2, `EN_DOCKED` 3 (a siege tower at the moat edge).
- Shot kinds (`shot` event `kind`): `SHOT_BOLT` 0, `SHOT_STONE` 1, `SHOT_ARROW` 2, `SHOT_SCORPION` 3. Shot `src`: a station 1..3, or 10 + pad.
- Events: `EV_WAVE_START`, `EV_WAVE_END`, `EV_RUSH`, `EV_PUSH`, `EV_DOCK`, `EV_SHOT`, `EV_KILL`, `EV_LEAK`, `EV_BREACH`, `EV_GATE_RESTORED`, `EV_BUY`, `EV_ROUTE`, `EV_OVERDRIVE`. The strings are the brief's type names.

## `SiegeState`

| Field | Type | Meaning |
| --- | --- | --- |
| `path` | `SiegePath` | The map |
| `tick`, `t` | int, float | Game tick and seconds |
| `phase_index`, `role`, `wave_no`, `waves_total`, `phase_elapsed_s`, `phase_duration_s`, `phase_remaining_s`, `done` | | Phase clock, as in v0.1.0 |
| `in_wave()`, `shop_open()`, `in_cooldown()`, `rush_on()` | bool | As in v0.1.0 |
| `gate_hp`, `gate_max`, `breach_s`, `breaches`, `iron_bands` | | The gate |
| `mine_level` | int 0..3 | |
| `perks` | `Array[int]` | `PERK_RESERVE` 1, `PERK_AQUEDUCT` 2, `PERK_CAULDRON` 3 |
| `team_w` | float | Team raw watts, 1 s mean |
| `riders` | `Array[SiegeRiderState]` | Slot order |
| `stations` | `Array[SiegeStationState]` | Index = station id, always 5 |
| `pads` | `Array[SiegePadState]` | Index = pad − 1, always 4 |
| `enemies` | `Array[SiegeEnemyState]` | Spawn order |
| `tar` | `SiegeTarState` | |
| `queued()` | int | |

## `SiegeRiderState`

The same fields as v0.1.0, with these changes:
- `target` is a station 0..4;
- `denarii` becomes `gold`;
- `wave_gen_s` / `wave_tower_s` become `wave_mine_s` / `wave_weapon_s`.

The view reads `slot`, `peer`, `is_bot`, `target`, `reconnect_s`, `p_eff_w`, `raw_w`, `cadence_rpm`, `rescue`, `afk`, `gold`, `od_state`, `od_s`, `od_cd_s` and `od_prompt`, plus `delivering()`.

## `SiegeStationState`

| Field | Meaning |
| --- | --- |
| `id` | 0..4 |
| `level` | Upgrades 0..3 (team-wide) |
| `m` | Output multiplier now (0 idle) |
| `wind` | 0..1: winding of the next shot (ballista, onager); for the arrow organ, the reload of the next rack |
| `yaw_deg` | Current aim, atan2(dy, dx) |
| `arm` | 0..1 animation phase: 0 just fired (the onager arm up, the ballista string forward, a rack empty), rising to 1 at fully wound |
| `rack` | Arrow organ: the next rack to fire, 0..2 (0..3 with the upgrade) |
| `damage_wave`, `shots`, `hits` | Results and Autopilot |

## `SiegePadState`

`pad` (1..4), `type` (`PAD_*`), `level`, `cd_s`, `yaw_deg`, `built()`.

## `SiegeEnemyState`

| Field | Meaning |
| --- | --- |
| `id`, `type`, `hp`, `max_hp`, `st` | |
| `prog_m`, `lat_m` | Position on the path |
| `speed_mps` | Current speed |
| `pos` | `Vector3` world position (`path.point_at(prog_m, lat_m)`), kept current by the rules and by `place(path)` on clients |

## `SiegeTarState`

| Field | Meaning |
| --- | --- |
| `cauldron_l`, `cauldron_max_l` | Litres in the cauldrons, of 300 or 400 |
| `curtain_hp`, `curtain_max` | 0..200, or more with upgrade 2 |
| `coat` | 0..1 on the bridge |
| `boarded` | A docked siege tower has boarders on the wall |

## Module signals the view listens to

`SiegeGame.cue(kind: String, data: Dictionary)` fires for every event on every rendering peer: on the host where it sends the event, on clients in `apply_event`. The view replays `shot` cues with `SiegeBallistics` and `SiegeHashRng(sd)`. Each arrow `j` of an `n`-arrow volley draws its own spread in order:
- `yaw += gauss(σ)`;
- `pitch += gauss(σ)`;
- `speed × (1 + range_f(−s, s))`.

σ and s come from `content/siege/stations.json` (`spread_deg`, `speed_spread`).

## Additions by the rules builder (all names above are kept)

Helpers:
- `SiegeBallistics.shot_velocities(v0, n, sd, spread_deg, speed_spread) -> PackedVector3Array`: the n launch velocities of one shot, drawn in the order above; the host flies exactly these.
- `SiegeEvents.shot_origin(e) -> Vector3` (m) and `SiegeEvents.shot_velocity(e) -> Vector3` (m/s) read a `shot` event's ints. Stones and arrows land on the aim point's ground (`SiegeBallistics.land(o, v, k, floor_z)`; floor_z is the path z near the target, about 0); bolts stop at the first body (Scorpion) or fly on (ballista).
- `SiegeBallistics.step` moves the position by the mean of the old and new velocity (ADR "trapezoidal position step").
- Spread per kind: `content.station_def(src)` for src 1..3, `content.pad_def(SiegeIds.PAD_SCORPION)` for src 11..14 (`spread_deg`, `speed_spread`, `k`).
- `SiegeSnapHistory` (`game.history` on clients): `advance(delta)`, `prog_of(id, fallback)`, `lat_of(id, fallback)`, `pos_of(id, fallback: Vector3) -> Vector3`.
- `SiegeGame.station_key(id)` is the station's name key (`SIEGE_STATION_MINE` ...). `SiegeGame.hud_plan(peer)` is a rider's plan with the cool-down, on every peer, for the HUD.

`SiegeState` extra fields: `projectiles` (host only), `gate_damage`, `leaks`, `engines_total`, `engines_stopped`, `wave` (`SiegeWaveState`: `rush_s`, `rush_next`, `gate_damage`, `leaks`), and `station(id)`, `pad(n)`, `range_band(id)`, `pad_band(n)`, `in_band(id, p)`, `station_cap(id)`, `cauldron_max()`, `curtain_max()`, `docked_tower()`, `alive_by_type()` (index = enemy code, 6 entries), `target_hot(id)`.

`SiegeRiderState` extra fields: `mine_gold`, `bounty_gold`, `station_s` (wave seconds per station), `top_station()`.

`SiegeStationState` extra fields: `target_id` (host), `damage_total`, `kills`. The tar works' `wind` and `arm` are the cauldron fill; the mine's `arm` turns with its m.

`SiegePadState` extra fields: `shots`, `hits`, `kills`, `damage`, `built_by`.

`SiegeEnemyState` extra fields: `reached` (an engine at the gate or docked), `escort`, `crew`, `rush`, `want_mps` (host).

Events (payloads in `contracts/siege_events.gd`):
- `push` {id, et, prog_dm}: one per engine as it enters;
- `dock` {id};
- `kill` {id, et, src (station 1..3, 10 + pad), x2};
- `leak` {id, et, dmg};
- `buy` {slot, item, station, pad, ok, why, lvl}.

Snapshot: `gd` is this wave's gate damage (0.1 HP); optional `ru` [1, i, left_ms] during a rush and `rk` (the arrow organ's next rack, absent at 0).

Review fixes (2026-10-30):
- `reach` {id, et}: a ram reached the gate (cued like every event).
- Snapshot rider rows have 13 columns: `connected` (R_CONNECTED 11) and `shop_fallback` (R_SHOP_FALLBACK 12) follow `afk`; clients get `SiegeRiderState.connected` and `shop_fallback` from them. Optional `rn`: `state.wave.rush_next` on clients.
- The mine's `m` and `arm` move in breaks too (all output goes to it then).

## The shared receipt (v0.7.0)

- `SiegeState.receipt`: `Array[SiegeReceiptLine]` in the order the items were added. A line is `item` (a `SiegeIds.ITEMS` id), `at` (the station for an upgrade, the pad for a Scorpion or a pad upgrade, else 0), `cost` (fixed when it was added), `slot` (the picker) and `no` (the slots that voted no, in slot order). Helpers: `receipt_line(item, at)`, `held_by(slot)`, `receipt_total()`, `spendable(rider)` (gold less what the rider holds, never below 0), `voter_slots()` (the connected riders, bots included) and `vote_on(line)` (a `TeamVote` over them: the picker counts yes, a majority no or a tie rejects).
- `SiegeRider.gold` is unchanged by a pick: the receipt only holds it. The HUD and Autopilot read `spendable`.
- Snapshot: the optional key `rc`, a list of `[item_code, at, cost, slot, no_slot...]` rows (`SiegeIds.item_code`, 1..9), present only while the receipt is not empty. A client rebuilds `state.receipt` from it (rows with an unknown item, an unknown slot or a repeat are dropped, at most 32 rows are read).
- Intent: `{"k": "pick", "item", "station"?, "pad"?, "auto"?}` (`"buy"` is read as `"pick"`). The host adds, takes back or votes; `auto` is ignored; a pick while the shop is closed is ignored.
- Event: `receipt` {`slot` (who acted), `item`, `station`, `pad`, `act` (`RC_ADD` 1, `RC_TAKE` 2, `RC_NO` 3, `RC_YES` 4, `RC_REJECT` 5, `RC_DROP` 6), `picker`, `yes`, `no`}. `buy` events now come when the break ends (and for a pick the shop refuses): `buy` {slot, item, ...}.
