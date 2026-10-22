# Siege game

The smallest working Wattlands game (BRIEF 3.6). `tools/new_game <id>` copies it, with
`content/siege/`, `assets/siege/` and `tests/games/siege/`, into a new game and renames
everything (`siege` -> `<id>`, `Siege` -> `<Id>`, `SIEGE_` -> `<ID>_`).
`docs/GAME_SDK.md` walks through every call it makes. Replace this README with your game's rules
summary, schemas, tuning knobs and P2 notes.

## What it plays

Each rider pushes a marker along their own lane of a track, at a speed proportional to P_eff, so every
FTP plays fair. The plan is a 5-minute warm-up ramp (50 -> 65% FTP), then 3 minutes of WORK at 75% FTP
(plus the rider's `work_offset`), then the platform's 3-minute cool-down. 60 s into the WORK phase a
"hill" raises the target by 5% for 30 s, inside the phase's `range_pct`. A lap marker splits the WORK
phase at 90 s. Confirm, a `surge` or the HUD's Boost button boosts your marker for 5 s; Autopilot boosts
every 30 s. Rescue and AFK make a marker wait. Results grade the team's time in band and give XP per kJ
and per lap; 3 laps unlock the gold marker.

The `short` content (the e2e content, about 3 minutes plus the cool-down) shows the calls the default
content has no room for: a 60 s warm-up ramp, a 40 s SIM "Rollers" phase whose grade the game feeds
with `ctx.directives.course_grade` (`grade_source: "game"`), and at the Rollers' start a
`ctx.directives.replan` of the rest of the plan into an open-ended "Finish" (30-50 s) that the game
ends with `ctx.directives.end_phase` once the rider holds the target after `min_s`. After it the riders'
phases drift apart, so each rider's phase change shows a `ctx.hud.banner` on that rider's own peer only,
and `phase_changed` reports the group's phase (the lowest index any rider is in).

## Files

| File | What |
| --- | --- |
| `game.json` | The manifest: ids, players, contents, options (`toggle`, `choice`) and player options (`int`) |
| `siege_game.gd` | `SiegeGame`, the GameModule entry: every SDK call |
| `siege_rules.gd` | `SiegeRules`, the pure rules: `step(state, inputs, dt)` |
| `siege_view.gd` | `SiegeView`, the 2D view at `pixel_base` 640 x 360 |
| `HARDWARE_TEST.md` | The real-trainer checklist for this game |
| `content/siege/*.json` | One file per content id (phases and tuning), loaded with `ctx.load_content_json` |
| `content/siege/strings.csv` | Every user-facing string, keys prefixed `SIEGE_` |
| `tests/games/siege/` | Unit tests with recording fakes; `integration/` runs the real platform |
