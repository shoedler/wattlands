class_name AudioBuses
extends RefCounted
## The audio buses (SPEC_AUDIO 1.4): Master, Machines, Ambience, Sfx, UI. Created in code, so no project.godot edit and
## no default_bus_layout.tres. Static over AudioServer. WlSfx calls ensure() in _ready and tick() in _process.
## Master and UI are never ducked: a safety prompt plays on Master and no sub-slider or duck can hide it. WlSfx trims
## the UI's own voices under a prompt, one by one, because the start count on UI must keep its level.
const MASTER := "Master"
const MACHINES := "Machines"
const AMBIENCE := "Ambience"
const SFX := "Sfx"
const UI := "UI"
const ALL: Array[String] = [MACHINES, AMBIENCE, SFX, UI]
const SETTING_KEYS := {
	MACHINES: "bus_machines_db",
	AMBIENCE: "bus_ambience_db",
	SFX: "bus_sfx_db",
	UI: "bus_ui_db",
}
const LIMITER_CEILING_DB := -1.0

static var _user: Dictionary = {}
static var _ducks: Array[Dictionary] = []


## Idempotent: the four buses send to Master, and Master holds one hard limiter.
static func ensure() -> void:
	for bus: String in ALL:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus)
		AudioServer.set_bus_send(i, MASTER)
	var master := AudioServer.get_bus_index(MASTER)
	for e in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, e) is AudioEffectHardLimiter:
			return
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = LIMITER_CEILING_DB
	AudioServer.add_bus_effect(master, limiter)


static func set_user_db(bus: String, db: float) -> void:
	_user[bus] = db
	_apply(bus)


static func user_db(bus: String) -> float:
	return float(_user.get(bus, 0.0))


## A scalar envelope on the bus volume, testable and identical to the offline preview. Deepest wins while several run.
static func duck(bus: String, db: float, attack_s: float, release_s: float) -> void:
	if bus == MASTER or bus == UI:
		push_warning("AudioBuses: %s is never ducked" % bus)
		return
	_ducks.append({"bus": bus, "db": db, "attack": attack_s, "release": release_s, "t": 0.0})


static func duck_db(bus: String) -> float:
	var deepest := 0.0
	for d: Dictionary in _ducks:
		if d["bus"] == bus:
			deepest = minf(deepest, _envelope(d))
	return deepest


## Bus volume = user_db + duck envelope.
static func tick(dt: float) -> void:
	var live: Array[Dictionary] = []
	for d: Dictionary in _ducks:
		d["t"] = float(d["t"]) + dt
		if float(d["t"]) < float(d["attack"]) + float(d["release"]):
			live.append(d)
	_ducks = live
	for bus: String in ALL:
		_apply(bus)


## The user's four bus levels from Settings (WlSettings).
static func apply_settings(settings: Node) -> void:
	for bus: String in ALL:
		set_user_db(bus, float(settings.call("get_value", SETTING_KEYS[bus], 0.0)))


## Tests: drop every running duck.
static func clear_ducks() -> void:
	_ducks.clear()
	for bus: String in ALL:
		_apply(bus)


static func _envelope(d: Dictionary) -> float:
	var t := float(d["t"])
	var attack := float(d["attack"])
	var depth := float(d["db"])
	if t < attack:
		return depth * t / attack
	var release := float(d["release"])
	return depth * (1.0 - (t - attack) / release) if release > 0.0 and t < attack + release else 0.0


static func _apply(bus: String) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, user_db(bus) + duck_db(bus))
