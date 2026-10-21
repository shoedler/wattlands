class_name GameHost
extends Node
## Owns a session around a game on one peer (BRIEF 3.6): plan validation, the sim clock,
## routing directives to each rider's governor, warm-up and cool-down, pause, rescue and AFK
## callbacks, telemetry, snapshots and events over the network, the ride recorder and its
## laps, and results. Runs in SOLO, HOST and CLIENT roles. Owned by sdk-runtime; public API
## frozen after W0. Runs with PROCESS_MODE_ALWAYS.
##
## Host/SOLO per fixed step: tick every local rider (own rider + bots) -> merge remote
## telemetry (stale > 3 s keeps age_s; dropped peers connected = false, power/cadence 0) ->
## local_intents + autopilot_intents -> InputFrame -> game.sim_step(dt, frame) -> phase
## tracking per rider (duration, max_s, end_phase, finished -> skip to cool-down) with
## EventBus.phase_started(peer, index) and `phase` messages -> snapshot at 10 Hz, roster at
## 2 Hz, batched events -> after the cool-down: results() -> `results` to all ->
## apply_progress on every peer -> results screen.
## Client per fixed step: tick its LocalRider, apply plan/phase/directive messages to it,
## send telemetry (with intents, gestures, acks) at 5 Hz, apply snapshots/events, call
## client_predict.
## Real-time play advances by SimClock.advance(wall delta) in _process; headless runs call
## step() directly (GameSimRunner).
##
## One step(), in order: poll the net session and apply the queued messages (telemetry,
## drops and rejoins on the authority; session_start, plan, phase, directive, event,
## snapshot, roster, hud, results on a client) -> tick every local rider on platform time ->
## drain gestures (the local rider's from the InputRouter when rendering, else from its
## LocalRider; bots' from their LocalRiders) and actions (InputRouter or inject_action;
## `pause` and `panic` are consumed here, as is a `confirm` that resumes a paused session
## while config.platform_pause is on; the InputRouter's `pause` (and its `confirm` while
## paused) is always dropped, because the app's session screen owns pausing;
## shift_up/shift_down also shift the gears) ->
## local_intents(actions, gestures) on every peer -> authority: unless paused, build the
## InputFrame (frame.tick/t = game ticks/seconds completed before this tick), call
## on_rescue/on_afk on edges, sim_step(0.05, frame), feed ctx.stats, advance phases (a
## change: LocalRider.set_plan/start_phase or `plan`/`phase` messages, EventBus.phase_started,
## a "wl.phase_started" event; cool-down: bands cleared), deliver coalesced course grades,
## flush events then a snapshot every 2nd platform tick, results once every rider finished
## its cool-down (complete_rows: a row per rider); client: client_predict, telemetry every
## 4th platform tick -> roster every
## 10th platform tick, report trace every 20th -> HUD update -> the clock steps.
##
## Wire formats (all through Protocol.game_msg and the WlNetSession):
##   session_start {game_id, game_version, content_id, seed, players: [PlayerSlot.to_dict()],
##     options, scaling, start_tick, session_id, content_overrides, game, content, session}
##     (game/content/session repeat the string ids without the "_id" suffix)
##   plan {peer, plan: EffortPlan.to_dict()}; phase {peer, index, start_tick, ended_by}
##   directive {kind: request, id, peer, directive: EffortDirective.to_dict()} |
##     {kind: course_grade, id, peer, grade_pct} | {kind: cadence_band, id, peer, lo_rpm,
##     hi_rpm} | {kind: power_band, peer, lo_w, hi_w}
##   event {seq, events: [game events and platform events whose type starts with "wl.":
##     wl.phase_started {peer, index, ended_by}, wl.lap_marker {label}, wl.finished {reason}]}
##   snapshot {game_id, seq, tick, state}; roster {riders: {peer: {...}}};
##   hud {kind: toast|banner, key, args, seconds}; results {results}; session_end {reason};
##   telemetry {tm: Telemetry.to_dict()} (client -> host).
## Game event types starting with "wl." are reserved for the platform.

## "setup", "running", "paused", "cooldown", "results", "ended".
signal state_changed(state: String)
signal session_finished(results: GameResults)

const DT := Wl.SIM_DT
## Platform ticks between client telemetry messages (5 Hz).
const TELEMETRY_EVERY := 4
## Platform ticks between event flushes and snapshots (10 Hz).
const SNAPSHOT_EVERY := 2
## Platform ticks between rosters (2 Hz).
const ROSTER_EVERY := 10
## Platform ticks between report trace rows (1 Hz).
const TRACE_EVERY := 20
## Fresh telemetry "shows pedaling" (BRIEF 3.5's not_pedaling, inverted).
const PEDAL_POWER_W := 15.0
const PEDAL_CADENCE_RPM := 20.0
const PLATFORM_EVENT_PREFIX := "wl."

var ctx: GameContext = null
var game: GameModule = null
var clock: SimClock = null
## peer_id -> LocalRider for riders simulated on this machine.
var local_riders: Dictionary = {}
var state: String = "setup"

# --- additive public state (sdk-runtime) ------------------------------------------------
var role: String = Wl.SOLO
var config: Dictionary = {}
## This peer's EventBus (config.bus, else the autoload, else a private instance).
var bus: WlEventBus = null
var net: WlNetSession = null
var registry: WlGameRegistry = null
## The game's validated game.json.
var manifest: Dictionary = {}
## peer -> finalized EffortPlan (authority: every rider; client: its own).
var plans: Dictionary = {}
## peer -> Array of PlanValidator warnings.
var plan_warnings: Dictionary = {}
var tracker: PhaseTracker = null
var directive_router: DirectiveRouter = null
var hud_router: HudRouter = null
var intent_router: IntentRouter = null
var stats: SessionStatsTracker = null
## Report data (config.report); null otherwise.
var report: ReportCollector = null
var results: GameResults = null
var finished_reason: String = ""
## "complete", "timeout", "paused", "host_left", ... once the session ended.
var end_reason: String = ""
var session_id: String = ""
## The local rider's new unlocks from apply_progress.
var unlocks: Array = []

var _setup_ok: bool = false
var _headless: bool = true
var _realtime: bool = false
var _platform_pause: bool = true
var _record_rides: bool = true
var _local_peer: int = 0
var _input_router: Node = null
var _injected_actions: Array[StringName] = []
var _players: Array[PlayerSlot] = []
var _slots: Dictionary = {}
var _order: Array[int] = []
## peer -> {tm, rx_t, gestures, intents, dropped, await_pedal, seen}
var _remote: Dictionary = {}
var _inbox: Array = []
var _rescue: Dictionary = {}
var _afk: Dictionary = {}
var _frame_tm: Dictionary = {}
var _event_queue: Array = []
var _event_seq: int = 0
var _snapshot_seq: int = 0
var _last_snapshot_msg: Dictionary = {}
var _last_snapshot_state: Dictionary = {}
var _state_before_pause: String = "running"
## Why the session is paused ("user", "coasting", "stop_5s", ...; "" while running).
var _pause_reason: String = ""
var _progress_done: Dictionary = {}
var _fit_paths: Dictionary = {}
var _view_root: Node = null
var _pixel_viewport: PixelViewport = null
var _hud_layer: HudLayer = null
# client side
var _configured: bool = false
var _pending_gestures: Array[StringName] = []
var _client_plan: EffortPlan = null
var _client_phase: int = -1
var _client_phase_ticks: int = 0
var _client_phase_start_tick: int = 0
var _client_prev_ended_by: String = ""
var _client_cadence: Array = [0.0, 0.0]
var _snap_seq_applied: int = 0
var _event_seq_applied: int = 0
var _pending_snapshot: Variant = null
var _int_fields: Dictionary = {}


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not _realtime or clock == null:
		return
	var n := clock.advance(delta)
	for i in n:
		step()


