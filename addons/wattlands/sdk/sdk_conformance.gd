class_name SdkConformance
extends RefCounted
## The SDK conformance checks (BRIEF 3.6 "Conformance", 7.3; docs/OWNERSHIP.md TL8, REG6,
## REG7, C9) for any game in a registry, with no per-game code. tests/sdk/test_conformance.gd
## runs them for `_template` (loaded explicitly) and every registered game:
##   - game.json validates (naming the failing field) and content/<id>/strings.csv keys carry
##     the game's <ID>_ prefix;
##   - configure + plan validation for every content id at min_players and max_players;
##   - 2 minutes of headless simulation through GameSimRunner on default_content at
##     min_players and max_players, with bots when the game allows them (one human slot,
##     so SOLO) or Autopilot human slots otherwise (HOST with LoopbackTransport clients);
##   - results() with a row per rider and a grade S..D;
##   - determinism: two runs with the same seed give the same snapshot hashes;
##   - snapshot round trip: the latest snapshot survives JSON.stringify and
##     JSON.parse_string plus Protocol.apply_int_fields(int_fields()["snapshot"]) unchanged
##     (every int declared, only string keys, only JSON types), fits one relay message, and a
##     fresh CLIENT module applies it.

const SIM_SECONDS := 120.0
const SEED := 4242
## Room for the snapshot message envelope around the state.
const ENVELOPE_BYTES := 256
## GameResults.grade values (BRIEF 3.6: S to D).
const GRADES: Array[String] = ["S", "A", "B", "C", "D"]


## Errors for game `id` (empty when it conforms). `opts` is merged into every
## GameSimRunner args (tests may pass factories); `log` collects progress lines.
static func check_game(registry: WlGameRegistry, id: String, opts: Dictionary = {}, log: Array = []) -> Array[String]:
	var errors: Array[String] = []
	var m := registry.manifest(id)
	if m.is_empty():
		errors.append("%s: not in the registry" % id)
		return errors
	var err := registry.validate_manifest(m)
	if err != "":
		errors.append("%s: game.json: %s" % [id, err])
		return errors
	errors.append_array(strings_errors(id, registry.content_dir(id).path_join("strings.csv")))
	var counts := player_counts(m)
	for content: Variant in m["contents"]:
		for n in counts:
			var r := _runner(registry, id, str(content), n, m, opts, 1.0)
			var setup_err := str(r["err"])
			if setup_err != "":
				errors.append("%s/%s at %d riders: %s" % [id, str(content), n, setup_err])
			_dispose(r)
	for n in counts:
		var a := _run(registry, id, str(m["default_content"]), n, m, opts)
		var b := _run(registry, id, str(m["default_content"]), n, m, opts)
		var at := "%s at %d riders" % [id, n]
		if str(a["err"]) != "":
			errors.append("%s: %s" % [at, str(a["err"])])
			continue
		if int(a["rows"]) != n:
			errors.append("%s: results() has %d rows for %d riders" % [at, int(a["rows"]), n])
		if not GRADES.has(str(a["grade"])):
			errors.append("%s: results().grade \"%s\" is not one of S, A, B, C, D" % [at, str(a["grade"])])
		if (a["hashes"] as Array).is_empty():
			errors.append("%s: no snapshot in %d s" % [at, int(SIM_SECONDS)])
		if JSON.stringify(a["hashes"]) != JSON.stringify(b["hashes"]):
			errors.append("%s: two runs with seed %d gave different snapshot hashes (determinism)" % [at, SEED])
		if int(a["max_bytes"]) + ENVELOPE_BYTES > NetMessages.MAX_MESSAGE_BYTES or int(a["oversize"]) > 0:
			errors.append("%s: a snapshot of %d bytes does not fit one %d-byte message" % [at, int(a["max_bytes"]), NetMessages.MAX_MESSAGE_BYTES])
		var paths: Variant = (a["int_fields"] as Dictionary).get("snapshot", [])
		for e in snapshot_errors(a["snapshot"], paths if paths is Array else []):
			errors.append("%s: %s" % [at, e])
		var apply_err := client_apply_error(registry, id, a)
		if apply_err != "":
			errors.append("%s: %s" % [at, apply_err])
		log.append("conformance: %s %d riders (%s), %d snapshots, end %s" % [id, n, str(a["role"]), (a["hashes"] as Array).size(), str(a["end_reason"])])
	return errors


