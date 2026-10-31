class_name WorkoutCrowd
extends Node2D
## The roadside crowd and the gantry of a scored sprint. Never in the first 300 s (BRIEF 4.6.8): a
## cheering crowd under a SPRINT gantry would ask for the effort the warm-up forbids. Nobody pops in
## on screen: a crowd starts past the screen's right edge and ends at where that edge was. People
## stand in clumps with open verge between them, not in a line: a clump overlaps itself, its members
## stand a few px apart in depth, and the ones further back are in shade, so the crowd has its own
## solid mass under the scene's light (this node's modulate). Their hands go up and down on the
## viewer's own cadence, half of each clump on the off beat.

const LEAD_S := 6.0
## One clump per bucket, wholly inside it, CLEAR_PX of open verge at least before the next bucket.
const CLUMP_PX := 140
const CLEAR_PX := 10
## People in a clump, by hash: some buckets are empty.
const CLUMP_SIZES: Array[int] = [0, 2, 3, 4, 4, 5, 5, 6, 7, 8]
## From one person to the next in a clump: closer than a sprite is wide.
const STEP_MIN_PX := 9
const STEP_SPREAD_PX := 5
## How far back a person stands (art px up the verge), and the shade at the furthest back.
const DEPTH_PX := 4
const BACK_SHADE := Color(0.72, 0.72, 0.78)
## The widest a sprite can be, for what the view can still see.
const SPRITE_PX := 26
## The gantry stands this far past the crowd's first spectator.
const GANTRY_PX := 120
## From the raised hand to the lowered one (props/crowd.png).
const HAND_DOWN_DY := 17
const CELL_COLUMNS := 8
## Salts the hash of a person from the hash of its clump.
const PERSON_SALT := 0x5bd1e995

var kit: WorkoutKit = null
var seed_value: int = 0
## [{w0, w1, open, i}] by start: the crowds on the road now.
var windows: Array[Dictionary] = []
var _road: PackedFloat64Array = PackedFloat64Array()
var _world_x: int = 0
var _canvas_w: float = 960.0
var _hands_up: bool = false
var _env_t: float = 0.0


func prepare(p_kit: WorkoutKit, p_seed: int) -> WorkoutCrowd:
	kit = p_kit
	seed_value = p_seed
	return self


## Does phase `i` get a crowd: a sprint with a scored effort, after the warm-up.
static func cheers_for(state: WorkoutState, i: int) -> bool:
	if not WorkoutSession.is_sprint(state.phase(i)):
		return false
	return state.phase_start_s(i) >= WorkoutHud.WARMUP_S


## The cheering phase at plan time `t` (from LEAD_S before it to its end), -1 if none.
static func cheering_phase(state: WorkoutState, t: float) -> int:
	for i: int in [state.phase_index, state.phase_index + 1]:
		var p := state.phase(i)
		if p == null or not cheers_for(state, i):
			continue
		var start := state.phase_start_s(i)
		if t >= start - LEAD_S and t < start + p.duration_s:
			return i
	return -1


## The spectators of the crowd [w0, w1) that the view [view_x0, view_x1) shows, in world px, clump by
## clump: [{x, kind, flag, depth, off_beat}]. Fixed by the seed and the world, so peers agree.
static func spectators(
	w0: float, w1: float, seed_val: int, view_x0: float, view_x1: float, kinds: int = CELL_COLUMNS
) -> Array:
	var out: Array = []
	var lo := floori(maxf(w0, view_x0) / float(CLUMP_PX))
	var hi := floori(minf(w1, view_x1) / float(CLUMP_PX))
	for k in range(lo, hi + 1):
		for p: Dictionary in clump(k, seed_val, kinds):
			var x := float(p["x"])
			if x >= w0 and x < w1 and x < view_x1 and x + float(SPRITE_PX) > view_x0:
				out.append(p)
	return out


## Bucket `k`'s people, left to right. Neighbours are never the same sprite.
static func clump(k: int, seed_val: int, kinds: int = CELL_COLUMNS) -> Array:
	var out: Array = []
	var h := WorkoutPropLayer.bucket_hash(k, seed_val)
	var count := CLUMP_SIZES[h % CLUMP_SIZES.size()]
	if count == 0:
		return out
	var steps: Array[int] = []
	var hashes: Array[int] = []
	var span := SPRITE_PX
	for i in count:
		var person := WorkoutPropLayer.bucket_hash(k * 8 + i, seed_val ^ PERSON_SALT)
		hashes.append(person)
		var step := STEP_MIN_PX + (person >> 3) % (STEP_SPREAD_PX + 1)
		steps.append(step)
		if i > 0:
			span += step
	var x := k * CLUMP_PX + (h >> 8) % (CLUMP_PX - span - CLEAR_PX + 1)
	var kind := (h >> 16) % kinds
	for i in count:
		if i > 0:
			x += steps[i]
			kind = (kind + 3) % kinds
		(
			out
			. append(
				{
					"x": float(x),
					"kind": kind,
					"flag": (hashes[i] >> 16) % 5 == 0,
					"depth": (hashes[i] >> 8) % (DEPTH_PX + 1),
					"off_beat": (hashes[i] >> 12) % 2 == 1,
				}
			)
		)
	return out


