class_name GameSimRunner
extends Node
## In-process, headless (or windowed) simulation of a whole session with MockTrainer riders
## (BRIEF 3.6 tools/run_game_sim, tools/screenshot). Owned by sdk-runtime; public API frozen
## after W0. qa's tools/screenshot reuses it windowed.
##
## One human slot (with or without bots) runs SOLO; two or more run as HOST with
## LoopbackTransport clients, one GameHost and NetSession per human slot. Every human slot
## has its own MockTrainer and governor; bots are added after the humans.
## args (the run_game_sim flags, parsed): game, content, players (int), bots (int),
## riders (Array[String] per human slot), sim_speed, seed, report (path), autopilot
## ("all" | "none" | Array[int] slots), ftp (Array[float]), unverified (bool),
## haptics_off (Array[int]), options (Dictionary), player_options (Array[Dictionary]),
## override (Dictionary of content patches), max_sim_seconds (float), headless (bool).
##
## Additive args: override_path (the --override file, recorded), at (Array[float]) and
## screenshot_dir (tools/screenshot), registry (a WlGameRegistry; default the autoload),
## rider_factory (Callable(slot: PlayerSlot, profile: RiderProfile, spec: String,
## options: Dictionary) -> LocalRider; default LocalRider + MockTrainer.from_spec),
## net_factory (Callable(count: int) -> Array of WlNetSession with local_peer set, host
## first, or an error String; default LoopbackTransport rooms), utc_start_unix (int; the
## FIT start stamp, default the wall clock, kept out of the hash).
##
## Rules: FTP 200 W per slot unless --ftp gives one value (every slot), one per human slot
## (bots take the first) or one per slot; human slots are verified unless --unverified;
## bots are verified, run Autopilot and ride "erg:compliance=1.0" at the bot FTP (the first
## human's); --autopilot (default all) sets the human slots' Autopilot; --haptics-off turns
## haptics off for the listed slots; --player-options holds one object per human slot (bots
## and missing keys get defaults). Each human slot gets a private profile dir under a temp
## root (Paths' override is moved there for the run and restored by cleanup()), so the
## user's profile, progress and rides are never touched. FIT files: one per human slot at
## <report dir>/fit/<report stem>_slot<n>.fit. The run ends `complete` after every rider's
## cool-down, `timeout` at max_sim_seconds (default: the longest validated plan with
## open-ended phases at max_s, plus 600 s), or `paused` once a SOLO run stayed paused for
## 120 s of platform time; every ending calls results() and saves the FIT files. Peers step
## in a fixed order (host, then clients in slot order), so a run is deterministic.

const REPORT_SCHEMA := 1
const DT := Wl.SIM_DT
const DEFAULT_FTP := 200.0
const DEFAULT_RIDER := "erg"
const PAUSED_END_S := 120.0
const TIMEOUT_MARGIN_S := 600.0
## Steps given to clients after the host ended, to receive the results.
const CLIENT_DRAIN_TICKS := 200
const FLAGS: Array[String] = [
	"game", "content", "players", "bots", "rider", "sim-speed", "seed", "report", "autopilot",
	"ftp", "unverified", "haptics-off", "options", "player-options", "override",
	"max-sim-seconds", "headless", "windowed", "at", "screenshot-dir",
]
## args keys kept out of the deterministic hash (paths and tool-only settings).
const UNHASHED_ARGS: Array[String] = ["report", "override_path", "screenshot_dir", "at", "headless", "sim_speed"]

var host: GameHost = null

# --- additive public state ---------------------------------------------------------------
## The normalized args (defaults filled).
var args: Dictionary = {}
var clients: Array[GameHost] = []
## Wl.SOLO or Wl.HOST.
var role: String = Wl.SOLO
## Every slot in slot order (humans, then bots).
var slots: Array[PlayerSlot] = []
## peer -> LocalRider (every human and bot).
var riders: Dictionary = {}
## Host first, then clients (empty in SOLO).
var nets: Array[WlNetSession] = []
var registry: WlGameRegistry = null
var manifest: Dictionary = {}
var end_reason: String = ""
var max_sim_seconds: float = 0.0
## Per human slot: the rider profile spec.
var slot_specs: Array[String] = []

