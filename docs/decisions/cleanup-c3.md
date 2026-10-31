# Decisions: cleanup c3

## 2026-10-31: tank_view.gd is a chain of six classes

- **Decision:** `TankViewBase`, `TankViewMotion`, `TankViewSeats`, `TankViewWorld` and `TankViewHud` sit under `TankView`, each calling only down. Bodies moved byte-for-byte, proved by `tools/qa/verify_move.mjs` with no allow list. `far_panel_x` moved from Frame to Base, because the HUD's geometry reads it and it reads only `panels`.
- **Alternatives:** a star like `TankMech`'s; a virtual stub to keep `far_panel_x` in `TankView`.
- **Reason:** the sections share one set of vars and call down, so a star would pass the view everywhere. GDScript has no partial classes, and inheritance lets every `TankView.X` outside the file keep working. A stub would add a call the parser can no longer check.

## 2026-10-31: the near threats' lanes stay in the view

- **Decision:** keep `LANES`, `LANE_FOOT`, `lane_foot` and `lane_rect`. `lane_scale` is already gone.
- **Alternatives:** delete them, as SPEC_CLEANUP 2.1 asks if nothing but their own tests read them.
- **Reason:** v4 uses them: `near_ground`, `_track_enemies` and `TankWorldDraw` read them at run time.

## 2026-10-31: seat phases use one CrankClock per seat

- **Decision:** `_seats` advances a `CrankClock` per seat, made on first use, and writes `phases[seat] = clock.revs`. `phases`, `machine_phase` and `audio_feed` stay.
- **Alternatives:** read the clocks directly and drop `phases`.
- **Reason:** no reader changes and no number moves. The rpm there is 0 or above `STOP_RPM`, which `CrankClock` ignores the same way, and the dt is `render_dt` (clamped to 0 or more) or `dt`, so its early return changes nothing. The sum is the same float expression. SPEC_CLEANUP's `MAX_DT_S` difference is void under E1: the class has no clamp.
