# Decisions: cleanup c7

## 2026-10-31: Siege's PROPOSAL.md goes, though the Siege brief still cites it

- **Decision:** delete `src/games/siege/art/PROPOSAL.md` and its clause in `src/games/siege/README.md`. `docs/games/siege.md:3` still names the file, and that path is never edited, so the citation dangles. Git holds the file: `git show c885d4ed~1:src/games/siege/art/PROPOSAL.md`.
- **Alternatives:** keep the file so the citation resolves.
- **Reason:** it says of itself "mockup stage, not approved" and that once approved it becomes sections of the brief, which has happened. A stale proposal next to the art tools misleads more than one historical citation does.

## 2026-10-31: three names outside the spec's list, two deleted and one kept

- **Decision:** delete `TankIds.FROM_FRONT` (the content schema now rejects any encounter `from`) and `TankAutopilot.EDGE_MARGIN_PX`, each with its comment. Keep `TankIds.RETIRED_ENEMY_CODES`, which no code reads, and keep `TankIds.BOSS_ID`, which v4's far panel now uses.
- **Alternatives:** leave all three, as the spec's list predates them.
- **Reason:** the first two describe nothing that exists any more. `RETIRED_ENEMY_CODES` records that wire code 4 is never reused, the same job as the schema constants the spec leaves as wire documentation.

## 2026-10-31: Siege's writePng keeps deflate level 9

- **Decision:** `src/games/siege/art/png.mjs` calls `encodePng` from `tools/art/lib/png.mjs` with `{ level: 9 }`, as Workout's wrapper does, and keeps `toRgba8`.
- **Alternatives:** take the codec's default level 6.
- **Reason:** level 6 would change the bytes of committed art. A bake with the old writer and one with the new are byte-identical, and both match `assets/siege/bake`.

## 2026-10-31: `siege/view/v2` and `SiegeV2*` keep their names

- **Decision:** no rename, though v2 is the only view.
- **Alternatives:** rename to drop the "v2".
- **Reason:** it touches more than 30 files and changes no behaviour.