## Prepare a session. config keys:
##   game_id, content_id, seed (int), role (Wl.SOLO/HOST/CLIENT), players
##   (Array[PlayerSlot]), local_riders ({peer: LocalRider}, bots included on the host),
##   local_peer (int), net (WlNetSession or null for SOLO), bus (WlEventBus; default the
##   autoload), options (Dictionary), scaling_mode, sim_speed (float, default 1),
##   headless (bool: no view/HUD nodes), view_parent (Node), hud_parent (Node),
##   record_rides (bool, default true), report (bool: collect the run_game_sim report data).
## Additive keys: registry (WlGameRegistry; default the autoload), manifest (Dictionary, a
##   game.json used instead of a registry lookup), game (a GameModule instance to use),
##   content_dir (res:// folder for ctx.content_dir), progress_path (the local rider's
##   progress.json; default Paths.progress_path(game_id)), content_overrides
##   ({rel path: merge patch} for ctx.content_overrides), fit_paths ({peer: path}: move each
##   local rider's FIT there after finish_ride), input_router (Node with take_actions() and
##   take_gestures(), optionally attach_rider(rider) and detach_rider(); default the
##   InputRouter autoload unless headless; when rendering, the local rider's gestures come
##   from it; its `pause`, and its `confirm` while paused, are always dropped: the app's
##   session screen owns them), sfx (Node with set_metronome(); default the Sfx autoload),
##   realtime (bool: _process drives the clock with the wall-clock delta; default true,
##   headless or not: GameSimRunner and tests pass false and call step()), poll_net
##   (bool, default true: step() polls the net session), platform_pause (bool, default
##   true: an injected `pause` toggles the pause, and a `confirm`, or `pedal_start` after a
##   pause that was not the rider's own, resumes it; false: the GameHost never pauses or
##   resumes on actions or gestures and the app calls pause()/resume() itself; either way
##   the SOLO coasting and stop_5s pause, LocalRider.pause_requested, still pauses, BRIEF
##   4.6.4). A CLIENT's game, players, options and seed come from the host's session_start:
##   config.session_start (the message that opened the session, which the app shell received
##   before this GameHost existed) is applied on the first step(), else the first
##   session_start from the net.
## Returns "" on success or an error string (invalid plan, unknown game, ...).
func setup(p_config: Dictionary) -> String:
	if clock != null:
		return "setup: already set up"
	config = p_config
	role = str(config.get("role", Wl.SOLO))
	if role != Wl.SOLO and role != Wl.HOST and role != Wl.CLIENT:
		return "role: must be SOLO, HOST or CLIENT"
	_headless = bool(config.get("headless", DisplayServer.get_name() == "headless"))
	# The app (windowed or a headless scripted peer) is driven by _process; GameSimRunner and
	# tests step it themselves and pass realtime = false.
	_realtime = bool(config.get("realtime", true))
	_platform_pause = bool(config.get("platform_pause", true))
	_record_rides = bool(config.get("record_rides", true))
	bus = config.get("bus") as WlEventBus
	if bus == null:
		bus = _autoload("EventBus") as WlEventBus
	if bus == null:
		bus = WlEventBus.new()
		bus.name = "SessionBus"
		add_child(bus)
	net = config.get("net") as WlNetSession
	if role != Wl.SOLO and net == null:
		return "net: HOST and CLIENT need a WlNetSession"
	registry = config.get("registry") as WlGameRegistry
	if registry == null:
		registry = _autoload("GameRegistry") as WlGameRegistry
	clock = SimClock.create(float(config.get("sim_speed", 1.0)))
	var lr: Variant = config.get("local_riders", {})
	if lr is Dictionary:
		for k: Variant in (lr as Dictionary).keys():
			var rider := (lr as Dictionary)[k] as LocalRider
			if rider != null:
				local_riders[int(k)] = rider
	var default_peer := Wl.HOST_PEER
	if role == Wl.CLIENT and net != null:
		default_peer = net.local_peer
	_local_peer = int(config.get("local_peer", default_peer))
	_input_router = config.get("input_router") as Node
	if _input_router == null and not _headless:
		_input_router = _autoload("InputRouter")
	if bool(config.get("report", false)):
		report = ReportCollector.new()
	_make_routers()
	_connect_net()
	_connect_riders()
	if not bus.panic_requested.is_connected(_on_panic):
		bus.panic_requested.connect(_on_panic)
	if not bus.cadence_band_changed.is_connected(_on_cadence_band_changed):
		bus.cadence_band_changed.connect(_on_cadence_band_changed)
	var own: LocalRider = local_riders.get(_local_peer)
	if _input_router != null and own != null and _input_router.has_method("attach_rider"):
		_input_router.call("attach_rider", own)
	if role == Wl.CLIENT:
		_queue_session_start(config.get("session_start", {}))
		_setup_ok = true
		return ""
	var err := _setup_authority()
	_setup_ok = err == ""
	return err


## Host/SOLO: build and validate plans, send session_start/plans, start the clock.
## Client: wait for session_start/plan messages.
func start() -> void:
	if role == Wl.CLIENT:
		return
	if not _setup_ok or game == null or state != "setup" or tracker.is_started():
		push_warning("GameHost: start() needs a successful setup()")
		return
	if net != null:
		net.mark_started()
		_broadcast(Protocol.game_msg("session_start", _session_start_payload()))
		for peer in _order:
			if not local_riders.has(peer):
				_send_to(peer, Protocol.game_msg("plan", {"peer": peer, "plan": (plans[peer] as EffortPlan).to_dict()}))
	_set_state("running")
	_event("session_start", {"role": role, "players": _order.size()})
	for c in tracker.start():
		_on_phase_change(c, true)
	_update_metronome(0.0, 0.0)


## One fixed 0.05 s platform step (headless loops); _process uses the clock in real time.
func step() -> void:
	if clock == null or not _setup_ok:
		return
	_poll_net()
	_process_inbox()
	if role == Wl.CLIENT:
		_client_step()
	else:
		_authority_step()
	clock.step()


func pause(reason: String = "user") -> void:
	if role != Wl.SOLO:
		push_warning("GameHost: pause works in SOLO only (multiplayer riders go AFK instead)")
		return
	if state != "running" and state != "cooldown":
		return
	_state_before_pause = state
	_pause_reason = reason
	clock.set_game_paused(true)
	for peer in _local_order():
		(local_riders[peer] as LocalRider).set_game_paused(true)
	_set_state("paused")
	bus.paused_changed.emit(true, reason)
	_event("paused", {"paused": true, "reason": reason})


func resume() -> void:
	if state != "paused":
		return
	_pause_reason = ""
	clock.set_game_paused(false)
	for peer in _local_order():
		(local_riders[peer] as LocalRider).set_game_paused(false)
	_set_state(_state_before_pause)
	bus.paused_changed.emit(false, "resume")
	_event("paused", {"paused": false, "reason": "resume"})


func is_paused() -> bool:
	return state == "paused"


func is_finished() -> bool:
	return results != null or state == "ended"


## The final results (null until available).
func final_results() -> GameResults:
	return results


## Each local rider's FIT path after the session ({peer: path}).
func fit_paths() -> Dictionary:
	return _fit_paths.duplicate()


## Data for the run_game_sim report (events, phases, directives requested/applied,
## 1 Hz traces, snapshot hashes and sizes); empty unless setup(report = true).
func report_data() -> Dictionary:
	if report == null:
		return {}
	var d := report.to_dict()
	var phases := {}
	var plan_dicts := {}
	var warns := {}
	var peers: Array[int] = _order.duplicate() if not _order.is_empty() else _local_order()
	for peer in peers:
		if tracker.has(peer):
			phases[str(peer)] = tracker.history(peer)
		if plans.has(peer):
			plan_dicts[str(peer)] = (plans[peer] as EffortPlan).to_dict()
		if plan_warnings.has(peer):
			warns[str(peer)] = (plan_warnings[peer] as Array).duplicate()
	d["phases"] = phases
	d["plans"] = plan_dicts
	d["plan_warnings"] = warns
	d["finished_reason"] = finished_reason
	d["end_reason"] = end_reason
	d["role"] = role
	d["local_peer"] = _local_peer
	d["unlocks"] = unlocks.duplicate(true)
	d["game_seconds"] = clock.game_tick * DT if clock != null else 0.0
	d["platform_seconds"] = clock.platform_tick * DT if clock != null else 0.0
	return d


## The view root returned by make_view (inside its PixelViewport for 2D), or null headless.
func view_root() -> Node:
	return _view_root


func end_session(reason: String) -> void:
	if state == "ended":
		return
	if role != Wl.CLIENT:
		if results == null and game != null and tracker.is_started():
			_finish_session(reason)
		if end_reason == "":
			end_reason = reason
		if net != null:
			_broadcast(Protocol.game_msg("session_end", {"reason": reason}))
	else:
		if end_reason == "":
			end_reason = reason
		_save_fits()
	_event("session_end", {"reason": reason})
	_stop_metronome()
	if _input_router != null and _input_router.has_method("detach_rider"):
		_input_router.call("detach_rider")
	_set_state("ended")


# --- additive public API -----------------------------------------------------------------


## Queue an input action for the next step (on-screen buttons and tests; the InputRouter's
## actions are drained the same way).
func inject_action(action_name: StringName) -> void:
	_injected_actions.append(action_name)


## The local rider's peer id.
func local_peer() -> int:
	return _local_peer