## The rider counts conformance runs: min_players and max_players.
static func player_counts(m: Dictionary) -> Array[int]:
	var out: Array[int] = [int(m["min_players"])]
	if int(m["max_players"]) != int(m["min_players"]):
		out.append(int(m["max_players"]))
	return out


## "" when the game.json at `path` validates, else "<field>: <reason>".
static func manifest_error(registry: WlGameRegistry, path: String) -> String:
	var parsed: Variant = WlGameRegistry.load_manifest_file(path)
	if not (parsed is Dictionary):
		return "game.json: not a JSON object"
	return registry.validate_manifest(parsed, path)


## Keys in content/<id>/strings.csv without the game's upper-case <ID>_ prefix.
static func strings_errors(id: String, csv_path: String) -> Array[String]:
	var errors: Array[String] = []
	if not FileAccess.file_exists(csv_path):
		return errors
	var prefix := id.to_upper() + "_"
	var f := FileAccess.open(csv_path, FileAccess.READ)
	if f == null:
		errors.append("%s: cannot read %s" % [id, csv_path])
		return errors
	var first := true
	while not f.eof_reached():
		var row := f.get_csv_line()
		if first:
			first = false
			continue
		if row.is_empty() or str(row[0]).strip_edges() == "":
			continue
		var key := str(row[0]).strip_edges()
		if not key.begins_with(prefix):
			errors.append("%s: strings.csv key \"%s\" lacks the \"%s\" prefix" % [id, key, prefix])
	return errors


## Problems with `state` surviving JSON plus apply_int_fields(paths) (empty = fine).
static func snapshot_errors(state: Variant, paths: Array) -> Array[String]:
	var errors: Array[String] = []
	if not (state is Dictionary):
		errors.append("snapshot: snapshot() must return a Dictionary")
		return errors
	var text := JSON.stringify(state)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		errors.append("snapshot: does not survive JSON.stringify/parse_string")
		return errors
	var converted: Variant = Protocol.apply_int_fields(parsed, paths)
	_compare(state, converted, "snapshot", errors)
	return errors


## "" when a fresh CLIENT instance of the game configures and applies the run's latest
## snapshot after the JSON round trip.
static func client_apply_error(registry: WlGameRegistry, id: String, run: Dictionary) -> String:
	var gm := registry.instantiate(id)
	if gm == null:
		return "cannot instantiate a client module"
	var players: Array[PlayerSlot] = []
	for d: Variant in run["players"]:
		players.append(PlayerSlot.from_dict(d))
	# Like a CLIENT GameHost, the module lives in the scene tree before configure().
	var holder := Node.new()
	holder.name = "ConformanceClient"
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.add_child(holder)
	holder.add_child(gm)
	var bus := WlEventBus.new()
	holder.add_child(bus)
	var ctx := GameContext.new()
	ctx.game_id = id
	ctx.manifest = registry.manifest(id)
	ctx.players = players
	ctx.content_id = str(run["content_id"])
	ctx.seed = SEED
	ctx.role = Wl.CLIENT
	ctx.local_peer = players[players.size() - 1].peer_id if not players.is_empty() else 2
	for p in players:
		if not p.is_bot:
			ctx.local_peer = p.peer_id
	ctx.rng = SeededRng.make(SEED)
	var dr := DirectiveRouter.new()
	dr.role = Wl.CLIENT
	ctx.directives = dr
	ctx.options = (run["options"] as Dictionary).duplicate(true)
	ctx.progress = ProgressStore.open(id, "")
	var hud := HudRouter.new()
	hud.role = Wl.CLIENT
	hud.bus = bus
	ctx.hud = hud
	ctx.intents = IntentRouter.new()
	ctx.roster = {}
	ctx.strings = GameStrings.new()
	ctx.events = bus
	ctx.stats = SessionStatsTracker.new()
	ctx.game_dir = registry.game_dir(id)
	ctx.content_dir = registry.content_dir(id)
	ctx.assets_dir = registry.assets_dir(id)
	gm.configure(ctx)
	var parsed: Variant = JSON.parse_string(JSON.stringify(run["snapshot"]))
	var paths: Variant = gm.int_fields().get("snapshot", [])
	var conv: Variant = Protocol.apply_int_fields(parsed, paths if paths is Array else [])
	gm.apply_snapshot(conv if conv is Dictionary else {})
	holder.free()
	return ""


