# Decisions: cleanup c2

## 2026-10-31: tank_mech.gd becomes a star of one kit and six machines

- **Decision:** `TankMechKit` holds the sizes, ratios, palette, room and `Cv`. `TankMechDiesel`, `Dynamo`, `Steam`, `Arc`, `Feed` and `Repair` extend it and hold one machine each. `TankMech` extends it too and keeps `paint`, `paint_ex`, `_rate_of` and the caches. Only `paint_ex` changed: its arms name their class. `verify_move` proves the rest byte-identical, and `mech_hash` matches on all 288 images.
- **Alternatives:** a chain like `tank_view.gd`'s; keeping the file whole.
- **Reason:** the machines depend on the kit and almost never on each other, so one machine can be read and changed alone. A chain would claim a dynamo is a diesel.

## 2026-10-31: TankMech forwards the repair hammer

- **Decision:** `TankMech` keeps `R_CAM`, `R_CAM_R`, `R_HEAD_X`, `R_REST_Y`, `R_HEAD_LIFT`, `R_LIFT`, `R_SPARK`, `hammer_lift` and `since_strike` as forwarders to `TankMechRepair`. SPEC_CLEANUP 3.1 did not list them, because the repair machine's outside readers (`TankInterior`, `test_tank_mech.gd`, `test_tank_audio_bank.gd`) arrived after the spec's scan.
- **Alternatives:** move them to `TankMechKit`, which tears the repair machine's constants in two; `TankMech extends TankMechRepair`, which says the painter is a repair machine; changing the callers, which the spec rules out.
- **Reason:** the repair machine stays in one file and no caller changes.

## 2026-10-31: test_tank_audio_bank's art pins follow the formulas to their machine's file

- **Decision:** the five tests that read `tank_mech.gd` as text and check each art formula's line need to read `tank_mech_<machine>.gd`. They ask for the same ten lines, now each in its own machine's file. The test sits outside this batch's paths, so the lead applies the change.
- **Alternatives:** quote the lines in a comment in `tank_mech.gd`, which keeps the test green and pins nothing; leave the moving bodies in `tank_mech.gd`, which needs a chain and parts each machine from its own drawing.
- **Reason:** the formulas did not change, only their file, and the test's own header says it speaks up when a formula moves.