## The players in slot order (authority: from setup; client: from session_start).
func players() -> Array[PlayerSlot]:
	return _players.duplicate()


## The newest snapshot state sent (host) or {} (report and rejoin use it).
func last_snapshot() -> Dictionary:
	return _last_snapshot_state


## The local rider's current PhaseState (any role).
func local_phase_state() -> PhaseState:
	if role == Wl.CLIENT:
		return PhaseTracker.make_state(_client_plan, _client_phase, _client_phase_ticks, 0, _client_prev_ended_by)
	return tracker.state(_local_peer)


## The HudLayer built for this session (null headless).
func hud_layer() -> HudLayer:
	return _hud_layer


func pixel_viewport() -> PixelViewport:
	return _pixel_viewport


# --- setup -----------------------------------------------------------------------------


## A client created by the app when the host's session_start arrived (the app shell builds the
## GameHost inside that game_message emission, so the GameHost never sees it on the net): the
## payload from config.session_start is processed on the first step(), before any later
## message. A copy that arrives again over the net is ignored (configured once).
func _queue_session_start(ss: Variant) -> void:
	if not (ss is Dictionary) or (ss as Dictionary).is_empty():
		return
	var msg := (ss as Dictionary).duplicate(true)
	msg["type"] = "session_start"
	_inbox.append([net.host_peer if net != null else Wl.HOST_PEER, msg])


func _make_routers() -> void:
	tracker = PhaseTracker.new()
	intent_router = IntentRouter.new()
	stats = SessionStatsTracker.new()
	directive_router = DirectiveRouter.new()
	directive_router.role = role
	directive_router.tracker = tracker
	directive_router.clock = clock
	directive_router.riders = local_riders
	directive_router.bus = bus
	directive_router.report = report
	directive_router.remote_send = _send_directive
	directive_router.telemetry_of = _latest_telemetry
	directive_router.on_replan = _on_replan
	hud_router = HudRouter.new()
	hud_router.role = role
	hud_router.local_peer = _local_peer
	hud_router.riders = local_riders
	hud_router.bus = bus
	hud_router.report = report
	hud_router.clock_now = _now
	if net != null:
		hud_router.send = _send_or_broadcast
	hud_router.local_status_changed.connect(_on_local_status)


func _setup_authority() -> String:
	var game_id := str(config.get("game_id", ""))
	var m: Variant = config.get("manifest", {})
	manifest = (m as Dictionary).duplicate(true) if m is Dictionary and not (m as Dictionary).is_empty() else {}
	if manifest.is_empty() and registry != null:
		manifest = registry.manifest(game_id)
	if manifest.is_empty():
		return "game_id: unknown game \"%s\"" % game_id
	if not manifest.has("options"):
		manifest = WlGameRegistry.normalized(manifest)
	game_id = str(manifest.get("id", game_id))
	var players := _sorted_players(config.get("players", []))
	if players.is_empty():
		return "players: a session needs at least one rider"
	var seen := {}
	for p in players:
		if seen.has(p.peer_id):
			return "players: peer %d appears twice" % p.peer_id
		seen[p.peer_id] = true
	if not seen.has(_local_peer):
		return "local_peer: %d is not one of the players" % _local_peer
	for peer: int in local_riders.keys():
		if not seen.has(peer):
			return "local_riders: peer %d is not one of the players" % peer
	var content_id := str(config.get("content_id", ""))
	if content_id == "":
		content_id = str(manifest.get("default_content", ""))
	if not WlGameRegistry.content_allowed(manifest, content_id):
		return "content_id: \"%s\" is not one of %s%s" % [content_id, JSON.stringify(manifest.get("contents", [])),
			" or <scheme>:<value> for a scheme in %s" % JSON.stringify(manifest["content_schemes"]) if not (manifest.get("content_schemes", []) as Array).is_empty() else ""]
	game = config.get("game") as GameModule
	if game == null:
		game = WlGameRegistry.instantiate_manifest(manifest)
	if game == null:
		return "entry: cannot instantiate %s" % str(manifest.get("entry", ""))
	if game.get_parent() == null:
		add_child(game)
	var opts_in: Variant = config.get("options", {})
	var options := WlGameRegistry.resolve_option_values(manifest.get("options", []), opts_in if opts_in is Dictionary else {}, game_id)
	for p in players:
		p.options = WlGameRegistry.resolve_option_values(manifest.get("player_options", []), p.options, "%s player %d" % [game_id, p.peer_id])
	var overrides: Variant = config.get("content_overrides", {})
	_init_session(players, content_id, int(config.get("seed", 0)), options,
		str(config.get("scaling_mode", Wl.FAIR_FTP)), overrides if overrides is Dictionary else {})
	game.configure(ctx)
	_connect_game()
	var raw: Variant = game.build_effort_plans()
	if not (raw is Dictionary):
		return "plan: build_effort_plans() must return {peer_id: EffortPlan}"
	for peer in _order:
		var plan: Variant = (raw as Dictionary).get(peer, null)
		if not (plan is EffortPlan):
			return "plan: build_effort_plans() returned no EffortPlan for peer %d" % peer
		var res := PlanValidator.validate(plan)
		if not bool(res["ok"]):
			return "plan for peer %d (%s): %s" % [peer, (_slots[peer] as PlayerSlot).name, "; ".join(res["errors"])]
		var fin := PlanValidator.finalize(plan)
		plans[peer] = fin
		plan_warnings[peer] = (res["warnings"] as Array).duplicate()
		tracker.add_rider(peer, fin)
	_build_presentation()
	return ""


func _init_session(players: Array[PlayerSlot], content_id: String, p_seed: int, options: Dictionary, scaling: String, overrides: Dictionary) -> void:
	_players = players
	_order.clear()
	_slots.clear()
	for p in players:
		_order.append(p.peer_id)
		_slots[p.peer_id] = p
	var game_id := str(manifest.get("id", ""))
	session_id = "%s/%s/%d" % [game_id, content_id, p_seed]
	ctx = GameContext.new()
	ctx.game_id = game_id
	ctx.manifest = manifest.duplicate(true)
	ctx.players.assign(players)
	ctx.content_id = content_id
	ctx.seed = p_seed
	ctx.role = role
	ctx.local_peer = _local_peer
	ctx.rng = SeededRng.make(p_seed)
	ctx.directives = directive_router
	ctx.options = options
	var progress_path := str(config.get("progress_path", ""))
	if progress_path == "":
		progress_path = Paths.progress_path(game_id)
	ctx.progress = ProgressStore.open(game_id, progress_path)
	ctx.hud = hud_router
	ctx.intents = intent_router
	ctx.roster = {}
	ctx.strings = GameStrings.new()
	ctx.events = bus
	ctx.stats = stats
	ctx.scaling_mode = scaling
	var has_reg := registry != null and registry.has_game(game_id)
	ctx.game_dir = registry.game_dir(game_id) if has_reg else str(manifest.get("entry", "")).get_base_dir()
	var cdir := str(config.get("content_dir", ""))
	if cdir == "":
		cdir = registry.content_dir(game_id) if has_reg else WlGameRegistry.CONTENT_ROOT.path_join(game_id)
	ctx.content_dir = cdir
	ctx.assets_dir = registry.assets_dir(game_id) if has_reg else WlGameRegistry.ASSETS_ROOT.path_join(game_id)
	ctx.content_overrides = overrides.duplicate(true)
	directive_router.slots = _slots
	hud_router.slots = _slots
	for p in players:
		stats.add_rider(p.peer_id, p.ftp)
		if not local_riders.has(p.peer_id) and role != Wl.CLIENT:
			_remote[p.peer_id] = {
				"tm": null, "rx_t": 0.0, "gestures": [], "intents": [], "dropped": false,
				"await_pedal": false, "seen": false,
			}
	_int_fields = game.int_fields() if game != null else {}


func _session_start_payload() -> Dictionary:
	var ps: Array = []
	for p in _players:
		ps.append(p.to_dict())
	var game_id := str(manifest.get("id", ""))
	# "game", "content" and "session" repeat the string ids under names without the "_id"
	# suffix, which Protocol.decode may convert to int (net_messages.gd); clients read them first.
	return {
		"game_id": game_id, "game_version": str(manifest.get("version", "")),
		"content_id": ctx.content_id, "seed": ctx.seed, "players": ps, "options": ctx.options.duplicate(true),
		"scaling": ctx.scaling_mode, "start_tick": clock.game_tick, "session_id": session_id,
		"content_overrides": ctx.content_overrides.duplicate(true),
		"game": game_id, "content": ctx.content_id, "session": session_id,
	}


