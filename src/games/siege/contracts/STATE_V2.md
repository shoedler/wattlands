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
