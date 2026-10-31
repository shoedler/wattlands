# Decisions: cleanup c1

## 2026-10-31: a stricter walk decides what the tank generator keeps, and the bakes prove it

- **Decision:** delete the generator code a walk with strings and comments stripped cannot reach from `bake.gd`, `r6_base.gd`, `env/` and `assets/tank/v4/tools_src/`. That goes beyond SPEC_CLEANUP 2.2's table: `tank.gd` and `mach.gd` go whole, `tank_r5.gd` and `tank_r6.gd` fold into `tank_gen.gd` with `layout`, `build`, `roof` and `puff` only, and `gear.gd` and `px.gd` lose more than `tools/qa/scan/toolsrc_reach.mjs` lists. That scan counts a name inside a string or a comment as a call (`"loader"`, `Tank6.blast()`), so it reports what stays as all live and can't see the rest.
- **Alternatives:** delete only what `toolsrc_reach.mjs` calls dead, which keeps about 1200 lines nothing runs.
- **Reason:** the proof doesn't depend on the walk. `bake.sh` and `enemy_bake.sh` rewrite `assets/tank/v3` and `assets/tank/v4` byte for byte after each cut, the same as on the untouched tree, and a missing function is a parse error on a preloaded script. No dynamic call names a deleted function: the only `.call("...")` uses were lambdas in the deleted `interior` functions.

## 2026-10-31: r6_hitbox.json is checked-in data

- **Decision:** `assets/tank/v3/r6_hitbox.json` has no writer after `mock_r6.gd`. `bake.gd`'s header says so. `test_tank_v3_contracts.gd` still ties it to `tanks.json`.
- **Alternatives:** keep `job_hitbox` and the whole dead chain it needs.
- **Reason:** the plan leaves the tank's body as it is, so nothing regenerates the hitbox.

## 2026-10-31: the cards and the type leave v2, and v2 goes

- **Decision:** the cards move to `assets/tank/cards/`, the type to `assets/tank/hud/`, `cards.gd` and `cards.sh` to `assets/tank/v3/tools_src/`. The rest of `assets/tank/v2/`, `source/reference.webp` included, is deleted. `card_ambush` moves too, which the spec's list missed. The moved `cards.sh` was run once and works; its renders were thrown away, so the cards stay byte-identical.
- **Alternatives:** keep `reference.webp` because `docs/games/tank.md` names it as THE reference.
- **Reason:** `tank_4rider.png` is the live input and the briefs are history; the image stays in git at every earlier commit. `docs/games/tank.md` is never edited, so its paths now describe the past.

## 2026-10-31: rigs.json keeps only what the rules read

- **Decision:** drop `tanks` and `machinery` (855 of 943 lines), `RIG_FALLBACK`, `rig_of`, `has_rig` and `secondary_muzzles`. Also drop `boss_secondary_muzzle`, its frozen key and `boss.secondary_muzzle`: the spec expected a reader, and v4 left none. The Behemoth's bow secondary now comes from `assets/tank/v4/enemies.json`. `enemies.enemy_dugin` and its two frozen keys stay, because `test_tank_contracts.gd` still reads the hit box. `screen`, `enemies` and `boss` stay.
- **Alternatives:** keep the frozen `boss.secondary_muzzle` for a future reader.
- **Reason:** behaviour hash tank matches the baseline on all four scenarios.
