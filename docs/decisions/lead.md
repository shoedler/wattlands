# Lead decisions

## 2026-10-21: Godot binary is Simon's .NET 4.7.2 build

- Decision: run and test with `C:\Projects\.tooling\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe` (reports `4.7.2.stable.mono.official.ed1daf0bf`). The wrappers resolve `$GODOT`, then `tools/godot_bin.local` (gitignored, machine-local) in this or the main checkout, then `godot` on PATH.
- Alternatives: download the standard build (BRIEF 2); require `GODOT` in every shell.
- Reason: the user named this binary for running and testing; BRIEF 2 allows a .NET build for that. Exports need the standard build's export templates (BRIEF 7.10), documented in the README.

## 2026-10-21: Frozen W0 stubs for cross-module classes

- Decision: besides `addons/wattlands/contracts/`, W0 wrote stub files with frozen public signatures for every class another module calls (governor, LocalRider, GameHost, NetSession, registry, HUD layer, pedal-scan list, pixel viewport, ...). Owners fill the bodies and may add API, never change it.
- Alternatives: contracts as abstract base classes only; let each W1 agent design its own API and reconcile in W2.
- Reason: 15 builders work in parallel; a frozen, documented call surface keeps W2 merges mechanical.

## 2026-10-21: Autoload classes are named Wl<Name>

- Decision: autoload `X` is an instance of `class_name WlX` (`WlEventBus`, `WlNetSession`, ...).
- Alternatives: no class_name on autoload scripts.
- Reason: Godot refuses a script class with an autoload's name; named classes let tests and in-process simulations create private instances (one EventBus and NetSession per simulated peer).

## 2026-10-21: Two clocks, fixed steps, no wall clock in rules

- Decision: one `SimClock` drives platform time (always runs: trainer, governor, mock riders, telemetry) and game time (stops on pause: `sim_step`, phase elapsed, directive expiry). Real-time play feeds wall deltas to `SimClock.advance`; headless runs call `step()`.
- Alternatives: `_process` deltas everywhere; `Engine.time_scale`.
- Reason: BRIEF 3.6 and 6 demand fixed 0.05 s steps and determinism; BRIEF 4.1 needs trainer I/O to keep running while the game is paused.

## 2026-10-21: Game events go through GameModule.game_event

- Decision: `GameModule` gets an additive `signal game_event(event)` and `send_event(event)`; the GameHost batches events (at most 10 messages per second), sends them in order and calls `apply_event` on clients only. Every event has a `"type"` key, which `int_fields()` uses.
- Alternatives: `ctx.events` (the EventBus) for game events.
- Reason: BRIEF 3.6 names `apply_event` but no emitter; the game briefs need ordered, batched events.

## 2026-10-21: PlayerSlot field names

- Decision: the FTP field is `ftp` (watts); the Autopilot flag is `autopilot`; the look fields are `color`, `shape`, `pattern`, `hollow`. Backticked BRIEF names are kept exactly (`ftp_verified`, `p_eff_per_w`, `rider_mass_kg`, `preferred_cadence_rpm`, `haptics_on`, `is_bot`, `options`); `haptic_intensity` is added.
- Reason: the game briefs refer to "the slot's FTP" and "Autopilot flag" without code names.

## 2026-10-21: Window base size and stretch

- Decision: base viewport 1920 x 1080, `canvas_items` stretch with `expand` aspect, window override 1280 x 720 for windowed runs.
- Alternatives: stretch disabled with the HUD scaling itself.
- Reason: HUD sizes are specified at 1080p (BRIEF 3.9); a 640 x 360 PixelViewport stays integer-scaled at 720p, 1080p and 1440p.

## 2026-10-21: Phase kinds, modes and rule names are strings

- Decision: `Wl.WARMUP`, `Wl.ERG`, `Wl.SOLO`, `Wl.CLAMP_*` and friends are String constants.
- Alternatives: GDScript enums.
- Reason: they appear verbatim in JSON content, network messages and run_game_sim reports.

