extends Node3D
## A windowed look at the Siege view for tools/screenshot --scene (GAME_SDK 19.3): the mid-wave
## fixture (43 enemies, four towers, an Overdrive, a rescue, a reconnect) bound to a SiegeView,
## with the camera already pushed in. Not a test; the view tests build the same thing headless.
## Options (user args or the SIEGE_FIXTURE environment variable, ";"-separated):
##   cap                 the 150-enemy state
##   empty               no enemies, shots or zones
##   zoom=<m>            frame this many metres of width instead of the whole fort
##   target=x,y,z        camera target (with zoom)
##   gate=<hp>           set the gate HP
##   breach              the gate burst open
##   cooldown            the victory march
##   stats               print the frame times, draw calls and primitives after 300 frames, then quit

var view: SiegeView = null
var state: SiegeState = null
var _t: float = 0.0
var _frames: int = 0
var _times: Array[float] = []
var _stats: bool = false


func _ready() -> void:
	var opts := _options()
	state = SiegeFixtures.cap() if opts.has("cap") else SiegeFixtures.mid_wave()
	if opts.has("empty"):
		state.enemies.clear()
		state.shots.clear()
		state.zones.clear()
	if opts.has("gate"):
		state.gate_hp = float(opts["gate"])
	if opts.has("breach"):
		state.gate_hp = 30.0
		state.breach_s = 8.0
	if opts.has("cooldown"):
		state.role = SiegeIds.ROLE_COOLDOWN
	view = SiegeView.new()
	view.bind(state, state.content.map)
	add_child(view)
	view.rig.push_in(1.0, 0.0)
	if opts.has("zoom"):
		view.rig.fit_width(float(opts["zoom"]))
	if opts.has("target"):
		var t := str(opts["target"]).split(",")
		view.rig.target = Vector3(float(t[0]), float(t[1]), float(t[2]))
	_stats = opts.has("stats")
	_step()


## Advances the state one tick (a firing tower now and then) and draws it.
func _step() -> void:
	state.tick += 1
	view.refresh(0.05)


func _process(delta: float) -> void:
	_frames += 1
	if _stats and _frames > 60:
		_times.append(delta * 1000.0)
		if _frames == 360:
			_print_stats()
	# Keep the towers firing so bolts are in the air whenever a picture is taken.
	_t += delta
	if _t >= 0.2:
		_t = 0.0
		for s in state.shots:
			s.age_s = 0.0
		_step()


func _options() -> Dictionary:
	var out := {}
	var tokens: Array[String] = []
	for a in OS.get_cmdline_user_args():
		tokens.append(a.trim_prefix("--"))
	for a in OS.get_environment("SIEGE_FIXTURE").split(";", false):
		tokens.append(a)
	for tok in tokens:
		var kv := tok.split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


func _print_stats() -> void:
	var sorted := _times.duplicate()
	sorted.sort()
	var mean := 0.0
	for t in _times:
		mean += t
	mean /= float(_times.size())
	var worst := sorted.slice(maxi(sorted.size() - ceili(sorted.size() * 0.01), 0))
	var low := 0.0
	for t: float in worst:
		low += t
	low /= float(worst.size())
	var budget := SiegeViewBudget.measure(view)
	print(
		(
			(
				"siege view stats: enemies %d, mean %.2f ms, 1%% low %.2f ms, draw calls %d, primitives %d, "
				% [
					state.enemies.size(),
					mean,
					low,
					int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
					int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
				]
			)
			+ (
				"tree draw calls %d (with shadows %d), triangles %d"
				% [budget["draw_calls"], budget["draw_calls_with_shadows"], budget["triangles"]]
			)
		)
	)
	get_tree().quit()