## A string id from a host message: the suffix-free copy ("game") when present, else the
## "_id" field, unless that came back as a number.
static func _string_field(data: Dictionary, plain: String, with_id: String, fallback: String = "") -> String:
	var v: Variant = data.get(plain, null)
	if v is String:
		return v
	v = data.get(with_id, null)
	if v is String:
		return v
	return fallback


func _connect_game() -> void:
	if role == Wl.CLIENT or game == null:
		return
	game.finished.connect(_on_game_finished)
	game.game_event.connect(_on_game_event)
	game.phase_changed.connect(_on_game_phase_changed)
	game.lap_marker.connect(_on_lap_marker)


func _connect_net() -> void:
	if net == null:
		return
	net.game_message.connect(_on_net_message)
	net.peer_left.connect(_on_net_peer_left)
	net.rejoin_requested.connect(_on_net_rejoin)
	net.refused.connect(_on_net_refused)


func _connect_riders() -> void:
	var rider: LocalRider = local_riders.get(_local_peer)
	if rider != null and not rider.pause_requested.is_connected(_on_pause_requested):
		rider.pause_requested.connect(_on_pause_requested)


func _build_presentation() -> void:
	if _headless or game == null:
		return
	var view := game.make_view()
	if view != null:
		var parent := config.get("view_parent") as Node
		if parent == null:
			parent = self
		if str(manifest.get("presentation", "2d")) == "2d" and view is Node2D:
			_pixel_viewport = PixelViewport.new()
			_pixel_viewport.name = "PixelViewport"
			var pb: Variant = manifest.get("pixel_base", [640, 360])
			if pb is Array and (pb as Array).size() == 2:
				_pixel_viewport.pixel_base = Vector2i(int(pb[0]), int(pb[1]))
			parent.add_child(_pixel_viewport)
			_pixel_viewport.set_game_view(view as Node2D)
			if view.get_parent() == null:
				_pixel_viewport.add_child(view)
		else:
			parent.add_child(view)
		_view_root = view
	_hud_layer = HudLayer.new()
	_hud_layer.name = "HudLayer"
	var hp := config.get("hud_parent") as Node
	if hp == null:
		hp = self
	hp.add_child(_hud_layer)
	_hud_layer.build(game.hud_spec(), ctx, _pixel_viewport)


# --- authority step ----------------------------------------------------------------------


func _authority_step() -> void:
	if state == "setup" or state == "ended":
		return
	var gestures := {}
	for peer in _local_order():
		var r: LocalRider = local_riders[peer]
		r.tick(DT)
		gestures[peer] = _local_gestures(r) if peer == _local_peer else _take_gestures(r)
		# Riders simulated here already reported through apply_directive's return value;
		# their ack queue (meant for Telemetry.acks) is drained so it never grows.
		r.take_acks()
	var actions := _take_actions()
	var running := state == "running" or state == "paused" or state == "cooldown"
	if not running:
		return
	var my_gestures: Array[StringName] = []
	my_gestures.assign(gestures.get(_local_peer, []))
	actions = _platform_actions(actions, my_gestures)
	if local_riders.has(_local_peer):
		_call_local_intents(actions, my_gestures)
	var tick := clock.game_tick
	var flush_now := clock.platform_tick % SNAPSHOT_EVERY == 0
	if state != "paused":
		var frame := _build_frame(tick, gestures)
		_detect_edges(frame)
		game.sim_step(DT, frame)
		_feed_stats(frame)
		for c in tracker.advance(tick):
			_on_phase_change(c, false)
		directive_router.flush(tick + 1)
		tracker.update_modes(tick + 1)
		if state == "running" and tracker.all_in_cooldown():
			_set_state("cooldown")
		if flush_now:
			_flush_events()
			_send_snapshot(tick)
		if tracker.all_done():
			_finish_session("complete")
	else:
		for peer in _local_order():
			_frame_tm[peer] = (local_riders[peer] as LocalRider).telemetry()
		if flush_now:
			_flush_events()
	if clock.platform_tick % ROSTER_EVERY == 0:
		_send_roster()
	if report != null and clock.platform_tick % TRACE_EVERY == 0:
		_trace_authority()
	_update_hud()


func _build_frame(tick: int, gestures: Dictionary) -> InputFrame:
	var frame := InputFrame.new()
	frame.tick = tick
	frame.t = tick * DT
	var pt := clock.platform_time()
	for peer in _order:
		var tm: Telemetry
		if local_riders.has(peer):
			var r: LocalRider = local_riders[peer]
			tm = r.telemetry()
			tm.peer_id = peer
			tm.connected = true
			tm.age_s = 0.0
			tm.gestures.assign(gestures.get(peer, []))
			var ints: Array = r.take_intents()
			if peer == _local_peer:
				ints.append_array(intent_router.take())
			tm.intents = ints
		else:
			tm = _remote_frame_telemetry(peer, pt)
		var slot: PlayerSlot = _slots[peer]
		if slot.autopilot or slot.is_bot:
			var ap: Variant = game.autopilot_intents(peer)
			if ap is Array and not (ap as Array).is_empty():
				tm.intents.append_array(ap)
		frame.players[peer] = tm
		frame.phase[peer] = tracker.state(peer)
	_frame_tm = frame.players.duplicate()
	return frame


func _remote_frame_telemetry(peer: int, pt: float) -> Telemetry:
	var r: Dictionary = _remote[peer]
	var tm: Telemetry = (r["tm"] as Telemetry).duplicate_telemetry() if r["tm"] != null else Telemetry.new()
	tm.peer_id = peer
	tm.gestures.assign(r["gestures"])
	tm.intents = (r["intents"] as Array).duplicate(true)
	tm.acks = []
	r["gestures"] = []
	r["intents"] = []
	tm.age_s = pt - float(r["rx_t"])
	tm.cadence_age_s += tm.age_s
	tm.connected = not bool(r["dropped"])
	if bool(r["dropped"]):
		tm.power_w = 0.0
		tm.cadence_rpm = 0.0
		tm.speed_kmh = 0.0
		tm.p_eff_w = 0.0
		tm.afk = true
	elif bool(r["await_pedal"]) or not bool(r["seen"]):
		tm.afk = tm.afk or bool(r["await_pedal"])
	return tm


func _detect_edges(frame: InputFrame) -> void:
	for peer in _order:
		var tm: Telemetry = frame.players[peer]
		if bool(_rescue.get(peer, false)) != tm.rescue:
			_rescue[peer] = tm.rescue
			game.on_rescue(peer, tm.rescue)
			bus.rescue_changed.emit(peer, tm.rescue)
			_event("rescue", {"peer": peer, "active": tm.rescue})
		_set_afk(peer, tm.afk)


func _set_afk(peer: int, afk: bool) -> void:
	if bool(_afk.get(peer, false)) == afk:
		return
	_afk[peer] = afk
	if game != null:
		game.on_afk(peer, afk)
	bus.afk_changed.emit(peer, afk)
	_event("afk", {"peer": peer, "afk": afk})


func _feed_stats(frame: InputFrame) -> void:
	for peer in _order:
		var tm: Telemetry = frame.players[peer]
		var band: Array = hud_router.band_of(peer)
		stats.add_sample(peer, DT, tm.power_w, tm.mode, float(tm.applied_target_w), float(band[0]), float(band[1]))