var _ticks: int = 0
var _paused_ticks: int = 0
var _temp_root: String = ""
var _prev_paths_override: String = ""
var _paths_overridden: bool = false
var _wall_start_ms: int = 0
var _wall_s: float = 0.0
var _utc_start: int = 0
var _fit_targets: Array[String] = []


func _init() -> void:
	# A system node: its riders, trainers, net sessions and GameHosts keep running while the
	# scene tree is paused (BRIEF 4.1).
	process_mode = Node.PROCESS_MODE_ALWAYS


## Freeing the runner restores Paths' override and deletes the run's temp root too (W3 QT-4),
## so a runner freed without cleanup() (autofree in tests, a tool that forgot it) never leaves a
## wattlands_sim_* dir behind.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_restore_paths()
		if _temp_root != "":
			_remove_tree(_temp_root)
			_temp_root = ""


## The one flag parser shared by tools/run_game_sim and tools/screenshot: turns
## "--game=... --players=2 --rider=erg --rider=zero --ftp=180,220 ..." into the args
## Dictionary setup() takes ({"error": String} on a bad flag).
static func parse_args(p_args: PackedStringArray) -> Dictionary:
	var out := default_args()
	for a in p_args:
		if a == "--":
			continue
		if not a.begins_with("--"):
			return {"error": "%s: not a --flag=value argument" % a}
	var parsed := CmdLine.parse(p_args)
	for key: String in parsed.keys():
		if not FLAGS.has(key):
			return {"error": "--%s: unknown flag" % key}
		var vals: Array = parsed[key]
		if key != "rider" and vals.size() > 1:
			return {"error": "--%s: given more than once" % key}
		var v := str(vals[vals.size() - 1])
		var err := ""
		match key:
			"game", "content", "report", "screenshot-dir":
				if v == "" or v == "true":
					err = "needs a value"
				else:
					out[key.replace("-", "_")] = v
			"players":
				err = _int_flag(out, "players", v, 1, Wl.MAX_SLOTS)
			"bots":
				err = _int_flag(out, "bots", v, 0, Wl.MAX_SLOTS - 1)
			"seed":
				if not v.is_valid_int():
					err = "must be a whole number"
				else:
					out["seed"] = int(v)
			"rider":
				var specs: Array[String] = []
				for s: Variant in vals:
					if str(s) == "" or str(s) == "true":
						err = "needs a profile"
					specs.append(str(s))
				out["riders"] = specs
			"sim-speed":
				err = _float_flag(out, "sim_speed", v, 0.0, false)
			"max-sim-seconds":
				err = _float_flag(out, "max_sim_seconds", v, 0.0, false)
			"autopilot":
				if v == "all" or v == "none":
					out["autopilot"] = v
				else:
					var list := _int_list(v, 0)
					if list.is_empty() and v != "":
						err = "must be all, none or a list of slots"
					out["autopilot"] = list
			"ftp":
				var ftps: Array[float] = []
				for part in v.split(","):
					var s := part.strip_edges()
					if not s.is_valid_float() or float(s) <= 0.0:
						err = "\"%s\" is not a positive number of watts" % s
						break
					ftps.append(float(s))
				out["ftp"] = ftps
			"unverified":
				out["unverified"] = _bool_value(v)
			"headless":
				out["headless"] = _bool_value(v)
			"windowed":
				out["headless"] = not _bool_value(v)
			"haptics-off":
				var hl := _int_list(v, 0)
				if hl.is_empty():
					err = "must be a list of slots"
				out["haptics_off"] = hl
			"at":
				var at: Array[float] = []
				for part in v.split(","):
					var s := part.strip_edges()
					if not s.is_valid_float() or float(s) < 0.0:
						err = "\"%s\" is not a time in seconds" % s
						break
					at.append(float(s))
				out["at"] = at
			"options":
				var o: Variant = WlGameRegistry.parse_json(v)
				if not (o is Dictionary):
					err = "must be a JSON object"
				else:
					out["options"] = o
			"player-options":
				var po: Variant = WlGameRegistry.parse_json(v)
				if not (po is Array):
					err = "must be a JSON array with one object per human slot"
				else:
					for e: Variant in po:
						if not (e is Dictionary):
							err = "every entry must be a JSON object"
					out["player_options"] = po
			"override":
				var path := _abs_path(v)
				if not FileAccess.file_exists(path):
					err = "%s does not exist" % v
				else:
					var ov: Variant = WlGameRegistry.parse_json(FileAccess.get_file_as_string(path))
					if not (ov is Dictionary):
						err = "%s must hold a JSON object {\"<file under content/<id>/>\": <merge patch>}" % v
					else:
						out["override"] = ov
						out["override_path"] = v
		if err != "":
			return {"error": "--%s: %s" % [key, err]}
	return out


