# tools/e2e: the multiplayer end-to-end test

`node tools/e2e/run.mjs --games=<id>[,<id>...]` plays each listed game's `e2e_content` with one host and two clients (BRIEF 3.6, 7.7). Zero npm dependencies; `node --test tools/e2e/test` runs its own tests with stand-ins for Godot, the relay, the mock Strava server and the FIT checker (`tools/e2e/fixtures/`).

## What one game's run does

1. Takes one lease of 3 Godot slots from the machine-wide lock (`tools/lib/godot_lock.mjs`) for the whole run. Every peer runs through `tools/godot.sh` with `WATTLANDS_GODOT_LEASE_TOKEN`, so it never queues again; the restarted client reuses the killed one's slot. A lock wait timeout exits 75 and starts nothing.
2. Starts the relay (`--relay-cmd`, default `node server/relay/src/main.ts`, or `node --experimental-strip-types server/relay/src/main.ts` on a Node without default type stripping (22.12–22.17, 23.0–23.5), with `PORT=<free port>` and `HOST=127.0.0.1`; `{port}` and `{pid}` in the command are replaced) and waits for `GET /health`; starts the mock Strava server (`--strava-cmd`, default `node server/mock_strava/server.mjs --port=0 --parent-pid=<harness pid>`; the port comes from its `MOCK_STRAVA_PORT <port>` line, or a line naming a URL, `port N` or `{"port": N}`).
3. Starts the host headless: `tools/godot.sh --timeout=<s> --headless --path <repo> --log-file <peer dir>/godot.log -- --host --content=<e2e_content> --game=<id> --e2e --wait-peers=3 --relay=ws://127.0.0.1:<port>/v1 --mock-trainer=erg:compliance=1.0 --autopilot --profile-dir=<peer dir>/profile --sim-speed=1 --seed=<n> --report=<peer dir>/report.json --strava-base=http://127.0.0.1:<port> --run-seconds=<n>`, reads `WATTLANDS_ROOM <code>` from its stdout and starts `client1` and `client2` with `--join=<code>`. Exactly one peer (`--auto-upload`, default `client1`) also gets `--strava-client-id=12345`, `--strava-client-secret=mock-client-secret` (the mock's default test client; masked in logs and the report) and `--strava-auto-upload`.
4. Once `client2` prints `WATTLANDS_STATE running` (or `session`, `playing`, `started`, `warmup`), waits `--kill-after` seconds (25), kills its whole process tree, waits `--restart-delay` (3) and restarts it with the same profile dir and code.
5. Waits for every peer to exit (`--game-timeout`, 660 s, cool-down included), lists the mock's uploads (`--strava-admin`, default: tries `/admin/uploads`, then `/__admin/uploads`, `/_admin/uploads`, `/__mock/uploads`, `/_mock/uploads`, `/mock/uploads`), stops both services and runs the checks below.
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
| `same_events` | the shared events (everything except per-peer types such as session states, peer churn, uploads, HUD messages; see `PER_PEER_EVENT_TYPES` in `lib/checks.mjs`) are identical on the host and `client1`, ignoring arrival times (and the `peer` of a `results` event, which names the peer that recorded it); the restarted `client2` holds a tail of the host's sequence that ends with the results, apart from at most one replayed `phase_started` for itself (a phase the host started, among its first 8 events after the rejoin); the host's sequence holds `phase_started` and `results` |
| `final_state` | every peer's `final_state` matches the host's within 2 % or 0.01 (per-peer keys such as `local_peer`, `fit_path`, `distance_m` and `phase_index` ignored; see `PER_PEER_STATE_KEYS`) |
| `directives_clamped` | every applied directive record is refused with a reason, or carries `applied` values and a `clamped_by` list; host records naming a remote peer have a record with the same id in that peer's report |
| `warmup_limits` | every 1 Hz trace entry in ERG has `applied_pct` <= 65, every SIM entry an `applied_grade_pct` within -2..+3, and so do the applied directive values (BRIEF 4.6.8) |
| `mock_trainer` | every peer ran with `--mock-trainer=` |
| `strava_upload` | the mock holds exactly one upload and accepted it (`fit_valid`, `data_type` fit, `trainer` 1, no `error`, where the mock reports them), the auto-upload peer reports one finished upload with the same activity id and the others none |
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

# tools/e2e/faults.mjs: the multiplayer failure paths

`node tools/e2e/faults.mjs [--games=a,b] [--scenarios=x,y]` proves what happens when a room goes wrong, with real headless peers (`tools/godot.sh`, `--mock-trainer=erg:compliance=1.0 --autopilot --sim-speed=1 --e2e --wait-peers=2`, a fresh `--profile-dir` per peer under `build/e2e_faults/<scenario>/`). `run.mjs` plays one good session and kills one client inside the hold window; `faults.mjs` kills and refuses things on purpose, on the built-in relay and on `server/relay`. Zero npm dependencies. `--help` lists the options (`--run-seconds`, `--kill-after`, `--end-timeout`, `--long-timeout`, `--relay-cmd`, `--lock-timeout`, `--jobs`, `--peer-cmd`, `--verbose`).

The built-in relay is what a host without `--relay` uses: `WlNetSession` hosts on the host's own PC through `LanTransport`, and a client finds the room from UDP beacons by its code. While the network lock is set it binds and beacons on 127.0.0.1 only. The harness gives every peer of such a scenario one free TCP port (`--lan-port`, host only) and one free UDP port (`--lan-discovery-port`, every peer), so scenarios never meet. A client stops listening once it found its room, so only one client at a time searches a discovery port: the scenarios start their clients one after another.

Each scenario takes one lease of the machine-wide Godot lock (2 slots, 3 for `late_join`) and its peers run inside it, as in `run.mjs`. Nothing is shared between scenarios, so `--jobs=<n>` runs up to n of them at once: the four long ones start first, each still waits for its own lease, and the report lists the scenarios in run order. `getFreePort` never hands out one port twice in a run, so a relay restarted on its own port keeps it.

## Scenarios

| Scenario | What it does | Passes when |
| --- | --- | --- |
| `builtin:<game>` (fishing, siege, tank, workout) | host without `--relay`, one client joins by code over beacons, the session starts, the client is killed `--kill-after` s into it and restarted `--restart-delay` s later with the same profile; `--run-seconds` (70) ends it | both reached the session, the restarted client has the same `WATTLANDS_PEER` id and was not refused, the host exits 2 (`run_seconds`), the client 2 (or 4, `host_left`), no script or push_error lines, a report on each, a valid FIT on the host and the restarted client |
| `wrong_code:relay`, `wrong_code:builtin` | a real room waits in its lobby; a client joins `ZZZZZZ` | the client exits 3 with reason `refused:room_not_found`, no error lines, and the real room's host is still running afterwards |
| `late_join:relay`, `late_join:builtin` | a third peer with a fresh profile joins a running room (workout) | it exits 3 with `refused:session_in_progress`; the host and first client are still riding 5 s later, end at `--run-seconds` with no error and a FIT each |
| `relay_dies` | workout on `server/relay`, relay killed `--kill-after` s into the session and left dead | the peers retry for the token's 120 s; the client then rides the plan's cool-down here (`WATTLANDS_STATE cooldown`) and exits 3 `refused:dropped` with its FIT (about 300 s after the kill); the host carries on alone to its results and exits 0 `complete` (about 295 s); no error lines, no warning flood |
| `relay_restarts` | the same, but the relay is started again on its port 2 s later, so its rooms are gone | the client's rejoin gets `room_not_found`: it rides the cool-down at once (about 180 s later) and exits 3 `refused:room_not_found` with its FIT; the host's rejoin fails the same way, it carries on alone and exits 0 `complete` |
| `host_killed_relay` | host killed in the session on the relay (it holds the room 120 s, then sends `host_left`) | the client exits 4 `host_left` with its FIT 120 s after the kill (a client ends at once on `host_left`, like the session screen; no cool-down) |
| `host_killed_builtin` | host killed on the built-in relay, which dies with it | nobody holds the room: the client retries 120 s, rides the cool-down and exits 3 `refused:dropped` with its FIT, about 300 s after the kill (the `timing` check says how long) |

Error lines are matched like `run.mjs` does (`SCRIPT ERROR`, `Parse Error`, `ERROR:` push_error, `Debugger Break`, `Ignoring script`) over each peer's stdout, stderr and Godot log; a scenario may allow named patterns (`EXPECTED_ERRORS` in `lib/fault_scenarios.mjs`, empty today) and the report says how many lines were ignored. Desync warnings and `rate_limited` fail a scenario too.

`relay_dies`, `relay_restarts`, `host_killed_relay` and `host_killed_builtin` play the whole 2 minute workout and ride out the 120 s reconnect window and the 180 s cool-down: expect 5 to 6 minutes each. One after another the whole set takes over half an hour; with `--jobs=4` it takes about as long as the longest scenario plus the short ones beside it. Without `--jobs`, run them one by one with `--scenarios=` when a shell call is limited to 10 minutes.

## report.json

`build/e2e_faults/report.json`: `{schema: 1, started, ok, games, scenarios: [{name, ok, failures: [String], checks: [{name, ok, details}], evidence: {duration_s, out_dir, timeline: [{t, text}], relays, lan: {port, discoveryPort}, peers: [{name, role, exit_code, exit_reason, done_line, peer_id, room, states, started_s, exited_s, report_path, stdout_log, godot_log, cmdline, error_lines, script_errors, desync_warnings, fit_paths, fit_check, report_error}]}}], pending: [names not run]}`. The report is rewritten after every scenario.

## Exit codes

0 every scenario passed, 1 one failed (or none ran), 2 usage error, 75 Godot lock wait timeout.

## Tests

`node --test tools/e2e/test` covers the harness's pure logic in `test/fault_scenarios.test.mjs` (the command line, the peer flags, a peer's outcome from fake output, each scenario check and the run verdict) and the `--jobs` pool in `test/faults_pool.test.mjs`. The scenarios themselves need Godot; the lead runs them.