func _platform_actions(actions: Array[StringName], my_gestures: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	var rider: LocalRider = local_riders.get(_local_peer)
	var resume_now := false
	for a in actions:
		match a:
			&"panic":
				if rider != null:
					rider.panic()
			&"pause":
				# platform_pause false: the app owns pausing; the action is consumed unused.
				if not _platform_pause:
					pass
				elif state == "paused":
					resume_now = true
				else:
					pause("user")
			&"shift_up", &"shift_down":
				if rider != null:
					rider.shift(1 if a == &"shift_up" else -1)
				out.append(a)
			_:
				out.append(a)
	# A user pause ends by resume(), an injected pause or confirm; a coasting or stop_5s pause
	# also ends when the rider pedals again (the session screen follows the same rule). With
	# platform_pause false only resume() ends a pause, and confirm stays an ordinary action.
	if not _platform_pause:
		return out
	var pedal_resume := my_gestures.has(Wl.G_PEDAL_START) and _pause_reason != "user"
	if state == "paused" and (resume_now or out.has(&"confirm") or pedal_resume):
		if not resume_now and out.has(&"confirm"):
			# The confirm that resumed the session is the platform's, never also a game confirm.
			out.erase(&"confirm")
		resume()
	return out


func _call_local_intents(actions: Array[StringName], gestures: Array[StringName]) -> void:
	if game == null:
		return
	var out: Variant = game.local_intents(actions, gestures)
	if not (out is Array):
		return
	for i: Variant in out:
		if i is Dictionary:
			intent_router.send(i)
		else:
			push_warning("GameHost: local_intents() returned a non-Dictionary intent; dropped")


func _on_phase_change(c: Dictionary, starting: bool) -> void:
	var peer := int(c["peer"])
	var index := int(c["index"])
	var ended_by := str(c["ended_by"])
	var plan_changed := bool(c.get("plan_changed", false))
	var plan := tracker.plan_of(peer)
	var start_tick := clock.game_tick if starting else clock.game_tick + 1
	if plan_changed:
		plans[peer] = plan
	if local_riders.has(peer):
		var r: LocalRider = local_riders[peer]
		if starting or plan_changed:
			r.set_plan(plan)
		r.start_phase(index)
	else:
		if plan_changed:
			_send_to(peer, Protocol.game_msg("plan", {"peer": peer, "plan": plan.to_dict()}))
		_send_to(peer, Protocol.game_msg("phase", {"peer": peer, "index": index, "start_tick": start_tick, "ended_by": ended_by}))
	bus.phase_started.emit(peer, index)
	_queue_event({"type": "wl.phase_started", "peer": peer, "index": index, "ended_by": ended_by})
	_event("phase_started", {"peer": peer, "index": index, "ended_by": ended_by, "kind": plan.phase(index).kind})
	if plan.phase(index).kind == Wl.COOLDOWN:
		directive_router.clear_bands(peer)
		hud_router.clear_power_band(peer)


func _send_snapshot(tick: int) -> void:
	if net == null and report == null:
		return
	var raw: Variant = game.snapshot()
	var st: Dictionary = (raw as Dictionary).duplicate(true) if raw is Dictionary else {}
	_snapshot_seq += 1
	var msg := Protocol.game_msg("snapshot", {"game_id": str(manifest.get("id", "")), "seq": _snapshot_seq, "tick": tick, "state": st})
	_last_snapshot_msg = msg
	_last_snapshot_state = st
	if report != null:
		var m := report.snapshot(_snapshot_seq, tick, st)
		if int(m["bytes"]) + 256 > NetMessages.MAX_MESSAGE_BYTES \
				and JSON.stringify(msg).to_utf8_buffer().size() > NetMessages.MAX_MESSAGE_BYTES:
			report.count_oversize()
			push_warning("GameHost: snapshot %d is over %d bytes" % [_snapshot_seq, NetMessages.MAX_MESSAGE_BYTES])
	if net != null:
		_broadcast(msg)


func _queue_event(e: Dictionary) -> void:
	_event_queue.append(e)


func _flush_events() -> void:
	if _event_queue.is_empty():
		return
	_event_seq += 1
	var msg := Protocol.game_msg("event", {"seq": _event_seq, "events": _event_queue})
	_event_queue = []
	if net != null:
		_broadcast(msg)


func _send_roster() -> void:
	if ctx == null:
		return
	var riders := {}
	for peer in _order:
		var tm: Telemetry = _frame_tm.get(peer)
		if tm == null:
			tm = (local_riders[peer] as LocalRider).telemetry() if local_riders.has(peer) else Telemetry.new()
		var slot: PlayerSlot = _slots[peer]
		var connected := tm.connected
		if _remote.has(peer):
			connected = not bool((_remote[peer] as Dictionary)["dropped"])
		riders[peer] = {
			"raw_w": tm.power_w, "cadence_rpm": tm.cadence_rpm,
			"ftp_pct": tm.power_w / maxf(slot.ftp, 1.0) * 100.0,
			"rescue": tm.rescue, "afk": bool(_afk.get(peer, tm.afk)), "connected": connected,
			"status": (hud_router.statuses.get(peer, {}) as Dictionary).duplicate(),
			"name": slot.name, "slot_index": slot.slot_index,
		}
	ctx.roster = riders
	bus.roster_changed.emit(riders)
	if net != null:
		_broadcast(Protocol.game_msg("roster", {"riders": riders}))


func _trace_authority() -> void:
	var pt := clock.platform_time()
	var gt := clock.game_tick * DT
	for peer in _order:
		var tm: Telemetry = _frame_tm.get(peer)
		if tm == null:
			tm = (local_riders[peer] as LocalRider).telemetry() if local_riders.has(peer) else Telemetry.new()
		var slot: PlayerSlot = _slots[peer]
		var st := tracker.state(peer)
		report.trace(peer, _trace_row(pt, gt, st, tm, slot.ftp))


func _trace_row(pt: float, gt: float, st: PhaseState, tm: Telemetry, ftp: float) -> Dictionary:
	var cb: Array = []
	for c in tm.clamped_by:
		cb.append(str(c))
	return {
		"t": pt, "game_t": gt, "phase": st.index, "kind": st.kind, "mode": tm.mode,
		"applied_target_w": tm.applied_target_w,
		"applied_pct": float(tm.applied_target_w) / maxf(ftp, 1.0) * 100.0,
		"applied_grade_pct": tm.applied_grade_pct, "clamped_by": cb, "rescue": tm.rescue,
		"afk": tm.afk, "paused": tm.paused or state == "paused", "haptic": tm.haptic_pct,
		"power_w": tm.power_w, "cadence_rpm": tm.cadence_rpm, "connected": tm.connected,
	}


func _finish_session(reason: String) -> void:
	if results != null:
		return
	end_reason = reason
	_flush_events()
	var r: GameResults = game.results() if game != null else null
	if r == null:
		r = GameResults.from_stats(stats, ctx.players)
	complete_rows(r)
	r.session_id = session_id
	results = r
	if net != null:
		_broadcast(Protocol.game_msg("results", {"results": r.to_dict()}))
	_event("results", {"grade": r.grade, "reason": reason})
	_apply_results(r)
	_save_fits()
	_set_state("results")
	session_finished.emit(r)


## The platform's part of the results (BRIEF 3.6 "per-player rows"; docs/OWNERSHIP.md RES1):
## every rider in ctx.players gets a row, with the SessionStatsTracker's base row for a rider
## the game left out (appended after the game's rows, in slot order), and every row keeps
## the base keys (kJ, power, NP, best powers, ride and band time, xp, unlocks, stats, slot
## fields) the game did not set itself. Values the game set are never changed.
func complete_rows(r: GameResults) -> void:
	if r == null or ctx == null:
		return
	var base := GameResults.from_stats(stats, ctx.players)
	for brow in base.rows:
		var row := r.row(int(brow["peer_id"]))
		if row.is_empty():
			r.rows.append(brow)
			continue
		for k: Variant in brow.keys():
			if not row.has(k):
				row[k] = brow[k]


func _apply_results(r: GameResults) -> void:
	if _progress_done.has(r.session_id):
		return
	_progress_done[r.session_id] = true
	var u: Variant = []
	if game != null and ctx != null and ctx.progress != null:
		u = game.apply_progress(r, ctx.progress)
		ctx.progress.save()
	unlocks = (u as Array).duplicate(true) if u is Array else []
	bus.results_ready.emit(r)
	bus.unlocks_ready.emit(unlocks)


func _save_fits() -> void:
	if not _record_rides:
		return
	var targets: Variant = config.get("fit_paths", {})
	for peer in _local_order():
		if _fit_paths.has(peer):
			continue
		var r: LocalRider = local_riders[peer]
		var slot: PlayerSlot = _slots.get(peer)
		if r.is_bot or (slot != null and slot.is_bot):
			continue
		var path := r.finish_ride()
		if path == "":
			continue
		if targets is Dictionary and (targets as Dictionary).has(peer):
			path = _move_ride(path, str((targets as Dictionary)[peer]))
		_fit_paths[peer] = path


## Move a saved FIT (and its JSON summary next to it) to `target`; returns the final path.
static func _move_ride(from: String, target: String) -> String:
	if target == "" or target == from:
		return from
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if not _move_file(from, target):
		push_warning("GameHost: could not move %s to %s" % [from, target])
		return from
	var summary_from := from.get_basename() + ".json"
	if FileAccess.file_exists(summary_from):
		_move_file(summary_from, target.get_basename() + ".json")
	return target


static func _move_file(from: String, to: String) -> bool:
	if FileAccess.file_exists(to):
		DirAccess.remove_absolute(to)
	if DirAccess.rename_absolute(from, to) == OK:
		return true
	if DirAccess.copy_absolute(from, to) == OK:
		DirAccess.remove_absolute(from)
		return true
	return false


# --- client step -------------------------------------------------------------------------


func _client_step() -> void:
	var rider: LocalRider = local_riders.get(_local_peer)
	var gestures: Array[StringName] = []
	if rider != null:
		rider.tick(DT)
		gestures = _local_gestures(rider)
	_pending_gestures.append_array(gestures)
	var actions := _take_actions()
	var active := _configured and (state == "running" or state == "cooldown")
	var filtered: Array[StringName] = []
	for a in actions:
		match a:
			&"panic":
				if rider != null:
					rider.panic()
			&"pause":
				pass
			&"shift_up", &"shift_down":
				if rider != null:
					rider.shift(1 if a == &"shift_up" else -1)
				filtered.append(a)
			_:
				filtered.append(a)
	if active:
		_call_local_intents(filtered, gestures)
		if rider != null:
			game.client_predict(DT, rider.telemetry())
	if _client_phase >= 0:
		_client_phase_ticks += 1
	if state != "ended" and clock.platform_tick % TELEMETRY_EVERY == 0:
		_send_telemetry()
	if report != null and rider != null and clock.platform_tick % TRACE_EVERY == 0:
		var ftp := (_slots[_local_peer] as PlayerSlot).ftp if _slots.has(_local_peer) else 200.0
		report.trace(_local_peer, _trace_row(clock.platform_time(), clock.game_tick * DT, local_phase_state(), rider.telemetry(), ftp))
	_update_hud()


func _send_telemetry() -> void:
	var rider: LocalRider = local_riders.get(_local_peer)
	if rider == null or net == null:
		return
	var tm := rider.telemetry()
	tm.peer_id = _local_peer
	tm.gestures.assign(_pending_gestures)
	_pending_gestures.clear()
	var ints: Array = rider.take_intents()
	ints.append_array(intent_router.take())
	if ints.size() > IntentRouter.MAX_PER_TELEMETRY:
		push_warning("GameHost: %d intents in one telemetry message; %d dropped (max %d)" % [ints.size(), ints.size() - IntentRouter.MAX_PER_TELEMETRY, IntentRouter.MAX_PER_TELEMETRY])
		ints = ints.slice(0, IntentRouter.MAX_PER_TELEMETRY)
	tm.intents = ints
	tm.acks = rider.take_acks()
	net.send_to_host(Protocol.game_msg("telemetry", {"tm": tm.to_dict()}))


# --- messages ----------------------------------------------------------------------------


func _poll_net() -> void:
	if net != null and bool(config.get("poll_net", true)):
		net.poll()


func _on_net_message(from: int, data: Dictionary) -> void:
	_inbox.append([from, data])


func _on_net_peer_left(peer_id: int, reason: String) -> void:
	_inbox.append([peer_id, {"type": "_peer_left", "reason": reason}])


func _on_net_rejoin(peer_id: int) -> void:
	_inbox.append([peer_id, {"type": "_rejoin"}])


func _on_net_refused(reason: String) -> void:
	_inbox.append([0, {"type": "_refused", "reason": reason}])


func _process_inbox() -> void:
	while not _inbox.is_empty():
		var batch := _inbox
		_inbox = []
		for item: Array in batch:
			var from := int(item[0])
			var data: Dictionary = item[1]
			if role == Wl.CLIENT:
				_client_message(from, data)
			else:
				_authority_message(from, data)


func _authority_message(from: int, data: Dictionary) -> void:
	match str(data.get("type", "")):
		"telemetry":
			_on_telemetry(from, data)
		"_peer_left":
			_on_peer_left(from, str(data.get("reason", "")))
		"_rejoin":
			_on_rejoin(from)


func _on_telemetry(from: int, data: Dictionary) -> void:
	if not _remote.has(from):
		return
	var tmd: Variant = data.get("tm")
	if not (tmd is Dictionary):
		return
	var tm := Telemetry.from_dict(tmd)
	var r: Dictionary = _remote[from]
	(r["gestures"] as Array).append_array(tm.gestures)
	(r["intents"] as Array).append_array(tm.intents)
	for ack: Variant in tm.acks:
		if ack is Dictionary:
			var rec := _normalized_ack(ack)
			directive_router.on_ack(from, rec)
			bus.directive_applied.emit(from, rec)
			if report != null:
				report.directive_applied(from, rec)
	tm.gestures.clear()
	tm.intents = []
	tm.acks = []
	r["tm"] = tm
	r["rx_t"] = clock.platform_time()
	r["seen"] = true
	if bool(r["dropped"]):
		r["dropped"] = false
		r["await_pedal"] = true
	if bool(r["await_pedal"]) and not tm.afk and (tm.power_w >= PEDAL_POWER_W or tm.cadence_rpm >= PEDAL_CADENCE_RPM):
		r["await_pedal"] = false


func _on_peer_left(peer: int, reason: String) -> void:
	if not _remote.has(peer):
		return
	var r: Dictionary = _remote[peer]
	r["dropped"] = true
	r["await_pedal"] = true
	# The last telemetry before the drop must never reappear as live power: after a rejoin the
	# rider shows 0 W and 0 rpm until fresh telemetry arrives.
	var last: Telemetry = r["tm"]
	if last != null:
		last.power_w = 0.0
		last.cadence_rpm = 0.0
		last.speed_kmh = 0.0
		last.p_eff_w = 0.0
		last.ftp_pct = 0.0
		last.effort = 0.0
	_event("peer_left", {"peer": peer, "reason": reason})
	if state == "running" or state == "cooldown" or state == "paused":
		_set_afk(peer, true)


func _on_rejoin(peer: int) -> void:
	if not _remote.has(peer) or ctx == null:
		return
	var r: Dictionary = _remote[peer]
	r["dropped"] = false
	r["await_pedal"] = true
	_event("rejoin", {"peer": peer})
	_send_to(peer, Protocol.game_msg("session_start", _session_start_payload()))
	if plans.has(peer):
		_send_to(peer, Protocol.game_msg("plan", {"peer": peer, "plan": (plans[peer] as EffortPlan).to_dict()}))
	if tracker.index_of(peer) >= 0:
		var hist := tracker.history(peer)
		var last: Dictionary = hist[hist.size() - 1] if not hist.is_empty() else {}
		var prev := tracker.state(peer).prev_ended_by
		_send_to(peer, Protocol.game_msg("phase", {
			"peer": peer, "index": tracker.index_of(peer),
			"start_tick": int(roundf(float(last.get("start", 0.0)) / DT)),
			"ended_by": prev if prev != "" else Wl.ENDED_START}))
	if not _last_snapshot_msg.is_empty():
		_send_to(peer, _last_snapshot_msg)
	if results != null:
		_send_to(peer, Protocol.game_msg("results", {"results": results.to_dict()}))


func _client_message(from: int, data: Dictionary) -> void:
	match str(data.get("type", "")):
		"session_start":
			_on_session_start(data)
		"plan":
			_on_plan(data)
		"phase":
			_on_phase(data)
		"directive":
			_on_directive(data)
		"snapshot":
			_on_snapshot(data)
		"event":
			_on_event(data)
		"roster":
			_on_roster(data)
		"hud":
			hud_router.draw_remote(str(data.get("kind", "toast")), str(data.get("key", "")), data.get("args", []), float(data.get("seconds", 3.0)))
		"results":
			_on_results(data)
		"session_end":
			end_session(str(data.get("reason", "host_ended")))
		"_refused":
			if state != "ended" and (str(data.get("reason", "")) == "host_left"):
				end_session("host_left")
		"_peer_left":
			if from == (net.host_peer if net != null else Wl.HOST_PEER) and state != "ended" and results == null:
				_event("host_dropped", {"peer": from})


func _on_session_start(data: Dictionary) -> void:
	if _configured:
		return
	var game_id := _string_field(data, "game", "game_id")
	var m: Variant = config.get("manifest", {})
	manifest = (m as Dictionary).duplicate(true) if m is Dictionary and not (m as Dictionary).is_empty() else {}
	if manifest.is_empty() and registry != null:
		manifest = registry.manifest(game_id)
	if manifest.is_empty():
		push_warning("GameHost: the host started unknown game \"%s\"" % game_id)
		end_session("unknown_game")
		return
	if not manifest.has("options"):
		manifest = WlGameRegistry.normalized(manifest)
	var players: Array[PlayerSlot] = []
	var pv: Variant = data.get("players", [])
	if pv is Array:
		for pd: Variant in pv:
			if pd is Dictionary:
				players.append(PlayerSlot.from_dict(pd))
	players = _sorted_players(players)
	for p in players:
		p.options = WlGameRegistry.resolve_option_values(manifest.get("player_options", []), p.options, "%s player %d" % [game_id, p.peer_id])
	game = config.get("game") as GameModule
	if game == null:
		game = WlGameRegistry.instantiate_manifest(manifest)
	if game == null:
		push_warning("GameHost: cannot instantiate %s" % str(manifest.get("entry", "")))
		end_session("unknown_game")
		return
	if game.get_parent() == null:
		add_child(game)
	var opts: Variant = data.get("options", {})
	var overrides: Variant = data.get("content_overrides", {})
	var options := WlGameRegistry.resolve_option_values(manifest.get("options", []), opts if opts is Dictionary else {}, game_id)
	_init_session(players, _string_field(data, "content", "content_id"), int(data.get("seed", 0)), options,
		str(data.get("scaling", Wl.FAIR_FTP)), overrides if overrides is Dictionary else {})
	session_id = _string_field(data, "session", "session_id", session_id)
	game.configure(ctx)
	_int_fields = game.int_fields()
	_build_presentation()
	_configured = true
	_set_state("running")
	_event("session_start", {"role": role, "players": players.size()})
	_update_metronome(0.0, 0.0)
	if _pending_snapshot != null:
		var snap: Variant = _pending_snapshot
		_pending_snapshot = null
		_apply_snapshot_state(snap)


func _on_plan(data: Dictionary) -> void:
	var pd: Variant = data.get("plan")
	if not (pd is Dictionary):
		push_warning("GameHost: plan message without a plan")
		return
	var plan := EffortPlan.from_dict(pd)
	var res := PlanValidator.validate(plan)
	if not bool(res["ok"]) or not plan.cooldown_appended:
		var why := "; ".join(res["errors"]) if not bool(res["ok"]) else "no cool-down appended"
		push_warning("GameHost: rejected the host's plan: %s" % why)
		_event("plan_rejected", {"errors": res["errors"]})
		return
	plans[_local_peer] = plan
	plan_warnings[_local_peer] = (res["warnings"] as Array).duplicate()
	_client_plan = plan
	var rider: LocalRider = local_riders.get(_local_peer)
	if rider != null:
		rider.set_plan(plan)


func _on_phase(data: Dictionary) -> void:
	var index := int(data.get("index", -1))
	if _client_plan == null or _client_plan.phase(index) == null:
		push_warning("GameHost: phase %d without a matching plan" % index)
		return
	_client_phase = index
	_client_phase_ticks = 0
	_client_phase_start_tick = int(data.get("start_tick", 0))
	var ended_by := str(data.get("ended_by", ""))
	_client_prev_ended_by = "" if ended_by == Wl.ENDED_START else ended_by
	var rider: LocalRider = local_riders.get(_local_peer)
	if rider != null:
		rider.start_phase(index)
	bus.phase_started.emit(_local_peer, index)
	_event("phase_started", {"peer": _local_peer, "index": index, "ended_by": ended_by})
	if _client_plan.phase(index).kind == Wl.COOLDOWN:
		if float(_client_cadence[0]) != 0.0 or float(_client_cadence[1]) != 0.0:
			_client_cadence = [0.0, 0.0]
			if rider != null:
				rider.set_cadence_band(0.0, 0.0)
			bus.cadence_band_changed.emit(_local_peer, 0.0, 0.0)
		hud_router.clear_power_band(_local_peer)
		if state == "running":
			_set_state("cooldown")


func _on_directive(data: Dictionary) -> void:
	var rider: LocalRider = local_riders.get(_local_peer)
	match str(data.get("kind", "")):
		NetMessages.DIRECTIVE_REQUEST:
			var dd: Variant = data.get("directive", {})
			if not (dd is Dictionary) or rider == null:
				return
			var d := EffortDirective.from_dict(dd)
			d.id = int(data.get("id", d.id))
			var rec := _normalized_ack(rider.apply_directive(d), d.id, d.to_dict())
			bus.directive_applied.emit(_local_peer, rec)
			if report != null:
				report.directive_requested(_local_peer, d.id, NetMessages.DIRECTIVE_REQUEST, d.to_dict(), clock.game_tick * DT, true, "")
				report.directive_applied(_local_peer, rec)
		NetMessages.DIRECTIVE_COURSE_GRADE:
			if rider != null:
				rider.apply_course_grade(float(data.get("grade_pct", 0.0)))
		NetMessages.DIRECTIVE_CADENCE_BAND:
			var lo := float(data.get("lo_rpm", 0.0))
			var hi := float(data.get("hi_rpm", 0.0))
			_client_cadence = [lo, hi]
			if rider != null:
				rider.set_cadence_band(lo, hi)
			bus.cadence_band_changed.emit(_local_peer, lo, hi)
		NetMessages.DIRECTIVE_POWER_BAND:
			var lo := float(data.get("lo_w", 0.0))
			var hi := float(data.get("hi_w", 0.0))
			if lo == 0.0 and hi == 0.0:
				hud_router.power_bands.erase(_local_peer)
			else:
				hud_router.power_bands[_local_peer] = [lo, hi]
			if rider != null:
				rider.set_power_band(lo, hi)
			bus.power_band_changed.emit(_local_peer, lo, hi)


func _on_snapshot(data: Dictionary) -> void:
	var seq := int(data.get("seq", 0))
	if seq <= _snap_seq_applied:
		return
	_snap_seq_applied = seq
	# The snapshot's tick is the host's game tick just simulated: a client that joined or
	# rejoined mid-phase catches its phase clock up from the phase's start_tick.
	var host_tick := int(data.get("tick", -1))
	if host_tick >= 0 and _client_phase >= 0:
		_client_phase_ticks = maxi(_client_phase_ticks, host_tick + 1 - _client_phase_start_tick)
	var st: Variant = data.get("state")
	if not (st is Dictionary):
		return
	if not _configured:
		_pending_snapshot = st
		return
	_apply_snapshot_state(st)


func _apply_snapshot_state(st: Variant) -> void:
	var paths: Variant = _int_fields.get("snapshot", [])
	var conv: Variant = Protocol.apply_int_fields(st, paths if paths is Array else [])
	game.apply_snapshot(conv if conv is Dictionary else st)


func _on_event(data: Dictionary) -> void:
	var seq := int(data.get("seq", 0))
	if seq <= _event_seq_applied:
		return
	_event_seq_applied = seq
	var evs: Variant = data.get("events", [])
	if not (evs is Array):
		return
	for ev: Variant in evs:
		if not (ev is Dictionary):
			continue
		var e: Dictionary = ev
		var type := str(e.get("type", ""))
		if type.begins_with(PLATFORM_EVENT_PREFIX):
			_platform_event(e)
			continue
		if not _configured:
			continue
		var paths: Variant = _int_fields.get(type, [])
		var conv: Variant = Protocol.apply_int_fields(e, paths if paths is Array else [])
		game.apply_event(conv if conv is Dictionary else e)
		_event("game_event", {"event": e})


func _platform_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"wl.phase_started":
			var peer := int(e.get("peer", 0))
			if peer != _local_peer:
				# The client's own rider is recorded from its `phase` message.
				bus.phase_started.emit(peer, int(e.get("index", 0)))
				_event("phase_started", {"peer": peer, "index": int(e.get("index", 0)), "ended_by": str(e.get("ended_by", ""))})
		"wl.lap_marker":
			var rider: LocalRider = local_riders.get(_local_peer)
			var label := str(e.get("label", ""))
			if rider != null:
				rider.lap(label)
			bus.lap_marked.emit(label)
		"wl.finished":
			bus.game_finished.emit(str(e.get("reason", "")))


func _on_roster(data: Dictionary) -> void:
	var rv: Variant = data.get("riders", {})
	if not (rv is Dictionary):
		return
	var roster := {}
	for k: Variant in (rv as Dictionary).keys():
		var row: Variant = (rv as Dictionary)[k]
		if row is Dictionary:
			var copy := (row as Dictionary).duplicate(true)
			if copy.has("slot_index"):
				copy["slot_index"] = int(copy["slot_index"])
			roster[int(str(k))] = copy
	for peer: int in hud_router.statuses.keys():
		if roster.has(peer):
			(roster[peer] as Dictionary)["status"] = (hud_router.statuses[peer] as Dictionary).duplicate()
	if ctx != null:
		ctx.roster = roster
	bus.roster_changed.emit(roster)


func _on_results(data: Dictionary) -> void:
	var rv: Variant = data.get("results", {})
	if not (rv is Dictionary):
		return
	var r := GameResults.from_dict(rv)
	if results == null:
		results = r
	_event("results", {"grade": r.grade})
	_apply_results(r)
	_save_fits()
	if state != "ended":
		_set_state("results")
	session_finished.emit(r)


func _on_local_status(peer: int, status: Dictionary) -> void:
	if ctx == null:
		return
	var roster := ctx.roster.duplicate(true)
	var row: Dictionary = roster.get(peer, {})
	row["status"] = status.duplicate()
	roster[peer] = row
	ctx.roster = roster
	bus.roster_changed.emit(roster)


# --- game signals --------------------------------------------------------------------


func _on_game_finished(reason: String) -> void:
	var first := finished_reason == ""
	if first:
		finished_reason = reason
		_queue_event({"type": "wl.finished", "reason": reason})
	_event("finished", {"reason": reason})
	bus.game_finished.emit(reason)
	tracker.finish_all()


func _on_game_event(event: Dictionary) -> void:
	var type := str(event.get("type", ""))
	if type == "":
		push_warning("GameHost: game event without a \"type\" dropped")
		return
	if type.begins_with(PLATFORM_EVENT_PREFIX) or type == "snapshot":
		push_warning("GameHost: game event type \"%s\" is reserved; dropped" % type)
		return
	var e := event.duplicate(true)
	_queue_event(e)
	_event("game_event", {"event": e})


func _on_game_phase_changed(index: int) -> void:
	_event("game_phase_changed", {"index": index})


func _on_lap_marker(label: String) -> void:
	var rider: LocalRider = local_riders.get(_local_peer)
	if rider != null:
		rider.lap(label)
	bus.lap_marked.emit(label)
	_queue_event({"type": "wl.lap_marker", "label": label})
	_event("lap_marker", {"label": label})


func _on_cadence_band_changed(peer: int, lo: float, hi: float) -> void:
	if peer == _local_peer:
		_update_metronome(lo, hi)


## The optional cadence metronome (BRIEF 3.9; docs/OWNERSHIP.md AU2): the local rider's
## published cadence band centre, else the preferred cadence; on only when the rider's
## profile turned it on. Rendering peers only.
func _update_metronome(lo: float, hi: float) -> void:
	if _headless:
		return
	var sfx := _sfx()
	var rider: LocalRider = local_riders.get(_local_peer)
	if sfx == null or not sfx.has_method("set_metronome") or rider == null:
		return
	var on := rider.profile != null and rider.profile.metronome
	var rpm := 0.5 * (lo + hi) if hi > 0.0 else (rider.slot.preferred_cadence_rpm if rider.slot != null else 90.0)
	sfx.call("set_metronome", rpm, on)


func _stop_metronome() -> void:
	if _headless:
		return
	var sfx := _sfx()
	if sfx != null and sfx.has_method("set_metronome"):
		sfx.call("set_metronome", 0.0, false)


## config.sfx (a Node with set_metronome; tests) or the Sfx autoload.
func _sfx() -> Node:
	var injected := config.get("sfx") as Node
	return injected if injected != null else _autoload("Sfx")


func _on_pause_requested(reason: String) -> void:
	if role == Wl.SOLO:
		pause(reason)


func _on_panic() -> void:
	var rider: LocalRider = local_riders.get(_local_peer)
	if rider != null:
		rider.panic()


func _on_replan(peer: int, warnings: Array) -> void:
	plan_warnings[peer] = warnings.duplicate()


# --- helpers -------------------------------------------------------------------------------


func _set_state(s: String) -> void:
	if state == s:
		return
	state = s
	if bus != null:
		var bus_state := s
		if s == "setup":
			bus_state = "starting"
		bus.session_state_changed.emit(bus_state)
	_event("session_state", {"state": s})
	state_changed.emit(s)


func _event(type: String, fields: Dictionary = {}) -> void:
	if report != null:
		report.event(clock.game_tick * DT if clock != null else 0.0, clock.platform_time() if clock != null else 0.0, type, fields)


func _now() -> Array:
	if clock == null:
		return [0.0, 0.0]
	return [clock.game_tick * DT, clock.platform_time()]


func _latest_telemetry(peer: int) -> Variant:
	if _frame_tm.has(peer):
		return _frame_tm[peer]
	if local_riders.has(peer):
		return (local_riders[peer] as LocalRider).telemetry()
	return null


func _local_order() -> Array[int]:
	var out: Array[int] = []
	for peer in _order:
		if local_riders.has(peer):
			out.append(peer)
	var extra: Array[int] = []
	for k: int in local_riders.keys():
		if not out.has(k):
			extra.append(k)
	extra.sort()
	out.append_array(extra)
	return out


func _take_gestures(rider: LocalRider) -> Array[StringName]:
	var out: Array[StringName] = []
	if rider != null:
		out.assign(rider.take_gestures())
	return out


## True when the local rider's gestures come from the InputRouter: a rendering session with
## a router, which merges its attached rider's pedal gestures (BRIEF 3.5; WlInputRouter).
func _gestures_from_router() -> bool:
	return not _headless and _input_router != null and _input_router.has_method("take_gestures")


## The local rider's gestures since the last tick: InputRouter.take_gestures() when rendering
## (the rider's own queue is then left to the router, so no gesture is taken twice), else
## LocalRider.take_gestures(); a headless session drains and ignores a router's queue.
func _local_gestures(rider: LocalRider) -> Array[StringName]:
	var out: Array[StringName] = []
	if _gestures_from_router():
		out.assign(_input_router.call("take_gestures"))
		return out
	if _input_router != null and _input_router.has_method("take_gestures"):
		_input_router.call("take_gestures")
	return _take_gestures(rider)


## The InputRouter's actions, then the injected ones. The router's `pause` is dropped, and so
## is its `confirm` while paused: the app's session screen owns pausing and its pause menu
## (it calls pause() and resume() itself), so the GameHost never toggles pause on them. An
## injected `pause` (on-screen buttons, tools, tests) still toggles while config.platform_pause
## is on (the default).
func _take_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	if _input_router != null and _input_router.has_method("take_actions"):
		for a: Variant in _input_router.call("take_actions"):
			var action := StringName(a)
			if action == &"pause" or (action == &"confirm" and state == "paused"):
				continue
			out.append(action)
	out.append_array(_injected_actions)
	_injected_actions.clear()
	return out


func _send_directive(peer: int, payload: Dictionary) -> void:
	_send_to(peer, Protocol.game_msg("directive", payload))


func _send_or_broadcast(peer: int, msg: Dictionary) -> void:
	if peer == Wl.ALL_PEERS:
		_broadcast(msg)
	else:
		_send_to(peer, msg)


func _send_to(peer: int, msg: Dictionary) -> void:
	if net == null:
		return
	if _remote.has(peer) and bool((_remote[peer] as Dictionary)["dropped"]):
		return
	net.send_to(peer, msg)


func _broadcast(msg: Dictionary) -> void:
	if net != null:
		net.broadcast(msg)


func _update_hud() -> void:
	if _hud_layer == null:
		return
	var rider: LocalRider = local_riders.get(_local_peer)
	var tm := rider.telemetry() if rider != null else Telemetry.new()
	var plan: EffortPlan = _client_plan if role == Wl.CLIENT else tracker.plan_of(_local_peer)
	_hud_layer.update(tm, local_phase_state(), plan)
	var warm := false
	if rider != null and rider.governor != null:
		warm = rider.governor.is_warmup_active()
	_hud_layer.set_safety_state(warm, tm.rescue, state == "paused" or tm.paused)


func _normalized_ack(rec: Dictionary, id: int = 0, requested: Dictionary = {}) -> Dictionary:
	var out := rec.duplicate(true)
	out["id"] = int(out.get("id", id)) if int(out.get("id", 0)) != 0 else id
	if not out.has("kind"):
		out["kind"] = NetMessages.DIRECTIVE_REQUEST
	if not out.has("requested"):
		out["requested"] = requested
	if not out.has("applied"):
		out["applied"] = {}
	if not out.has("clamped_by"):
		out["clamped_by"] = []
	if not out.has("refused"):
		out["refused"] = false
	elif not (out["refused"] is bool):
		# Telemetry.acks documents refused as a String ("" or the reason); records carry a bool.
		var rv: Variant = out["refused"]
		out["refused"] = (rv is String and str(rv) != "") or ((rv is int or rv is float) and float(rv) != 0.0)
	if not out.has("reason"):
		out["reason"] = ""
	if not out.has("t"):
		out["t"] = clock.game_tick * DT if clock != null else 0.0
	return out


static func _sorted_players(v: Variant) -> Array[PlayerSlot]:
	var out: Array[PlayerSlot] = []
	if v is Array:
		for p: Variant in v:
			if p is PlayerSlot:
				out.append(p)
	out.sort_custom(func(a: PlayerSlot, b: PlayerSlot) -> bool: return a.slot_index < b.slot_index)
	return out


static func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)