## The args with every default filled in.
static func default_args() -> Dictionary:
	return {
		"game": "", "content": "", "players": 1, "bots": 0, "riders": [] as Array[String],
		"sim_speed": 1.0, "seed": 1, "report": "", "autopilot": "all", "ftp": [] as Array[float],
		"unverified": false, "haptics_off": [] as Array[int], "options": {}, "player_options": [],
		"override": {}, "override_path": "", "max_sim_seconds": 0.0, "headless": true,
		"at": [] as Array[float], "screenshot_dir": "",
	}


## "" on success, else an error (invalid args, invalid game, invalid plan).
func setup(p_args: Dictionary) -> String:
	if host != null:
		return "setup: already set up"
	if p_args.has("error"):
		return str(p_args["error"])
	args = default_args()
	for k: Variant in p_args.keys():
		args[k] = p_args[k]
	_wall_start_ms = Time.get_ticks_msec()
	_utc_start = int(args.get("utc_start_unix", int(Time.get_unix_time_from_system())))
	registry = args.get("registry") as WlGameRegistry
	if registry == null:
		registry = GameHost._autoload("GameRegistry") as WlGameRegistry
	if registry == null:
		registry = WlGameRegistry.new()
		registry.scan_on_ready = false
		add_child(registry)
		registry.scan()
	var game_id := str(args["game"])
	if game_id == "":
		return "--game: required"
	if not registry.has_game(game_id):
		return "--game: unknown game \"%s\" (registered: %s)" % [game_id, ", ".join(PackedStringArray(registry.ids()))]
	manifest = registry.manifest(game_id)
	var content := str(args["content"])
	if content == "":
		content = str(manifest["default_content"])
		args["content"] = content
	if not WlGameRegistry.content_allowed(manifest, content):
		var schemes: Array = manifest.get("content_schemes", [])
		return "--content: \"%s\" is not one of %s%s" % [content, ", ".join(PackedStringArray(manifest["contents"])),
			" (or <scheme>:<value> for %s)" % ", ".join(PackedStringArray(schemes)) if not schemes.is_empty() else ""]
	var players := int(args["players"])
	var bots := int(args["bots"])
	if players < 1:
		return "--players: at least 1"
	if bots < 0:
		return "--bots: must be >= 0"
	if bots > 0 and not bool(manifest["bots"]):
		return "--bots: %s does not allow bots" % game_id
	var total := players + bots
	if total < int(manifest["min_players"]) or total > int(manifest["max_players"]):
		return "--players: %d riders (players + bots) is outside %s's %d..%d" % [total, game_id, int(manifest["min_players"]), int(manifest["max_players"])]
	var specs_err := _resolve_specs(players)
	if specs_err != "":
		return specs_err
	var ftps: Array[float] = []
	var ftp_err := _resolve_ftps(players, total, ftps)
	if ftp_err != "":
		return ftp_err
	var autopilot: Variant = args["autopilot"]
	var ap_slots: Array[int] = []
	if autopilot is Array:
		for s: Variant in autopilot:
			if int(s) < 0 or int(s) >= players:
				return "--autopilot: slot %d is not a human slot (0..%d)" % [int(s), players - 1]
			ap_slots.append(int(s))
	elif str(autopilot) != "all" and str(autopilot) != "none":
		return "--autopilot: must be all, none or a list of slots"
	var hoff: Array[int] = []
	for s: Variant in args["haptics_off"]:
		if int(s) < 0 or int(s) >= total:
			return "--haptics-off: slot %d does not exist (0..%d)" % [int(s), total - 1]
		hoff.append(int(s))
	var opts: Variant = args["options"]
	if not (opts is Dictionary):
		return "--options: must be a JSON object"
	var oerr := registry.check_option_values(game_id, opts)
	if oerr != "":
		return "--" + oerr
	var pops: Variant = args["player_options"]
	if not (pops is Array):
		return "--player-options: must be a JSON array"
	if (pops as Array).size() > players:
		return "--player-options: %d entries for %d human slots" % [(pops as Array).size(), players]
	for i in (pops as Array).size():
		if not (pops[i] is Dictionary):
			return "--player-options[%d]: must be a JSON object" % i
		var perr := registry.check_option_values(game_id, pops[i], true)
		if perr != "":
			return "--player-options[%d].%s" % [i, perr.trim_prefix("player_options.")]
	var ov: Variant = args["override"]
	if not (ov is Dictionary):
		return "--override: must be a JSON object"
	for rel: Variant in (ov as Dictionary).keys():
		var p := registry.content_dir(game_id).path_join(str(rel))
		if not FileAccess.file_exists(p):
			return "--override: %s does not exist" % p
	role = Wl.SOLO if players == 1 else Wl.HOST
	var p_seed := int(args["seed"])
	# Isolation: every persisted file of this run lives under a temp root.
	_temp_root = Paths.make_temp_dir("wattlands_sim")
	_prev_paths_override = Paths.get_override()
	Paths.set_override(_temp_root)
	_paths_overridden = true
	_fit_targets.clear()
	var report_path := _abs_path(str(args["report"]))
	for i in players:
		if report_path != "":
			_fit_targets.append(report_path.get_base_dir().path_join("fit").path_join("%s_slot%d.fit" % [report_path.get_file().get_basename(), i]))
		else:
			_fit_targets.append(_temp_root.path_join("fit").path_join("sim_slot%d.fit" % i))
	# Network peers.
	var peer_ids: Array[int] = [Wl.HOST_PEER]
	if role == Wl.HOST:
		var made: Variant = _make_nets(players)
		if made is String:
			return str(made)
		for n: Variant in made:
			nets.append(n as WlNetSession)
		peer_ids.clear()
		for n in nets:
			peer_ids.append(n.local_peer)
	# Slots.
	slots.clear()
	var profiles: Array[RiderProfile] = []
	for i in players:
		var prof := RiderProfile.new()
		prof.display_name = "Rider %d" % (i + 1)
		prof.ftp_w = ftps[i]
		prof.cp_w = ftps[i]
		prof.ftp_verified = not bool(args["unverified"])
		prof.haptics_on = not hoff.has(i)
		prof.autopilot_default = str(autopilot) == "all" or ap_slots.has(i)
		prof.created = true
		var slot := prof.to_slot(peer_ids[i], Wl.FAIR_FTP)
		slot.apply_look(i)
		if i < (pops as Array).size():
			slot.options = (pops[i] as Dictionary).duplicate(true)
		profiles.append(prof)
		slots.append(slot)
	for n in range(1, bots + 1):
		var idx := players + n - 1
		var bslot := Bots.make_slot(n, idx, ftps[idx], Wl.FAIR_FTP)
		bslot.haptics_on = not hoff.has(idx)
		var bprof := Bots.make_profile(n, ftps[idx])
		profiles.append(bprof)
		slots.append(bslot)
	# Riders.
	for i in slots.size():
		var slot := slots[i]
		var spec := slot_specs[i] if i < players else Bots.RIDER_SPEC
		var rider := _make_rider(slot, profiles[i], spec)
		if rider == null:
			return "--rider: could not build a rider for slot %d" % i
		riders[slot.peer_id] = rider
	# Host.
	var host_riders := {}
	host_riders[peer_ids[0]] = riders[peer_ids[0]]
	for i in range(players, slots.size()):
		host_riders[slots[i].peer_id] = riders[slots[i].peer_id]
	host = GameHost.new()
	host.name = "Host"
	add_child(host)
	var headless := bool(args["headless"])
	var cfg := {
		"game_id": game_id, "content_id": content, "seed": p_seed, "role": role,
		"players": slots.duplicate(), "local_riders": host_riders, "local_peer": peer_ids[0],
		"net": nets[0] if not nets.is_empty() else null, "bus": _new_bus("HostBus"),
		"options": (opts as Dictionary).duplicate(true), "scaling_mode": Wl.FAIR_FTP,
		"sim_speed": float(args["sim_speed"]), "headless": headless, "realtime": false,
		"view_parent": self, "hud_parent": self, "record_rides": true, "report": true,
		"registry": registry, "progress_path": _progress_path(0, game_id),
		"content_overrides": (ov as Dictionary).duplicate(true),
		"fit_paths": {peer_ids[0]: _fit_targets[0]}, "input_router": null,
		# No per-session nonce: a simulation's results.session_id stays game/content/seed, so two
		# runs with the same arguments keep the same deterministic_hash (each run has its own
		# temp profile, so the id never meets an earlier session's progress).
		"session_nonce": "",
	}
	var err := host.setup(cfg)
	if err != "":
		return err
	for i in range(1, players):
		var c := GameHost.new()
		c.name = "Client%d" % i
		add_child(c)
		var ccfg := {
			"role": Wl.CLIENT, "local_peer": peer_ids[i], "local_riders": {peer_ids[i]: riders[peer_ids[i]]},
			"net": nets[i], "bus": _new_bus("ClientBus%d" % i), "registry": registry,
			"headless": true, "realtime": false, "record_rides": true, "report": true,
			"progress_path": _progress_path(i, game_id), "fit_paths": {peer_ids[i]: _fit_targets[i]},
			"input_router": null,
		}
		var cerr := c.setup(ccfg)
		if cerr != "":
			return "client %d: %s" % [i, cerr]
		clients.append(c)
	max_sim_seconds = float(args["max_sim_seconds"])
	if max_sim_seconds <= 0.0:
		var longest := 0.0
		for peer: int in host.plans.keys():
			longest = maxf(longest, (host.plans[peer] as EffortPlan).max_length_s())
		max_sim_seconds = longest + TIMEOUT_MARGIN_S
	host.start()
	for c in clients:
		c.start()
	return ""


