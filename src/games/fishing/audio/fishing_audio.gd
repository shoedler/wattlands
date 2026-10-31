class_name FishingAudio
extends Node
## Turbo Reel's sound: an adapter over the platform's GameAudioKit. It maps the boats and the rider
## state to the parameters of assets/fishing/audio/audio.json and cues to the bank's cue names, and
## nothing else: every recipe, level and stroke fraction is in that file (docs/AUDIO_PIPELINE.md).
## Each boat is one `drivetrain` machine, driven with the very number its crank is drawn from
## (FishingBoatView.crank_clock), so a stroke and the crank on screen cannot drift apart. The local
## boat leads; others are quieter and fall away with distance. Headless runs and --sim-speed play
## nothing and still record `played` (tests read it). The metronome is the platform's (GAME_SDK 18).

const BANK_PATH := "res://assets/fishing/audio/audio.json"
## The bank's mix.other_db: another rider's boat and cues against your own.
const OTHER_DB := -10.0
## Module events with no sound of their own: none. A replacement fish hooks itself with the hookup
## cue (FishingCues), and the gaff sprint's start has its own landing cue.
const SILENT_EVENTS: Array[String] = []
## Gulls gather while the local boat is within this far of the dock (m).
const GULL_RANGE_M := 250.0
## Another boat at full `near` up to EAR_FULL_M from you, out of earshot from EAR_ZERO_M (m).
const EAR_FULL_M := 150.0
const EAR_ZERO_M := 700.0
## The line speed arrives in steps on a client (10 Hz snapshots): smoothed, or the ratchet stutters.
const REEL_TAU_S := 0.15
## A hull slap when the hull falls this fast (m/s), the rate smoothed over HEAVE_TAU_S (a client's
## heave comes in 1 cm steps, and one step must not read as a fall); only under way.
const SLAP_RATE_MPS := 0.05
const HEAVE_TAU_S := 0.25
const SLAP_MIN_MPS := 1.5
## The long swell a boat runs over, in metres of ocean: two sines, so it does not repeat for 7810 m.
const SWELL_A_M := 110.0
const SWELL_B_M := 71.0
const SWELL_A := 0.6
const SWELL_B := 0.4
## A slap on the swell: armed on a crest above this, fired going down into the trough under the next.
const SLAP_SWELL_ARM := 0.1
const SLAP_SWELL_FIRE := -0.2
## The sea deepens from the shallows (0) to open water (1) over this stretch of the course (m).
const OFFSHORE_FROM_M := 600.0
const OFFSHORE_FULL_M := 12000.0
## What the bank's routine cues lose (dB) from another boat at the edge of earshot: the fall of its
## machine (`near` in the bank). A bite is routine too: it should mean you. The news of a catch and
## a double hookup carry no `db_var`, so stay level.
const FAR_DB := -26.0
## The clutch: the prop is off once the clutch is halfway to the winch.
const CLUTCH_K := 2.0
const LOAD_MAX := 1.5

## Set by the view before add_child: SeededRng.derive(ctx.seed, "fishing:audio").
var rng_seed: int = 0
var kit: GameAudioKit = GameAudioKit.new()
## Every sound started, newest last (the kit's record: base sound ids).
var played: Array[String]:
	get:
		return kit.played

var _reel: Dictionary = {}
var _heave_seen: bool = false
var _heave_was: float = 0.0
var _heave_rate: float = 0.0
var _slap_armed: bool = true
var _swell_armed: bool = false
var _lift: LiftOffDetector = LiftOffDetector.new()
var _lift_armed: bool = true
var _lift_low: float = 0.0
var _clutch_in: bool = false
var _paused: bool = false
var _state: FishingState = null
var _local_slot: int = -1


func _init() -> void:
	name = "FishingAudio"
	add_child(kit)


func _ready() -> void:
	kit.setup(BANK_PATH, rng_seed)
	kit.set_bed("open_sea")
	var bus := get_tree().root.get_node_or_null("EventBus")
	if bus != null:
		bus.connect("paused_changed", _on_paused_changed)


