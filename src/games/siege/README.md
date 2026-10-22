# Generator Siege

Co-op tower defense on Castellum Rotae, a Roman hill fort that runs on treadwheels (brief: `docs/games/siege.md`). Each rider's watts turn a wheel and go to one target: a tower (defense now) or the generator (denarii for the breaks). Waves are ERG intervals, breaks are recovery and shopping, and Overdrive is a 30 s SIM sprint block. Decisions: `docs/decisions/siege.md`.

G0 status: contracts, content, plans and Overdrive are final; the rules, combat, Autopilot, view and HUD are stubs the G1 builders complete. The full rules summary, tuning knobs and P2 notes come at G4.

## Files

| Path | Owner | What |
| --- | --- | --- |
| `game.json` | lead | The manifest (brief 2.2) |
| `contracts/` | lead (G0) | `SiegeIds`, `SiegeMap`, `SiegeContent`, `SiegeRecord` and the state records (`SiegeState`, `SiegeRiderState`, `SiegeTowerState`, `SiegeEnemyState`, `SiegeZoneState`, `SiegeShot`, `SiegeSpawn`, `SiegeWaveState`), the rules input (`SiegeInputs`, `SiegeRiderInput`, `SiegePhaseInfo`), `SiegeIntents`, `SiegeIntentLimiter`, `SiegeEvents`, `SiegeSnapshotSchema` |
| `rules/siege_plan_builder.gd`, `rules/siege_overdrive.gd` | lead (G0) | `SiegePlanBuilder` (plans and wave offsets), `SiegeOverdrive` (the Overdrive state machine and its directive) |
| `rules/`, `combat/` | B1 rules | `SiegeRules.step`, `SiegeScore`, `SiegeCombat` |
| `siege_game.gd`, `autopilot/`, `net/` | B2 module | `SiegeGame`, `SiegeAutopilot`, `SiegeSnapshot` |
| `view/`, `hud/`, `audio/` | B3 view | `SiegeView` (3D miniature), `SiegeHud` |
| `content/siege/` | lead: `maps/`, `strings.csv`; B1: `shifts`, `balance`, `towers`, `enemies`, `waves`; B2: `cosmetics` | Validated at load by `SiegeContent` |
| `tests/games/siege/` | per folder (see `docs/decisions/siege.md`, "Four G1 builders") | `siege_fakes.gd` (shared fakes), `fixtures/` (`SiegeFixtures`) |