## One fixed platform step for every peer (host first, then clients, then loopback poll).
func step() -> void:
	if host == null:
		return
	host.step()
	for c in clients:
		c.step()
	_ticks += 1


## Run until the cool-down finishes, max_sim_seconds, or 120 s of platform time paused
## (SOLO). Returns end_reason: "complete", "timeout" or "paused".
func run_to_end() -> String:
	if host == null:
		return "timeout"
	var max_ticks := ceili(max_sim_seconds / DT - 1e-6)
	var paused_limit := PhaseTracker.ticks(PAUSED_END_S)
	var reason := ""
	while reason == "":
		if host.is_finished():
			reason = "complete"
			break
		if _ticks >= max_ticks:
			reason = "timeout"
			break
		step()
		if role == Wl.SOLO and host.is_paused():
			_paused_ticks += 1
			if _paused_ticks >= paused_limit:
				reason = "paused"
		else:
			_paused_ticks = 0
	end_reason = reason
	host.end_session(reason)
	var extra := 0
	while extra < CLIENT_DRAIN_TICKS and not _clients_done():
		step()
		extra += 1
	for c in clients:
		if not c.is_finished():
			c.end_session(reason)
	_wall_s = (Time.get_ticks_msec() - _wall_start_ms) / 1000.0
	return reason