## The sounds of one cue; `local` is true for the local rider. A cue with no rider (l < 0, the
## horns) is everyone's. Another rider's routine cue falls away with distance as its boat does.
func cue(c: Dictionary, local: bool) -> void:
	var slot := int(c.get("l", -1))
	var vars := {"far_db": 0.0 if local else _far_db(slot)}
	kit.cue(cue_name(c), vars, local or slot < 0)


## The bank's cue for FishingCues cue `c`: one splash per leap the fish makes, more for a trophy.
static func cue_name(c: Dictionary) -> String:
	var k := str(c.get("k", ""))
	if k == FishingCues.CUE_JUMP and int(c.get("leaps", 2)) != 2:
		return "%s_%d" % [k, int(c.get("leaps", 2))]
	if k == FishingCues.CUE_LANDED and int(c.get("grade", 0)) == FishingConst.GRADE_TROPHY:
		return k + "_trophy"
	return k


## One frame: every boat in earshot (`boats`: slot -> FishingBoatView, placed and advanced this
## frame), the loops of the local rider, the bed, then the kit's commit.
func update(dt: float, boats: Dictionary, state: FishingState, local_slot: int) -> void:
	_state = state
	_local_slot = local_slot
	var me := state.rider(local_slot)
	for r in state.riders:
		var b: FishingBoatView = boats.get(r.slot)
		if b == null:
			continue
		var near := ear_of(r.x_m, me)
		if near <= 0.0:
			continue
		kit.drive(
			"boat%d" % r.slot,
			"drivetrain",
			b.crank_clock.revs,
			b.cadence,
			_params(r, b, near, dt),
			r.slot == local_slot
		)
	var speed := absf(me.v_mps) if me != null else 0.0
	if me != null and boats.has(local_slot):
		_local_loops(me, boats[local_slot], speed, dt)
		_clutch(boats[local_slot])
	var hull_speed := 0.0 if _paused else speed
	var x_m := me.x_m if me != null else 0.0
	kit.bed_params({"near_dock": near_dock(x_m), "offshore": offshore(x_m), "speed": hull_speed})
	kit.commit(dt)


## 1 over the harbour .. 0 from GULL_RANGE_M out.
static func near_dock(x_m: float) -> float:
	return clampf(1.0 - x_m / GULL_RANGE_M, 0.0, 1.0)


## 0 in the shallows .. 1 on open water: the sea's weight moves down as the bottom falls away.
static func offshore(x_m: float) -> float:
	return clampf((x_m - OFFSHORE_FROM_M) / (OFFSHORE_FULL_M - OFFSHORE_FROM_M), 0.0, 1.0)


## The swell under a boat at `x_m`, -1 .. 1. A place on the ocean, so a host and a client agree and a
## boat at speed rides it at a few seconds a wave; the engine labours up and runs free down it.
static func swell(x_m: float) -> float:
	return SWELL_A * sin(TAU * x_m / SWELL_A_M) + SWELL_B * sin(TAU * x_m / SWELL_B_M)


## How well the local rider `me` hears a boat at `x_m`: 1 .. 0 (out of earshot). 1 with no rider.
static func ear_of(x_m: float, me: FishingRiderState) -> float:
	if me == null:
		return 1.0
	return 1.0 - clampf((absf(x_m - me.x_m) - EAR_FULL_M) / (EAR_ZERO_M - EAR_FULL_M), 0.0, 1.0)


## The rider's fish is running: the drag screams and the ratchet is silent.
static func is_running(r: FishingRiderState) -> bool:
	return r.action == FishingConst.A_FIGHT and r.fish.run_active


func _far_db(slot: int) -> float:
	if _state == null or _state.rider(slot) == null:
		return 0.0
	return FAR_DB * (1.0 - ear_of(_state.rider(slot).x_m, _state.rider(_local_slot)))


