class_name FishingAudio
extends Node
## Turbo Reel's sound (brief 3.5 "Audio"), all synthesized with Sfx.synth (no files, no
## downloads): reel clicks at a rate set by the local line speed, a drag scream while the local
## fish runs, gulls over bird piles and in a frenzy, splashes, the strike bell, the snap twang, a
## three-note landing fanfare and a looping surf bed. A child of FishingView: cue() plays what a
## FishingCues cue calls for (other lanes' cues quieter), update() keeps the loops and the clicks
## going. Headless runs create no players and play nothing; `played` still records every sound
## asked for (tests read and clear it). The metronome is the platform's (GAME_SDK 18).

const SOUNDS := {
	"fishing_click": ["square", 1900.0, 0.018, 0.001, 0.012],
	"fishing_splash": ["noise", 0.0, 0.32, 0.004, 0.26],
	"fishing_plop": ["sine", 260.0, 0.12, 0.002, 0.09],
	"fishing_bell": ["sine", 1320.0, 0.9, 0.002, 0.8],
	"fishing_twang": ["saw", 196.0, 0.45, 0.001, 0.4],
	"fishing_gull": ["triangle", 1450.0, 0.22, 0.03, 0.15],
	"fishing_zip": ["saw", 520.0, 0.25, 0.005, 0.18],
	"fishing_note_1": ["triangle", 523.25, 0.18, 0.005, 0.1],
	"fishing_note_2": ["triangle", 659.25, 0.18, 0.005, 0.1],
	"fishing_note_3": ["triangle", 783.99, 0.5, 0.005, 0.35],
	"fishing_horn": ["saw", 147.0, 0.9, 0.06, 0.5],
}
const LOOP_SURF := "fishing_surf"
const LOOP_DRAG := "fishing_drag"
const FANFARE: Array = [[0.0, "fishing_note_1"], [0.16, "fishing_note_2"], [0.32, "fishing_note_3"]]
## Reel clicks: one per this many metres of line; never faster than CLICK_MIN_S apart.
const CLICK_PER_M := 0.08
const CLICK_MIN_S := 0.03
const GULL_EVERY_S := 2.4
const OTHER_LANE_DB := -10.0

## Every sound the last calls asked for, newest last (tests).
var played: Array[String] = []
var silent: bool = true
var surf: AudioStreamPlayer = null
var drag: AudioStreamPlayer = null
## The drag loop's state (tests read it headless too).
var drag_on: bool = false

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
		surf.play()


## Every sound name this game registers (credits: "synthesized").
static func sound_names() -> Array[String]:
	var out: Array[String] = []
	for k: String in SOUNDS:
		out.append(k)
	out.append(LOOP_SURF)
	out.append(LOOP_DRAG)
	return out


## The sounds of one cue; `local` is true for the local rider's lane (full volume).
func cue(c: Dictionary, local: bool) -> void:
	var db := 0.0 if local else OTHER_LANE_DB
	match str(c.get("k", "")):
		FishingCues.CUE_CAST:
			_play("fishing_plop", -8.0 + db)
		FishingCues.CUE_BITE:
			_play("fishing_bell", -4.0 + db)
		FishingCues.CUE_HOOKUP:
			_play("fishing_zip", -8.0 + db)
			_play("fishing_splash", -10.0 + db)
		FishingCues.CUE_MISS, FishingCues.CUE_THROWN:
			_play("fishing_splash", -8.0 + db)
		FishingCues.CUE_RUN:
			_play("fishing_zip", -6.0 + db, 1.3)
		FishingCues.CUE_JUMP:
			_play("fishing_splash", -5.0 + db)
		FishingCues.CUE_SNAP:
			_play("fishing_twang", -4.0 + db)
		FishingCues.CUE_LANDED:
			_play("fishing_splash", -10.0 + db)
			for note: Array in FANFARE:
				_queue.append([_clock + float(note[0]), str(note[1]), -6.0 + db])
		FishingCues.CUE_DOUBLE_HOOKUP:
			_play("fishing_bell", -6.0, 1.5)
		FishingCues.CUE_FRENZY:
			_play("fishing_gull", -8.0 + db)
		FishingCues.CUE_TRIP_OVER:
			_play("fishing_horn", -6.0)


## Loops and clicks for one frame: the local lane `l` (null without one) and its reel's line
## speed `line_mps` (positive retrieving, negative running out).
func update(dt: float, l: FishingLaneState, line_mps: float) -> void:
	_clock += dt
	_flush_queue()
	var running := l != null and l.state == FishingConst.ST_FIGHT and l.fish.run_active
	_set_drag(running)
	_click_wait -= dt
	_click_m += absf(line_mps) * dt
	if not running and _click_m >= CLICK_PER_M and _click_wait <= 0.0:
		_click_m = 0.0
		_click_wait = CLICK_MIN_S
		_play("fishing_click", -20.0)
	elif _click_m > CLICK_PER_M * 4.0:
		_click_m = CLICK_PER_M
	_gull_t -= dt
	if l != null and l.state == FishingConst.ST_PICK and _gull_t <= 0.0 and _has_bird_pile(l):
		_gull_t = GULL_EVERY_S
		_play("fishing_gull", -16.0, 0.9 + 0.2 * float(int(_clock * 7.0) % 3))


func _has_bird_pile(l: FishingLaneState) -> bool:
	for i in l.hint_count():
		if int(l.hints[3 * i]) == FishingConst.SPOT_BIRD_PILE:
			return true
	return false


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