## Platform seconds simulated so far.
func sim_seconds() -> float:
	return _ticks * DT


## The JSON report (BRIEF 3.6): schema, args, slots, plans, plan_warnings, overrides,
## end_reason, finished_reason, events, phases, directives (requested and applied), 1 Hz
## traces, snapshots (sha256 and JSON byte size: UTF-8 length of JSON.stringify(state)),
## max_snapshot_bytes, oversize_snapshots, results, fit_paths, meta, deterministic_hash
## (sha256 of the report without paths and wall-clock fields).
func build_report() -> Dictionary:
	if host == null:
		return {}
	var hd := host.report_data()
	var r := {}
	r["schema"] = REPORT_SCHEMA
	r["args"] = _report_args()
	r["game_id"] = str(manifest.get("id", ""))
	r["content_id"] = str(args.get("content", ""))
	r["role"] = role
	r["seed"] = int(args.get("seed", 0))
	var slot_rows: Array = []
	for i in slots.size():
		var s := slots[i]
		slot_rows.append({
			"slot": s.slot_index, "peer": s.peer_id, "name": s.name, "is_bot": s.is_bot,
			"ftp": s.ftp, "ftp_verified": s.ftp_verified,
			"rider": slot_specs[i] if i < slot_specs.size() else Bots.RIDER_SPEC,
			"autopilot": s.autopilot, "haptics_on": s.haptics_on, "options": s.options.duplicate(true),
		})
	r["slots"] = slot_rows
	r["plans"] = hd.get("plans", {})
	r["plan_warnings"] = hd.get("plan_warnings", {})
	r["overrides"] = (args.get("override", {}) as Dictionary).duplicate(true)
	r["end_reason"] = end_reason
	r["finished_reason"] = str(hd.get("finished_reason", ""))
	r["sim_seconds"] = sim_seconds()
	r["game_seconds"] = float(hd.get("game_seconds", 0.0))
	r["max_sim_seconds"] = max_sim_seconds
	r["events"] = hd.get("events", [])
	r["phases"] = hd.get("phases", {})
	r["directives"] = hd.get("directives", [])
	r["directives_unmatched"] = hd.get("directives_unmatched", [])
	r["trace"] = hd.get("trace", {})
	r["snapshots"] = hd.get("snapshots", [])
	r["max_snapshot_bytes"] = int(hd.get("max_snapshot_bytes", 0))
	r["oversize_snapshots"] = int(hd.get("oversize_snapshots", 0))
	var res := host.final_results()
	r["results"] = res.to_dict() if res != null else {}
	var unl := {str(host.local_peer()): host.unlocks.duplicate(true)}
	var peers_out: Array = []
	for c in clients:
		unl[str(c.local_peer())] = c.unlocks.duplicate(true)
		var cd := c.report_data()
		peers_out.append({
			"peer": c.local_peer(), "state": c.state, "events": cd.get("events", []),
			"directives": cd.get("directives", []), "trace": cd.get("trace", {}),
			"results_grade": c.final_results().grade if c.final_results() != null else "",
		})
	r["unlocks"] = unl
	r["clients"] = peers_out
	var fits: Array = []
	for i in slots.size():
		var s := slots[i]
		if s.is_bot:
			continue
		var gh: GameHost = host if i == 0 else (clients[i - 1] if i - 1 < clients.size() else null)
		if gh != null and gh.fit_paths().has(s.peer_id):
			fits.append(str(gh.fit_paths()[s.peer_id]))
	r["fit_paths"] = fits
	r["meta"] = {
		"wall_s": _wall_s, "utc_start_unix": _utc_start,
		"godot": str(Engine.get_version_info().get("string", "")),
		"report": str(args.get("report", "")), "temp_root": _temp_root,
	}
	r["deterministic_hash"] = deterministic_hash(r)
	return r


