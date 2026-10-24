class_name FishingAudio
extends Node
## Turbo Reel's sound, all synthesized with Sfx.synth (no files, no downloads): the brass
## drivetrain's hum pitched by the local rider's cadence, winch clicks at a rate set by the line
## coming in, a drag scream while the local fish runs, splashes, the bite bell, the snap twang,
## a three-note landing fanfare, gulls near the harbour and a looping surf bed. A child of
## FishingView: cue() plays what a FishingCues cue calls for (other riders' cues quieter),
## update() keeps the loops and the clicks going. Headless runs create no players and play
## nothing; `played` still records every sound asked for (tests read and clear it). The
## metronome is the platform's (GAME_SDK 18).

const SOUNDS := {
	"fishing_click": ["square", 1900.0, 0.018, 0.001, 0.012],
	"fishing_splash": ["noise", 0.0, 0.32, 0.004, 0.26],
	"fishing_plop": ["sine", 260.0, 0.12, 0.002, 0.09],
	"fishing_bell": ["sine", 1320.0, 0.9, 0.002, 0.8],
	"fishing_twang": ["saw", 196.0, 0.45, 0.001, 0.4],
	"fishing_gull": ["triangle", 1450.0, 0.22, 0.03, 0.15],
	"fishing_zip": ["saw", 520.0, 0.25, 0.005, 0.18],
	"fishing_clunk": ["square", 140.0, 0.08, 0.001, 0.06],
	"fishing_note_1": ["triangle", 523.25, 0.18, 0.005, 0.1],
	"fishing_note_2": ["triangle", 659.25, 0.18, 0.005, 0.1],
	"fishing_note_3": ["triangle", 783.99, 0.5, 0.005, 0.35],
	"fishing_horn": ["saw", 147.0, 0.9, 0.06, 0.5],
}
const LOOP_SURF := "fishing_surf"
const LOOP_DRAG := "fishing_drag"
const LOOP_HUM := "fishing_hum"
const FANFARE: Array = [[0.0, "fishing_note_1"], [0.16, "fishing_note_2"], [0.32, "fishing_note_3"]]
## Winch clicks: one per this many metres of line; never faster than CLICK_MIN_S apart.
const CLICK_PER_M := 0.25
const CLICK_MIN_S := 0.03
## The hum: silent under HUM_MIN_RPM, pitch 1 at HUM_REF_RPM.
const HUM_MIN_RPM := 20.0
const HUM_REF_RPM := 90.0
const HUM_DB := -26.0
const GULL_EVERY_S := 5.0
## Gulls call while the local boat is within this far of the dock (m).
const GULL_RANGE_M := 250.0
const OTHER_DB := -10.0

## Every sound the last calls asked for, newest last (tests).
var played: Array[String] = []
var silent: bool = true
var surf: AudioStreamPlayer = null
var drag: AudioStreamPlayer = null
var hum: AudioStreamPlayer = null
## The loops' state (tests read it headless too).
var drag_on: bool = false
var hum_on: bool = false
var hum_pitch: float = 1.0

var _sfx: WlSfx = null
var _click_m: float = 0.0
var _click_wait: float = 0.0
var _gull_t: float = 0.0
var _queue: Array = []
var _clock: float = 0.0


func _ready() -> void:
	name = "FishingAudio"
	_sfx = get_node_or_null("/root/Sfx") as WlSfx
	silent = DisplayServer.get_name() == "headless" or _sfx == null
	_register()
	if not silent:
		surf = _loop_player(LOOP_SURF, "noise", 0.0, -30.0)
		drag = _loop_player(LOOP_DRAG, "saw", 1250.0, -24.0)
		hum = _loop_player(LOOP_HUM, "saw", 55.0, HUM_DB)
		surf.play()


## Every sound name this game registers (credits: "synthesized").
static func sound_names() -> Array[String]:
	var out: Array[String] = []
	for k: String in SOUNDS:
		out.append(k)
	out.append_array([LOOP_SURF, LOOP_DRAG, LOOP_HUM])
	return out


