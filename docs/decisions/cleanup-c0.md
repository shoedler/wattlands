# Decisions: cleanup c0

## 2026-10-31: TankKit goes with nothing to replace it

- **Decision:** delete `TankKit`, `assets/tank/v2/kit.json` and `test_tank_kit.gd`. `tests/games/tank/test_tank_cards.gd` holds four tests in their place and reads its paths from `game.json`. The manifest's `crew` assert in `test_tank_v3_tank.gd` now asserts the manifest is gone.
- **Alternatives:** keep a thin manifest for the cards; do it in the batch that moves the cards.
- **Reason:** nothing at run time read it after v4: `game.json` names the cards. Done first, because moving the cards would break `TankKit.check`.

## 2026-10-31: behaviour_hash compares every field, deterministic_hash included

- **Decision:** the baseline holds `deterministic_hash`, and a compare fails on it like any other field. Two runs of the same commit in two worktrees wrote byte-identical files, so no path reaches the report and the field needs no exception.
- **Alternatives:** skip `deterministic_hash` and rely on the snapshot, event and directive hashes, which the spec allows only if the two runs disagree.
- **Reason:** it is the wider check: it also covers results and traces.

## 2026-10-31: behaviour_hash subsets merge into --out, and --names runs one scenario

- **Decision:** `--games` and `--names` (added) run a subset, merge its rows into an existing `--out` and compare only the rows they ran. A failed run writes no row and exits 1. The first differing entries are read from the reports beside the `--compare` file.
- **Alternatives:** overwrite `--out` on every call; store whole reports in the baseline file.
- **Reason:** agents' shell calls stop at 10 minutes, so a run must be splittable (all ten take about 4 minutes on a quiet machine). The baseline file stays small and the reports stay in `build/`.

## 2026-10-31: verify_move fails a dropped allowed name, and keeps a column-zero comment in its body

- **Decision:** an `--allow` name may differ but must still exist. A column-zero comment run followed by an indented line stays in the body it interrupts; other comment lines attach to the declaration directly below or count as loose.
- **Alternatives:** let `--allow` skip the block entirely; end a body at any column-zero line.
- **Reason:** allowing a change must not hide a deletion, and a body cut short would move part of a function unchecked.

## 2026-10-31: the generator walk also counts what a reached module's top-level code names

- **Decision:** `toolsrc_reach.mjs` adds `assets/tank/v4/tools_src/*.gd` as entry points, as the spec asks, and also walks the constants and inner classes of each reached module, with strings and comments stripped.
- **Alternatives:** walk column-zero functions only, as the original did.
- **Reason:** a generator's inner class or constant can name a function too, and the walk decides deletions that no gate checks, so an error must fall on the side of keeping a function.