## sha256 of the canonical (sorted-key) JSON of `report` without fit_paths, meta, the
## hash itself and the path-like args.
static func deterministic_hash(report: Dictionary) -> String:
	var copy := report.duplicate(true)
	copy.erase("fit_paths")
	copy.erase("meta")
	copy.erase("deterministic_hash")
	if copy.get("args") is Dictionary:
		for k in UNHASHED_ARGS:
			(copy["args"] as Dictionary).erase(k)
	return JSON.stringify(copy, "", true).sha256_text()


## Write the report to args.report (and FIT files under <report dir>/fit/). Returns path.
func write_report() -> String:
	var path := _abs_path(str(args.get("report", "")))
	if path == "" or host == null:
		return ""
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("GameSimRunner: cannot write %s" % path)
		return ""
	f.store_string(JSON.stringify(build_report(), "\t"))
	f.close()
	return path


# --- additive API ------------------------------------------------------------------------


## Shut the riders down, restore Paths' override and delete the run's temp root (FIT files
## written next to a report stay).
func cleanup() -> void:
	for peer: int in riders.keys():
		var r: LocalRider = riders[peer]
		if is_instance_valid(r):
			r.shutdown()
	_restore_paths()
	if _temp_root != "":
		_remove_tree(_temp_root)
		_temp_root = ""


