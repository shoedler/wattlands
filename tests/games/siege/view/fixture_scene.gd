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
##   cooldown            the victory march

var view: SiegeView = null
var state: SiegeState = null
var _t: float = 0.0


func _ready() -> void:
	var opts := _options()
	state = SiegeFixtures.cap() if opts.has("cap") else SiegeFixtures.mid_wave()
	if opts.has("empty"):
		state.enemies.clear()
		state.shots.clear()
		state.zones.clear()
	if opts.has("gate"):
		state.gate_hp = float(opts["gate"])
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
	_step()


## Advances the state one tick (a firing tower now and then) and draws it.
func _step() -> void:
	state.tick += 1
	view.refresh(0.05)


func _process(delta: float) -> void:
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
