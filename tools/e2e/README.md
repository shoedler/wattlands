# tools/e2e: the multiplayer end-to-end test

`node tools/e2e/run.mjs --games=<id>[,<id>...]` plays each listed game's `e2e_content` with one host and two clients (BRIEF 3.6, 7.7). Zero npm dependencies; `node --test tools/e2e/test` runs its own tests with stand-ins for Godot, the relay, the mock Strava server and the FIT checker (`tools/e2e/fixtures/`).

## What one game's run does

1. Takes one lease of 3 Godot slots from the machine-wide lock (`tools/lib/godot_lock.mjs`) for the whole run. Every peer runs through `tools/godot.sh` with `WATTLANDS_GODOT_LEASE_TOKEN`, so it never queues again; the restarted client reuses the killed one's slot. A lock wait timeout exits 75 and starts nothing.
2. Starts the relay (`--relay-cmd`, default `node server/relay/src/main.ts` with `PORT=<free port>`; `{port}` in the command is replaced) and waits for `GET /health`; starts the mock Strava server (`--strava-cmd`, default `node server/mock_strava/server.mjs --port=0`; the port comes from its first line naming a URL, `port N` or `{"port": N}`).
3. Starts the host headless: `tools/godot.sh --timeout=<s> --headless --path <repo> --log-file <peer dir>/godot.log -- --host --game=<id> --e2e --wait-peers=3 --relay=ws://127.0.0.1:<port>/v1 --mock-trainer=erg:compliance=1.0 --autopilot --profile-dir=<peer dir>/profile --sim-speed=1 --seed=<n> --report=<peer dir>/report.json --strava-base=http://127.0.0.1:<port> --run-seconds=<n>`, reads `WATTLANDS_ROOM <code>` from its stdout and starts `client1` and `client2` with `--join=<code>`. Exactly one peer (`--auto-upload`, default `client1`) also gets `--strava-client-id`, `--strava-client-secret` (dummies) and `--strava-auto-upload`.
4. Once `client2` prints `WATTLANDS_STATE running` (or `session`, `playing`, `started`, `warmup`), waits `--kill-after` seconds (25), kills its whole process tree, waits `--restart-delay` (3) and restarts it with the same profile dir and code.
5. Waits for every peer to exit (`--game-timeout`, 660 s, cool-down included), lists the mock's uploads (`--strava-admin`, default: tries `/__admin/uploads`, `/_admin/uploads`, `/admin/uploads`, `/__mock/uploads`, `/_mock/uploads`, `/mock/uploads`), stops both services and runs the checks below.
6. Writes `build/e2e/<id>/report.json`, then runs `node tests/games/<id>/e2e_check.mjs <report path>` if that file exists; a non-zero exit fails the game.

Every child gets `WATTLANDS_NO_HW_CONTROL=1` and `WATTLANDS_NO_NETWORK_INTEGRATIONS=1`, never sees `FAL_KEY` or `WATTLANDS_ALLOW_ART`, and has stdin closed. `--mock-trainer=none` (or any non-mock value), `--allow-hw` and `--allow-network` are refused.

## Checks (each a named entry in `report.checks`)

| Check | Passes when |
| --- | --- |
| `run` | services and peers started, the room code arrived, the victim was killed and restarted, everything finished in time |
| `peers_exit` | the host, `client1` and the restarted `client2` exited 0 |
| `reports` | each wrote its `--report` JSON |
| `script_errors` | no `SCRIPT ERROR`, `Parse Error`, `ERROR:` (push_error), `Debugger Break` or `Ignoring script` in any peer's stdout, stderr or Godot log (the killed run included), and `report.script_errors` is 0 |
| `desync` | `report.desync_warnings` is 0 on every peer and no `WARNING: ... desync` line |
| `rate_limited` | no `rate_limited` in any peer's or the relay's output |
| `same_events` | the shared events (everything except per-peer types such as session states, peer churn, uploads, HUD messages; see `PER_PEER_EVENT_TYPES` in `lib/checks.mjs`) are identical on the host and `client1`, ignoring arrival times; the restarted `client2` holds a tail of the host's sequence (after at most one replayed `phase_started` for itself) that ends with the results; the host's sequence holds `phase_started` and `results` |
| `final_state` | every peer's `final_state` matches the host's within 2 % or 0.01 (per-peer keys such as `local_peer` ignored) |
| `directives_clamped` | every applied directive record is refused with a reason, or carries `applied` values and a `clamped_by` list; host records naming a remote peer have a record with the same id in that peer's report |
| `warmup_limits` | every 1 Hz trace entry in ERG has `applied_pct` <= 65, every SIM entry an `applied_grade_pct` within -2..+3, and so do the applied directive values (BRIEF 4.6.8) |
| `mock_trainer` | every peer ran with `--mock-trainer=` |
| `strava_upload` | the mock holds exactly one upload, the auto-upload peer reports one finished upload and the others none |
| `reconnect` | the victim printed the same `WATTLANDS_PEER` id before the kill and after its restart, was not refused with `session_in_progress`, exited 0 and got the results |
| `fit_files` | every peer's `fit_paths` exist and pass `node tools/fit_check/check.mjs <files> --json` (or `--fit-check-cmd`; without check.mjs, `tools/fit_decode/decode.gd` through `tools/godot.sh` inside the lease) |
| `duration` | wall time minus the cool-down (the host's `WATTLANDS_STATE cooldown` until its next state, else `--cooldown-s`) is <= `--max-duration` (360 s) |
| `e2e_check` | the game's `tests/games/<id>/e2e_check.mjs` exited 0 (only when it exists) |

## report.json

```
{schema: 1, game_id, content_id, seed, room, ok, failures: [String], checks: [{name, ok, details}],
 timings: {started, relay_ready_s, strava_ready_s, room_s, victim_running_s, kill_s, restart_s,
           peers_done_s, total_s, cooldown_observed_s, duration_excl_cooldown_s, uploads_query},
 services: {relay: {url, cmd, log}, mock_strava: {base, cmd, log, uploads}},
 auto_upload_peer, victim,
 peers: {host|client1|client2: {role, peer_id, exit_code, exit_reason, states, report_path, stdout_log,
         godot_log, cmdline (secrets masked), events, directives, trace, fit_paths, uploads, final_state,
         desync_warnings, script_errors, log_errors, restarted, earlier_runs: [...], auto_upload}},
 events_by_peer: {<peer id>: [events in arrival order]},   // host: sent; clients: applied
 directives: [{peer_role, ...applied record}],
 fit_paths: {host|client1|client2: [paths]},
 fit_check: {host|client1|client2: {ok, code, label, json, errors}},
 e2e_check: {path, exit_code, timed_out, output} | null}
```

A game's `e2e_check.mjs` reads `events_by_peer` (or `peers.<role>.events`) to assert its own events, for example one landed mackerel per rider. It may import the helpers in `tools/e2e/lib/checks.mjs` (`comparableEvents`, `eventType`, `checkWarmup`, ...).

## Exit codes

0 every game passed, 1 a game failed, 2 usage error (unknown game, bad option, no mock trainer), 75 Godot lock wait timeout.