## Every GameHost in stepping order (host first).
func hosts() -> Array[GameHost]:
	var out: Array[GameHost] = []
	if host != null:
		out.append(host)
	out.append_array(clients)
	return out


## The temp root holding this run's profile dirs.
func temp_root() -> String:
	return _temp_root


# --- internals --------------------------------------------------------------------------


func _resolve_specs(players: int) -> String:
	slot_specs.clear()
	var given: Array = args["riders"]
	if given.is_empty():
		for i in players:
			slot_specs.append(DEFAULT_RIDER)
	elif given.size() == 1:
		for i in players:
			slot_specs.append(str(given[0]))
	elif given.size() == players:
		for s: Variant in given:
			slot_specs.append(str(s))
	else:
		return "--rider: give one profile, or one per human slot (%d), not %d" % [players, given.size()]
	for s in slot_specs:
		if MockTrainer.parse_spec(s).is_empty():
			return "--rider: \"%s\" is not a valid mock rider profile" % s
	return ""


func _resolve_ftps(players: int, total: int, out: Array[float]) -> String:
	var given: Array = args["ftp"]
	if given.is_empty():
		for i in total:
			out.append(DEFAULT_FTP)
	elif given.size() == 1:
		for i in total:
			out.append(float(given[0]))
	elif given.size() == players:
		for i in total:
			out.append(float(given[i]) if i < players else float(given[0]))
	elif given.size() == total:
		for v: Variant in given:
			out.append(float(v))
	else:
		return "--ftp: give one value, one per human slot (%d) or one per slot (%d), not %d" % [players, total, given.size()]
	for v in out:
		if v <= 0.0:
			return "--ftp: every FTP must be positive"
	return ""


func _make_nets(count: int) -> Variant:
	var factory: Variant = args.get("net_factory")
	if factory is Callable and (factory as Callable).is_valid():
		var made: Variant = (factory as Callable).call(count)
		if made is String:
			return made
		if not (made is Array) or (made as Array).size() != count:
			return "net: the net factory returned no sessions"
		for n: Variant in made:
			if n is Node and (n as Node).get_parent() == null:
				add_child(n)
		return made
	return _make_loopback_nets(count)


func _make_loopback_nets(count: int) -> Variant:
	var hub: RefCounted = LoopbackTransport.create_hub()
	var out: Array = []
	for i in count:
		var t := LoopbackTransport.hub_transport(hub)
		var s := WlNetSession.new()
		s.name = "Net%d" % i
		add_child(s)
		s.use_transport(t)
		if t.get_parent() == null:
			s.add_child(t)
		out.append(s)
	var host_net: WlNetSession = out[0]
	host_net.host_room(Wl.MAX_SLOTS)
	if not _pump(out, func() -> bool: return host_net.room_code != "" and host_net.local_peer != 0):
		return "net: the loopback host never opened a room (LoopbackTransport/WlNetSession not ready)"
	for i in range(1, count):
		var cn: WlNetSession = out[i]
		cn.join_room(host_net.room_code)
		if not _pump(out, func() -> bool: return cn.local_peer != 0):
			return "net: loopback client %d never joined room %s" % [i, host_net.room_code]
	# mark_started() fixes the session's players from the host's lobby, which lists a peer only
	# once its player_info arrived; a client still missing then would be refused with
	# session_in_progress and never get session_start.
	if not _pump(out, func() -> bool: return host_net.peers().size() == count):
		return "net: the loopback host never listed all %d riders in its lobby" % count
	host_net.mark_started()
	return out


static func _pump(sessions: Array, done: Callable, max_iter: int = 400) -> bool:
	for k in max_iter:
		for s: Variant in sessions:
			(s as WlNetSession).poll()
		if done.call():
			return true
	return false