## Paused, the boat stands: the bed reads no speed, and nothing the frozen hull does is a new edge.
func _on_paused_changed(paused: bool, _reason: String) -> void:
	_paused = paused
	_heave_seen = false
	_lift = LiftOffDetector.new()


func _params(r: FishingRiderState, b: FishingBoatView, near: float, dt: float) -> Dictionary:
	var k := 1.0 - exp(-dt / REEL_TAU_S) if dt > 0.0 else 0.0
	var winch := lerpf(float(_reel.get(r.slot, 0.0)), maxf(b.winch_mps, 0.0), k)
	_reel[r.slot] = winch
	var reeling := b.fishing >= 0.5 and not is_running(r)
	return {
		"prop": b.prop_drive * clampf(1.0 - CLUTCH_K * b.fishing, 0.0, 1.0),
		"load": _load_of(r),
		"winch": winch,
		"reel": winch if reeling else 0.0,
		"fishing": b.fishing,
		"tension": b.tension,
		"near": near,
		"swell": swell(r.x_m),
	}


func _load_of(r: FishingRiderState) -> float:
	return clampf(r.p_eff_w / FishingConst.P_EFF_REF_W, 0.0, LOAD_MAX)


func _local_loops(me: FishingRiderState, b: FishingBoatView, speed: float, dt: float) -> void:
	if is_running(me):
		kit.set_loop("drag_scream", {"tension": b.tension})
	if me.plane > 0.0:
		kit.set_loop("plane_wash", {"plane": me.plane, "speed": speed, "swell": swell(me.x_m)})
	if dt <= 0.0 or _paused:
		return
	_hull_slap(me, speed, dt)
	_swell_slap(me, speed)
	_lift_off(_load_of(me), b, dt)


## One burble per lift, only with the crank turning and the clutch on the prop. Power can fall after
## the crank has stopped (on a client it comes in the 10 Hz snapshot, cadence is live): that is no
## lift-off. Any further drop waits until the load has risen by a drop's worth again.
func _lift_off(load_now: float, b: FishingBoatView, dt: float) -> void:
	if _lift.update(load_now, dt) >= 1.0:
		if _lift_armed and b.cadence > CrankClock.STOP_RPM and b.fishing < 0.5:
			kit.cue("lift_off")
		_lift_armed = false
		_lift_low = load_now
	_lift_low = minf(_lift_low, load_now)
	if load_now >= _lift_low + LiftOffDetector.DROP:
		_lift_armed = true


## The lever flips back to the prop after a landing, a snap or a thrown hook. The cast's clunk is
## the same lever going the other way.
func _clutch(b: FishingBoatView) -> void:
	var fishing := b.fishing_target >= 0.5
	if _clutch_in and not fishing:
		kit.cue("clutch")
	_clutch_in = fishing


## The bow dropping off a swell: the slap heard on a long crossing, where the heave lies flat. One
## per wave, so it comes faster the faster the boat goes.
func _swell_slap(me: FishingRiderState, speed: float) -> void:
	var s := swell(me.x_m)
	if s > SLAP_SWELL_ARM:
		_swell_armed = true
	elif s < SLAP_SWELL_FIRE and _swell_armed and speed >= SLAP_MIN_MPS:
		_swell_armed = false
		kit.cue("hull_slap")


## The hull falling back onto the water: an edge on the heave's smoothed fall, the same on a host
## and a client (a client has no heave_rate, only the snapshot's heave).
func _hull_slap(me: FishingRiderState, speed: float, dt: float) -> void:
	if not _heave_seen:
		_heave_seen = true
		_heave_was = me.heave_m
	var rate := (me.heave_m - _heave_was) / dt
	_heave_was = me.heave_m
	_heave_rate = lerpf(_heave_rate, rate, 1.0 - exp(-dt / HEAVE_TAU_S))
	if _heave_rate > -SLAP_RATE_MPS * 0.5:
		_slap_armed = true
	elif _heave_rate < -SLAP_RATE_MPS and _slap_armed and speed >= SLAP_MIN_MPS:
		_slap_armed = false
		kit.cue("hull_slap")