static func _runner(registry: WlGameRegistry, id: String, content: String, n: int, m: Dictionary, opts: Dictionary, seconds: float) -> Dictionary:
	var args := {
		"game": id, "content": content, "seed": SEED, "max_sim_seconds": seconds,
		"registry": registry, "headless": true, "autopilot": "all",
	}
	if bool(m["bots"]):
		args["players"] = 1
		args["bots"] = n - 1
	else:
		args["players"] = n
		args["bots"] = 0
	for k: Variant in opts.keys():
		args[k] = opts[k]
	var runner := GameSimRunner.new()
	var err := runner.setup(args)
	return {"runner": runner, "err": err}


static func _run(registry: WlGameRegistry, id: String, content: String, n: int, m: Dictionary, opts: Dictionary) -> Dictionary:
	var r := _runner(registry, id, content, n, m, opts, SIM_SECONDS)
	var out := {"err": str(r["err"]), "rows": 0, "grade": "", "hashes": [], "snapshot": {}, "int_fields": {},
		"max_bytes": 0, "oversize": 0, "role": "", "end_reason": "", "players": [], "options": {},
		"content_id": content}
	var runner: GameSimRunner = r["runner"]
	if out["err"] == "":
		out["end_reason"] = runner.run_to_end()
		var host := runner.host
		var res := host.final_results()
		out["rows"] = res.rows.size() if res != null else 0
		out["grade"] = res.grade if res != null else ""
		out["hashes"] = host.report.snapshot_hashes() if host.report != null else []
		out["snapshot"] = host.last_snapshot().duplicate(true)
		out["int_fields"] = host.game.int_fields()
		out["max_bytes"] = host.report.max_snapshot_bytes if host.report != null else 0
		out["oversize"] = host.report.oversize_snapshots if host.report != null else 0
		out["role"] = runner.role
		var ps: Array = []
		for p in host.players():
			ps.append(p.to_dict())
		out["players"] = ps
		out["options"] = host.ctx.options.duplicate(true)
	_dispose(r)
	return out


static func _dispose(r: Dictionary) -> void:
	var runner: GameSimRunner = r["runner"]
	if runner == null:
		return
	runner.cleanup()
	runner.free()


static func _compare(a: Variant, b: Variant, at: String, errors: Array[String]) -> void:
	match typeof(a):
		TYPE_NIL:
			if b != null:
				errors.append("%s: null comes back as %s" % [at, type_string(typeof(b))])
		TYPE_BOOL:
			if not (b is bool) or b != a:
				errors.append("%s: bool %s comes back as %s" % [at, str(a), JSON.stringify(b)])
		TYPE_INT:
			if not (b is int):
				errors.append("%s: int %d comes back as a float; declare it in int_fields()[\"snapshot\"]" % [at, a])
			elif b != a:
				errors.append("%s: int %d comes back as %d" % [at, a, b])
		TYPE_FLOAT:
			if not (b is float or b is int) or float(b) != float(a):
				errors.append("%s: float %s comes back as %s" % [at, str(a), JSON.stringify(b)])
		TYPE_STRING, TYPE_STRING_NAME:
			if not (b is String) or str(b) != str(a):
				errors.append("%s: string comes back changed" % at)
		TYPE_ARRAY:
			if not (b is Array) or (b as Array).size() != (a as Array).size():
				errors.append("%s: array comes back changed" % at)
				return
			for i in (a as Array).size():
				_compare(a[i], b[i], "%s[%d]" % [at, i], errors)
		TYPE_DICTIONARY:
			if not (b is Dictionary):
				errors.append("%s: dictionary comes back as %s" % [at, type_string(typeof(b))])
				return
			for k: Variant in (a as Dictionary).keys():
				if not (k is String or k is StringName):
					errors.append("%s: key %s is a %s; JSON keys are strings" % [at, str(k), type_string(typeof(k))])
					continue
				if not (b as Dictionary).has(str(k)):
					errors.append("%s.%s: missing after the round trip" % [at, str(k)])
					continue
				_compare(a[k], b[str(k)], "%s.%s" % [at, str(k)], errors)
		_:
			errors.append("%s: %s is not a JSON type" % [at, type_string(typeof(a))])