func _make_rider(slot: PlayerSlot, profile: RiderProfile, spec: String) -> LocalRider:
	var opts := {
		"multiplayer": role != Wl.SOLO or slot.is_bot, "scaling_mode": slot.scaling_mode,
		"record": not slot.is_bot, "game_id": str(manifest.get("id", "")),
		"content_id": str(args.get("content", "")), "utc_start_unix": _utc_start,
		"seed": SeededRng.derive(int(args.get("seed", 0)), "rider:slot%d" % slot.slot_index),
		"skip_warmup": false,
	}
	var factory: Variant = args.get("rider_factory")
	var rider: LocalRider = null
	if factory is Callable and (factory as Callable).is_valid():
		rider = (factory as Callable).call(slot, profile, spec, opts) as LocalRider
	else:
		var device := MockTrainer.from_spec(spec, slot.ftp, {
			"seed": SeededRng.derive(int(args.get("seed", 0)), "mock:slot%d" % slot.slot_index),
			"preferred_cadence_rpm": slot.preferred_cadence_rpm,
		})
		rider = LocalRider.new()
		rider.setup(slot.peer_id, profile, slot, device, opts)
		if device.get_parent() == null:
			rider.add_child(device)
	if rider == null:
		return null
	rider.name = "Rider%d" % slot.slot_index
	if rider.get_parent() == null:
		add_child(rider)
	if rider.slot == null:
		rider.slot = slot
	if rider.peer_id == 0:
		rider.peer_id = slot.peer_id
	if rider.profile == null:
		rider.profile = profile
	rider.is_bot = slot.is_bot
	return rider


func _new_bus(bus_name: String) -> WlEventBus:
	var b := WlEventBus.new()
	b.name = bus_name
	add_child(b)
	return b


func _progress_path(slot_index: int, game_id: String) -> String:
	return _temp_root.path_join("slot%d" % slot_index).path_join("games").path_join(game_id).path_join("progress.json")


func _clients_done() -> bool:
	for c in clients:
		if c.final_results() == null and c.state != "ended":
			return false
	return true


func _report_args() -> Dictionary:
	var out := {}
	for k: Variant in args.keys():
		var v: Variant = args[k]
		if v is Callable or v is Object:
			continue
		if v is Array:
			out[k] = Array(v).duplicate(true)
		elif v is Dictionary:
			out[k] = (v as Dictionary).duplicate(true)
		else:
			out[k] = v
	out.erase("utc_start_unix")
	return out


func _restore_paths() -> void:
	if _paths_overridden:
		Paths.set_override(_prev_paths_override)
		_paths_overridden = false


## Report and override paths: relative paths are relative to the project folder (the repo
## root, where the tools run).
static func _abs_path(p: String) -> String:
	if p == "":
		return ""
	if p.begins_with("res://") or p.begins_with("user://"):
		return ProjectSettings.globalize_path(p)
	if p.is_absolute_path():
		return p.replace("\\", "/")
	return ProjectSettings.globalize_path("res://").path_join(p)


static func _int_flag(out: Dictionary, key: String, v: String, lo: int, hi: int) -> String:
	if not v.is_valid_int() or int(v) < lo or int(v) > hi:
		return "must be a whole number %d..%d" % [lo, hi]
	out[key] = int(v)
	return ""


static func _float_flag(out: Dictionary, key: String, v: String, lo: float, inclusive: bool) -> String:
	if not v.is_valid_float() or float(v) < lo or (not inclusive and float(v) <= lo):
		return "must be a number above %s" % str(lo)
	out[key] = float(v)
	return ""


static func _int_list(v: String, lo: int) -> Array[int]:
	var out: Array[int] = []
	for part in v.split(","):
		var s := part.strip_edges()
		if s == "":
			continue
		if not s.is_valid_int() or int(s) < lo:
			return [] as Array[int]
		out.append(int(s))
	return out


static func _bool_value(v: String) -> bool:
	var s := v.to_lower()
	return not (s == "false" or s == "0" or s == "no" or s == "off")


static func _remove_tree(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = true
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in da.get_directories():
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)
