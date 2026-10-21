# Template game

The smallest working Wattlands game (BRIEF 3.6). `tools/new_game <id>` copies it, with
`content/_template/`, `assets/_template/` and `tests/games/_template/`, into a new game and renames
everything (`_template` -> `<id>`, `Template` -> `<Id>`, `_TEMPLATE_` -> `<ID>_`).
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

## Files

| File | What |
| --- | --- |
| `game.json` | The manifest: ids, players, contents, options (`toggle`, `choice`) and player options (`int`) |
| `template_game.gd` | `TemplateGame`, the GameModule entry: every SDK call |
| `template_rules.gd` | `TemplateRules`, the pure rules: `step(state, inputs, dt)` |
| `template_view.gd` | `TemplateView`, the 2D view at `pixel_base` 640 x 360 |
| `HARDWARE_TEST.md` | The real-trainer checklist for this game |
| `content/_template/*.json` | One file per content id (phases and tuning), loaded with `ctx.load_content_json` |
| `content/_template/strings.csv` | Every user-facing string, keys prefixed `_TEMPLATE_` |
| `tests/games/_template/` | Unit tests with recording fakes; `integration/` runs the real platform |