## The sounds of one cue; `local` is true for the local rider (full volume).
func cue(c: Dictionary, local: bool) -> void:
	var db := 0.0 if local else OTHER_DB
	match str(c.get("k", "")):
		FishingCues.CUE_CAST:
			_play("fishing_clunk", -10.0 + db)
			_play("fishing_plop", -8.0 + db)
		FishingCues.CUE_BITE:
			_play("fishing_bell", -4.0 + db)
		FishingCues.CUE_HOOKUP:
			_play("fishing_zip", -8.0 + db)
			_play("fishing_splash", -10.0 + db)
		FishingCues.CUE_THROWN:
			_play("fishing_splash", -8.0 + db)
		FishingCues.CUE_RUN:
			_play("fishing_zip", -6.0 + db, 1.3)
		FishingCues.CUE_JUMP:
			_play("fishing_splash", -5.0 + db)
		FishingCues.CUE_SNAP:
			_play("fishing_twang", -4.0 + db)
		FishingCues.CUE_TURN:
			_play("fishing_clunk", -12.0 + db, 0.8)
		FishingCues.CUE_LANDED:
			_play("fishing_splash", -10.0 + db)
			for note: Array in FANFARE:
				_queue.append([_clock + float(note[0]), str(note[1]), -6.0 + db])
		FishingCues.CUE_DOUBLE_HOOKUP:
			_play("fishing_bell", -6.0, 1.5)
		FishingCues.CUE_TIME_UP:
			_play("fishing_horn", -10.0, 1.2)
		FishingCues.CUE_TRIP_OVER:
			_play("fishing_horn", -6.0)


## Loops and clicks for one frame: the local rider `r` (null without one) and its winch's line
## speed `winch_mps` (positive reeling in).
func update(dt: float, r: FishingRiderState, winch_mps: float) -> void:
	_clock += dt
	_flush_queue()
	var running := r != null and r.action == FishingConst.A_FIGHT and r.fish.run_active
	_set_drag(running)
	var cad := r.cadence_ema if r != null else 0.0
	_set_hum(cad >= HUM_MIN_RPM, clampf(cad / HUM_REF_RPM, 0.5, 1.6))
	_click_wait -= dt
	if winch_mps > 0.0:
		_click_m += winch_mps * dt
	if not running and _click_m >= CLICK_PER_M and _click_wait <= 0.0:
		_click_m = 0.0
		_click_wait = CLICK_MIN_S
		_play("fishing_click", -20.0)
	elif _click_m > CLICK_PER_M * 4.0:
		_click_m = CLICK_PER_M
	_gull_t -= dt
	if r != null and r.x_m < GULL_RANGE_M and _gull_t <= 0.0:
		_gull_t = GULL_EVERY_S
		_play("fishing_gull", -18.0, 0.9 + 0.2 * float(int(_clock * 7.0) % 3))


func _set_hum(on: bool, pitch: float) -> void:
	hum_pitch = pitch
	if hum != null:
		hum.pitch_scale = pitch
	if on == hum_on:
		return
	hum_on = on
	if on:
		played.append(LOOP_HUM)
	if hum != null:
		if on:
			hum.play()
		else:
			hum.stop()


func _set_drag(on: bool) -> void:
	if on == drag_on:
		return
	drag_on = on
	if on:
		played.append(LOOP_DRAG)
	if drag != null:
		if on:
			drag.play()
		else:
			drag.stop()


func _flush_queue() -> void:
	var i := 0
	while i < _queue.size():
		var q: Array = _queue[i]
		if float(q[0]) <= _clock:
			_play(str(q[1]), float(q[2]))
			_queue.remove_at(i)
		else:
			i += 1


func _register() -> void:
	if _sfx == null:
		return
	for key: String in SOUNDS:
		if _sfx.has_sound(key):
			continue
		var d: Array = SOUNDS[key]
		var stream := _sfx.synth(str(d[0]), float(d[1]), float(d[2]), float(d[3]), float(d[4]))
		if stream != null:
			_sfx.register(key, stream)


func _loop_player(key: String, kind: String, hz: float, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = key
	p.volume_db = db
	if _sfx != null:
		p.stream = _sfx.synth(kind, hz, 2.0, 0.0, 0.0, true)
	add_child(p)
	return p


func _play(sound: String, db: float = -6.0, pitch: float = 1.0) -> void:
	played.append(sound)
	if played.size() > 128:
		played.pop_front()
	if _sfx != null and not silent:
		_sfx.play(sound, db, pitch)