## One frame: opens and closes crowds from the plan time, and takes what the drawing needs.
func set_view(
	state: WorkoutState,
	world_x: float,
	canvas_w: float,
	road: PackedFloat64Array,
	hands_up: bool,
	env_t: float
) -> void:
	_world_x = roundi(world_x)
	_canvas_w = canvas_w
	_road = road
	_hands_up = hands_up
	_env_t = env_t
	var edge := world_x + canvas_w
	var i := cheering_phase(state, state.plan_t)
	for w in windows:
		if bool(w["open"]):
			w["w1"] = edge
			w["open"] = int(w["i"]) == i
	if i >= 0 and not _has_phase(i):
		windows.append({"w0": edge, "w1": edge, "open": true, "i": i})
	var kept: Array[Dictionary] = []
	for w in windows:
		if bool(w["open"]) or maxf(float(w["w1"]), _gantry_end(w)) > world_x:
			kept.append(w)
	windows = kept
	queue_redraw()


## Is any crowd on the road (tests and screenshots read it).
func active() -> bool:
	return not windows.is_empty()


func _has_phase(i: int) -> bool:
	for w in windows:
		if int(w["i"]) == i:
			return true
	return false


func _gantry_end(w: Dictionary) -> float:
	return float(w["w0"]) + float(GANTRY_PX) + float(kit.props["gantry"]["size"][0])


func _contact(screen_x: float) -> int:
	if _road.is_empty():
		return roundi(WorkoutRideView.ROAD_Y)
	var col := clampi(int(screen_x / float(WorkoutTrackLayer.COLUMN_W)), 0, _road.size() - 1)
	return roundi(_road[col])


func _draw() -> void:
	if kit == null:
		return
	for w in windows:
		_gantry(w)
		_spectators(w)


func _gantry(w: Dictionary) -> void:
	var p: Dictionary = kit.props["gantry"]
	var x := roundi(float(w["w0"])) + GANTRY_PX
	if float(x) > float(w["w1"]):
		return
	var size := WorkoutKit.vec(p["size"])
	var sx := x - _world_x
	if sx >= roundi(_canvas_w) or sx + size.x <= 0:
		return
	var foot := _contact(float(sx) + float(size.x) * 0.5) - int(p["foot_above_contact"])
	draw_texture(kit.texture(p["path"]), Vector2(sx, foot - size.y))


func _spectators(w: Dictionary) -> void:
	var p: Dictionary = kit.props["crowd"]
	var c := WorkoutKit.vec(p["cell"])
	var tex := kit.texture(p["path"])
	var foot_up := int(p["foot_above_contact"])
	var view_x0 := float(_world_x)
	var people := spectators(
		float(w["w0"]), float(w["w1"]), seed_value, view_x0, view_x0 + _canvas_w, int(p["count"])
	)
	# Furthest back first, so the nearer ones stand in front of them.
	for depth in range(DEPTH_PX, -1, -1):
		var shade := Color.WHITE.lerp(BACK_SHADE, float(depth) / float(DEPTH_PX))
		for s: Dictionary in people:
			if int(s["depth"]) != depth:
				continue
			var sx := roundi(float(s["x"])) - _world_x
			var y := _contact(float(sx) + float(c.x) * 0.5) - foot_up - c.y - depth
			var up := _hands_up != bool(s["off_beat"])
			var src := Rect2(Vector2i(int(s["kind"]) * c.x, (1 if up else 0) * c.y), c)
			draw_texture_rect_region(tex, Rect2(Vector2i(sx, y), c), src, shade)
			if bool(s["flag"]):
				_hand_flag(sx, y, int(s["kind"]), up, shade)


## A hand flag on the near hand, waving on the environment clock, never on anybody's cadence.
func _hand_flag(sx: int, y: int, kind: int, up: bool, shade: Color) -> void:
	var p: Dictionary = kit.props["flag"]
	var c := WorkoutKit.vec(p["cell"])
	var hand := WorkoutKit.vec(kit.props["crowd"]["hand_up"])
	var grip := WorkoutKit.vec(p["grip"])
	var at := Vector2i(sx, y) + hand - grip
	if not up:
		at.y += HAND_DOWN_DY
	var frame := floori(_env_t * 6.0 + float(kind)) % int(p["frames"])
	draw_texture_rect_region(
		kit.texture(p["path"]), Rect2(at, c), Rect2(Vector2i(frame * c.x, 0), c), shade
	)