## 2026-10-21: W1 split sdk-runtime into sdk-runtime and sdk-tools (16 builders)

- Decision: BRIEF 8's W1 role sdk-runtime became two builders. sdk-runtime owns `addons/wattlands/sdk/` and `tests/sdk/` (GameRegistry, GameHost, PlanValidator, DirectiveSink, the conformance test). sdk-tools owns the template (`src/games/_template/` and its content, assets and tests), `tools/run_game_sim`, `tools/new_game`, `tools/sdk/`, `tests/tools/` and `docs/GAME_SDK.md`. W1 therefore had 16 builders (`docs/OWNERSHIP.md`); `GameSimRunner.parse_args` (sdk-runtime) stays the one flag parser both sides use.
- Alternatives: one sdk-runtime builder, as the brief lists it.
- Reason: it was the brief's broadest W1 role, and the tools, the template and the SDK guide need only the frozen W0 SDK stubs, so they could be built in parallel with the runtime (the template's unit tests run on recording fakes; its integration tests stayed pending until the runtime landed in W2).

## 2026-10-21: W2 and W4 ran as the lead plus up to 3 helpers

- Decision: W2 (integrate) and W4 (fix and polish) both used BRIEF 8's W2 shape, "you plus up to 3 helpers": each round three area fixers, each in its own worktree and branch, merged into `main` by the lead (W2 rounds: `core`, `sdk`, `app`; W4 rounds: `trainer`, `session`, `app`; for example `merge: w4r2/trainer`). Two rounds each.
- Alternatives: one fixer per module or per finding (W4's "parallel fixers grouped by area" allows more); the lead alone.
- Reason: findings cluster by area, so three fixers own disjoint paths and the merges stay mechanical; more parallel Godot runs would only queue on the machine-wide lock (2 slots, 4 on a large machine).

## 2026-10-21: The GUT gate fails on pending or risky tests (W3 QT-3)

- Decision: `tools/run_tests` (`tools/lib/gut_gate.mjs`) fails when any GUT test is pending or risky (a test with no asserts), counted from the GUT summary's "Risky/Pending" line and the JUnit file, in full and narrow (`--gdir`) runs alike. The only exceptions are environment guards listed in `tests/pending_allowlist.txt` (a test file, or `file::test_name`): today the GDBLE surface tests, which call `pending()` when the GDBLE library isn't loaded.
- Alternatives: GUT's own pass rule (exit 0 with pending tests); a pending-count threshold.
- Reason: GUT exits 0 for pending and risky tests and counts them in JUnit, so a regression that trips a `pending()` guard, or a test that lost its asserts, stayed green. An explicit allowlist keeps the real environment guards visible and reviewable.

## 2026-10-21: --sim-speed only with MockTrainers (W3 SAF-3)

- Decision: a sim speed other than 1 applies only to riders on a `MockTrainer`. `WlTrainerService.effective_sim_speed()` (the menu clock) and `AppSessionLauncher.effective_sim_speed()` (the session clock) return 1 for any other device, and `GameHost.setup()` resets a `sim_speed` other than 1 to 1 when any local rider's device is not a MockTrainer, each with a `push_warning`.
- Alternatives: refuse to start with a real trainer; ignore the flag only above 1; check only in the app.
- Reason: every governor time rule (slew, write rate, rescue, coasting, warm-up, haptics) runs on platform time, so x4 meant 120 W/s slew and 8 writes a second on a real trainer and x0.25 stretched rescue and coasting (BRIEF 4.5, 4.6). The GameHost check also covers tools and tests that build their own GameHost.

## 2026-10-21: A Windows export tool (W3 PKG-1, PKG-4, PKG-5)

- Decision: `node tools/export_windows.mjs` exports the Windows Desktop preset into `build/windows/` from a clean copy of the tracked files (`build/export_src`), so the working tree is never touched. With a .NET editor (Simon's) it points the copy's preset at the standard `windows_release_x86_64.exe` as a custom template (`--template`, or the installed `<version>.stable` export templates), because a .NET editor looks for .NET templates. It writes `LICENSE.txt`, `CREDITS.md` and `THIRD_PARTY_NOTICES.txt` next to the exe and fails when the GDBLE DLL is missing. `--with-vcruntime` copies `vcruntime140.dll` (and `vcruntime140_1.dll`) from System32 next to the exe, an app-local Visual C++ runtime for the GDBLE DLL. `--smoke` runs the exported console exe headless with a mock trainer for 8 s, locks set and a temp profile, and fails on a non-zero exit or a script error. Godot runs take the machine-wide lock.
- Alternatives: export from the working tree with the editor's own templates; install the standard editor only for exports; ship the VC++ redistributable installer or require it.
- Reason: BRIEF 7.10 needs a Windows build that ships the GDBLE DLL, and Simon's editor is the .NET build. The notices travel with the exe. A fresh PC without the VC++ runtime shows no trainers, so the README names the redistributable and the app-local copy stays opt-in. The smoke run checks the exported build itself, not the source tree.

## 2026-10-21: Atkinson Hyperlegible and CC0 audio stay BRIEF 3.9 fallbacks

- Decision: v0.1.0 ships Godot's default font and synthesized sound, BRIEF 3.9's fallbacks (as the ui-hud ADRs chose in W1). The font is a drop-in: put `AtkinsonHyperlegible-Regular.ttf` and `AtkinsonHyperlegible-Bold.ttf` with `OFL.txt` in `addons/wattlands/ui/theme/fonts/`, record them in `docs/deps.d/` and the credits, and import; `WlTheme` switches with no code change (`addons/wattlands/ui/theme/fonts/README.md`). Recorded sounds can replace a built-in through `Sfx.register(name, stream)`, with a credit.
- Alternatives: download the font and a CC0 pack during the build.
- Reason: downloading files needs Simon's explicit approval in chat, which an unattended run can't get; BRIEF 3.9 names both fallbacks.

## 2026-10-21: The lead CI workflow runs the full tools/run_tests

- Decision: `.github/workflows/lead.yml` runs every BRIEF 7 gate in one job on every push and pull request, as `tools/run_tests` runs them locally: ubuntu-latest, Godot 4.7.2's Linux build, Node 22, gdtoolkit 4.5.0 from pipx, both locks set. That covers the import, the full GUT suite, the scaffold check, `check_scripts`, the game sims with `fit_check`, the Node suites and the 3-peer end-to-end test. The logs are kept as an artifact. The module workflows keep their narrower suites.
- Alternatives: the module workflows only; one job per gate.
- Reason: each module workflow runs only its own part, so no CI job ran the command that decides green. It installs gdtoolkit 4.5.0 so the static gate's gdlint and gdformat --check run, as they do locally.
## 2026-10-21: gdformat and gdlint are part of the static gate, configured by ./gdlintrc

- Decision: every .gd under `addons/wattlands/`, `src/`, `tests/` and `tools/` is formatted with gdformat (gdtoolkit 4.5.0, its default 100 columns). The static step of `tools/run_tests` fails on any gdlint problem and on any file `gdformat --check` would change whenever gdtoolkit 4.5.0 is available (`gdlint` and `gdformat` on PATH reporting 4.5.0, else `uvx --from gdtoolkit==4.5.0`). Without it the step still passes with "gdtoolkit unavailable, skipped"; `--no-lint` skips lint; `--strict-lint` is a no-op kept for old command lines. `./gdlintrc` is gdlint's default config (`gdlint --dump-default-config`) with `class-definitions-order` disabled, `max-line-length` 120, `max-public-methods` 100, `max-returns` 25 and `max-file-lines` 3000; every naming rule stays, and findings are fixed in code, never with `# gdlint: disable`.
- Alternatives: keep lint reported but non-fatal (docs/decisions/tooling.md); gdlint's defaults (100 columns, 20 public methods, 6 returns, 1000 lines, the fixed member order); format only new files.
- Reason: a style gate that only reports never converges (2214 gdlint problems and 337 unformatted files when this landed), and game sessions copy the template, so it has to be clean. `class-definitions-order`: our files group members by role (a constant or signal next to the code that uses it, test helpers next to their tests), which a fixed order would scatter. 120 columns: gdformat wraps code at 100 but can't split comments, long string literals or regexes. 100 public methods: the SDK facades (GameHost, NetSession, SafetyGovernor, LocalRider, HudLayer, the app screens) have wide, documented APIs. 25 returns: validators and CLI parsers return one error per check, which reads best as early returns. 3000 lines: NetSession, GameHost, SafetyGovernor and the lobby screen are long and cohesive; splitting them for the linter would hurt.
- Consequences: gdformat 4.5.0 has bugs Godot exposes. A lambda too long for one line, nested in a call or collection, is wrapped into a form Godot rejects ("Unindent doesn't match the previous indentation level") and can duplicate the file's comments into it; a comment above a dictionary entry it expands can move into the entry; a string literal with a raw line break stops gdtoolkit. The formatting pass replaced such lambdas with methods or local variables, put moved comments back and wrote `\n`; CLAUDE.md lists the pitfalls. `tests/tools/test_template_size.gd` now counts logical lines (a statement wrapped inside brackets counts once): with game.json the formatted template is 452 physical lines but 296 logical ones (295 before formatting), so BRIEF 3.6's "under 300 lines" keeps measuring the code, not the formatter. A game fresh from `tools/new_game` needs one gdformat run, since its shorter names let gdformat join a few wrapped lines; new_game's "next:" line, CLAUDE.md and docs/GAME_SDK.md say so.

## 2026-10-22: A final Definition of Done sweep before the v0.1.0 tag

- Decision: after W4's two fixer rounds, the lead ran one read-only sweep of every BRIEF 9 Definition of Done bullet (14 checkers: one per BRIEF area, one for the docs, one per game brief, with three skeptics trying to refute each reported gap). It confirmed 24 gaps. Three were the missing `v0.1.0` tag. The lead fixed seven doc mismatches itself and the gate coverage (the static step parses every CI workflow as YAML through `uv`; the node step runs every `tests/games/<id>/` folder's Node tests; the fit step decodes `build/core_stack_test`). Eight small fixes went to isolated worktrees, each reviewed by a fresh agent and fixed again where the review found a problem:
  - the rescue banner always shows (4.6.3);
  - a mid-ride control loss shows a HUD notice (4.4);
  - no client learns another rider's weight in any scaling mode (3.2);
  - offline uploads never count toward the retry cap (3.8);
  - scenario FITs go to `build/scenarios` for the SDK decode;
  - one shared not_pedaling detector, with edge tests (3.5, 4.6.3, 4.6.4);
  - bots follow a published cadence band (3.6);
  - a Reset to defaults row for bindings and per-session Autopilot scanning (3.5), with over-tall Settings pages scrolling to the highlighted row (3.9);
  - Workout clients interpolate other riders and blend their own toward the host (5.1);
  - an export-time default relay URL (`export_windows --relay-url`), so a joining friend types only the code (DoD 2).

  What stays open is listed under "Known gaps in v0.1.0" in `docs/BACKLOG.md`.
- Alternatives: tag after W4 round 2 and list every sweep finding as a known issue; run a full third W3/W4 cycle.
- Reason: BRIEF 8 caps W4 at two fixer rounds but leaves the lead's closing step: rerun every gate, finish the docs, then tag. Each fix here is small, tested and reviewed, and four of them close BRIEF 3.2, 3.8, 4.4 and 4.6.3 gaps, which shouldn't ship as known issues when they are hours of work. The rest are P1 or design follow-ups, recorded rather than built.
