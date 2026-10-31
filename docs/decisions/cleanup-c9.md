# Decisions: cleanup c9

## 2026-10-31: Turbo Reel's credit says no fal output ships, and how we know

- **Decision:** keep "no generated art ships" in `docs/credits.d/fishing.md`, and name the 53 fal requests of 2026-10-23 in `assets/fishing/art_manifest.json` as a first attempt whose output does not ship.
- **Evidence:** none of the 31 images under `assets/fishing/` has a SHA-256 in the manifest (though the manifest hashes the raw results, not the pixelated sprites), and none is the same git blob as any PNG of `08036c31`, the commit that wrote the fal sprites. `bff49a6a` deleted those sprites and added the grids. Of the five ids in both sets, four have other sizes (`fish_marlin` 64 x 22 then, 420 x 45 now), and `picker_card` keeps 160 x 90 as another file, composed from the grid sprites. `art.json` marks all 30 sprites as hand-authored grids, and `tests/games/fishing/art/test_fishing_art.gd` proves every PNG is what `FishingArtGrids` draws (19 tests pass). `bff49a6a`'s message says the generated sprites are gone.
- **Limit:** git cannot prove nobody looked at a generated picture while typing a grid. No tool in the game's history reads `.art_cache` or turns a generated picture into a grid.
- **Alternatives:** drop the manifest from the credit (a reader who finds it would rightly ask); credit fal (false for what ships).

## 2026-10-31: Tank's credit names the reference's source only as far as the repo records it

- **Decision:** the credit no longer says "made for this project" or "no generated sprites". It says what `docs/games/tank.md` says: Simon's image, with the prompt that made it quoted, the tool not recorded. The path stays as a history pointer at d82d901c.
- **Alternatives:** call it generated (the repo doesn't say by what); leave it out (the base art derives from it).
- **Reason:** `CREDITS.md` ships next to the exe. The owner should confirm the tool and its terms before the public release.

## 2026-10-31: DECISIONS.md takes the platform fragments of the v1 run

- **Decision:** merge `gate`, `audio-dsp`, `audio-kit`, `audio-sync`, every `cleanup-*` and the lead's two new ADRs. `fishing`, `siege`, `tank`, `workout` and `audio-<game>` stay in their fragments, with a pointer.
- **Alternatives:** merge all of them (about 2,000 more lines, against the file's own header: game sessions keep theirs).
- **Reason:** existing practice since v0.1.0. Where an older fragment and `docs/DECISIONS.md` differ, the merged text was the one edited later and matches the code (pedal navigation, the rescue banner), so the older merge stands.

## 2026-10-31: OWNERSHIP 1.3 keeps a list of the frozen seams

- **Decision:** 1.1 and 1.2 are rewritten to match `tools/lib/gate_manifest.json`; 1.3 stays as one paragraph, without its owner table.
- **Alternatives:** delete 1.3, as the spec's one-screen table implies.
- **Reason:** `tests/governor/test_api.gd:2` cites the "Governor" seam of 1.3, and that path is denied to cleanup.
