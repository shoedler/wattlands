# Big Game Fishing backlog

What v0.1 does not ship, from docs/games/fishing.md 2.9, 3.3 and 4.3 (P1 ships once P0 is green; P2 stays a note here).

## P1 (not built in v0.1)

- **Deep Blue Trench at night**: a second area with a night palette and its own spots. Giant grouper (T_nom 180-300 s, `max_s` 330, 90%, band -10, peak 97.2%) and swordfish (360-600 s, `max_s` 660, 92-97%, band -5; v1's 100% top would peak at 108%, over the 105% long-phase cap). Sprites `fish_grouper` 40x18, `fish_swordfish` 64x20, `moon`, `trench_back`, `plankton`.
- **`marlin_hunt`** (75 min): a marlin bites 15-20 minutes in, T_nom 900 s, 6 jumps at 104%.
- **`.zwo` bite scheduling** through the platform's workout parser (BRIEF 3.7): work blocks >= 60 s become fights at the block's target and length, blocks above 105% lasting <= 30 s become runs, recoveries become Reels; the PlanValidator decides.
- **A legendary fish for two rods**: 2+ riders only, 88-92% +-8%, 8-12 min; it tires 1.5x while both riders are in band and 0.5x while one is. Sprite `fish_legend` 96x30.
- **Generated art**: v0.1 ships placeholder sprites (`FishingFallbackSprites`). Generate the art.json set with the pipeline once `FAL_KEY` and `WATTLANDS_ALLOW_ART=1` are set (assets/fishing/README.md, $10 budget), including a generated `picker_card` to replace the G0 placeholder.
- **Screenshots** (brief 4.3): `tools/screenshot` at 1, 2 and 4 lanes during the ride out, a pick, a tuna run, a marlin jump and a Landing.

## P2 notes

- A tournament trip: one fixed fish schedule for everyone, scored by total kg, with a board per seed.
- Hats and boat models as cosmetics (today: line colours, canopy patterns, hull trims, a trophy pennant).
- Weather: chop on the surface strip, rain squalls that dim the sky palette; never a change to the load.
- Sim QA: run the full S3 set (`run_sims.sh --full`, seeds 1-20) in a nightly job rather than per push.
