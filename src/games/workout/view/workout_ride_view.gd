class_name WorkoutRideView
extends Node2D
## Workout's ride view (BRIEF 3.7; the owner's pixel-art goal overrides its 640 x 360 and "no people",
## see docs/decisions/workout.md): real riders on a morning's road, 960 x 540 art px on a flexible
## canvas. Every world plane comes through the time-of-day LUT (workout_tod.gdshader); riders and
## props are true colour under a tint. In Rolling road the road follows the course profile.
##
## Three clocks, never mixed. On cadence, from game.cranks: legs, cranks, chain, breath, the crowd's
## hands. On speed, from shown_distance: wheels, road, verges' scroll, poles, pennant flutter, dust.
## On the environment clock (env_t, this view's frame time): wind pump, smoke, cattle, grass wind,
## clouds, hand flags.
##
## It reads WorkoutGame.state (the host's rules state or a client's snapshot state) and
## never changes it. refresh() rebuilds the drawing model; _process calls advance() every
## frame, which on a client first moves the client display (BRIEF 5.1) on by the frame's delta:
## the other riders are drawn between the two snapshots around render_t (WorkoutGame.history),
## the local rider from its own prediction blended softly toward the host's value. The host and
## SOLO draw the state as it is. It never reads a wall clock and never consumes ctx.rng.

const RIDER_X := 300.0
const ROAD_Y := 384.0
const ROAD_MIN_Y := 300.0
const ROAD_MAX_Y := 400.0
## Course and markers: metres per art pixel, vertical exaggeration (px per metre).
const MAP_M_PER_PX := 2.0
const ELEV_PX_PER_M := 1.0
## Parallax: art pixels per metre at factor 1 (gives a sense of speed).
const VISUAL_PX_PER_M := 14.0
## Interval strip: art pixels per plan second (960 px is about 21 minutes).
const STRIP_PX_PER_S := 0.75
const STRIP_BASE := 460.0
const STRIP_MAX_H := 40.0
## Strip heights (% FTP scale) of FREE phases, which have no target: a sprint stands tall, free
## riding (a FreeRide longer than a sprint, W4r2 R15) sits low and hatched.
const SPRINT_STRIP_PCT := 130.0
const FREE_STRIP_PCT := 55.0
## Pennants are drawn at this scale of WorkoutArt's base geometry.
const PENNANT_SCALE := 1.5
## Off-screen riders sit this far inside the left and right edges (a rider sprite is 88 wide).
const EDGE_MARGIN_LEFT := 44.0
const EDGE_MARGIN_RIGHT := 44.0
## Client display, other riders: render_t runs on the frame clock interp_delay() behind the
## newest snapshot's host time (a game has no NetSession handle, so the snapshot's tick is the
## host time) and never passes the newest snapshot (no extrapolation). The delay is the mean
## spacing of the snapshot history, at least INTERP_DELAY_S (NetSession's documented 100 ms
## interpolation at 10 Hz, host_time() - 0.1) and at most INTERP_DELAY_MAX_S. Under the 8-rider
## load snapshots arrive about once a second; a 0.1 s delay would hold the other riders at the
## newest snapshot for most of each second and then hurry them on.
const INTERP_DELAY_S := 0.1
## render_t further than this from where it belongs (the first snapshot, a rejoin, a stall)
## jumps there.
const CLOCK_RESYNC_S := 1.5
## The longest delay. It stays under CLOCK_RESYNC_S, so a render_t held at the newest snapshot
## is never resynced (sent back) when the delay grows.
const INTERP_DELAY_MAX_S := CLOCK_RESYNC_S - 0.1
## A render_t that fell behind (a late snapshot held it at the newest) catches up with this
## time constant.
const CLOCK_CATCHUP_TAU_S := 0.25
## Client display, local rider: drawn from its own prediction (moved by its predicted speed
## each frame) and blended toward the client state's value (the host's latest plus the
## prediction since) with this time constant. It never moves backwards; it jumps to the state
## only when they differ by more than LOCAL_SNAP_M (a rejoin, a long stall).
const LOCAL_BLEND_TAU_S := 0.3
const LOCAL_SNAP_M := 10.0
## The predicted speed stops moving the local rider once the state has not moved for this long
## (a pause: no prediction runs).
const LOCAL_STALE_S := 0.15
const SHADER_PATH := "res://src/games/workout/view/workout_tod.gdshader"
## Seconds the road takes to rise from flat into a course's profile, and to settle back after.
const ROAD_BLEND_S := 8.0
## A breath cloud's life, and how many one rider can have.
const BREATH_LIFE_S := 0.6
const BREATH_MAX := 8
## Dust: one puff per this many metres above this speed or in a sprint; a puff stays on its spot on
## the road and lasts DUST_PUFFS spacings.
const DUST_EVERY_M := 2.0
const DUST_MPS := 11.0
const DUST_PUFFS := 4
## Pennant flutter: cycles per metre (wind by speed, not cadence).
const FLUTTER_PER_M := 0.8
## Grey of a rider's sprite by state: a plain tint, the pose and the bubble do the telling.
const GREY_RESCUE := 0.35
const GREY_AFK := 0.6
const GREY_LINK := 1.0
## The bubble over a rider's head blinks at 2 Hz.
const BLINK_HZ := 2.0
## Riders' wheels never go under the foreground grass: it keeps this far below the lowest contact.
const FOREGROUND_CLEAR_PX := 3
const LANE_KEY_OFFSET := 100
const X_KEY_OFFSET := 5000

var game: WorkoutGame = null
var kit: WorkoutKit = null
## Every layer's parent, bottom-anchored on the canvas.
var stage: Node2D = null
var sky_fill: ColorRect = null
var sky: ParallaxStrip = null
var stars: ParallaxStrip = null
var sun: Sprite2D = null
var clouds: ParallaxStrip = null
var clouds_lo: ParallaxStrip = null
var far_hills: ParallaxStrip = null
var mid_hills: ParallaxStrip = null
var mid_props: WorkoutPropLayer = null
var near_trees: ParallaxStrip = null
var near_props: WorkoutPropLayer = null
var poles: ParallaxStrip = null
var road_layer: WorkoutRoadLayer = null
var crowd_layer: WorkoutCrowd = null
var riders: WorkoutRiderLayer = null
var verge_near: WorkoutRoadLayer = null
var bank: WorkoutBankLayer = null
var foreground: ParallaxStrip = null
var track: WorkoutTrackLayer = null
## The latest model (tests and screenshots read it).
var model: Dictionary = {}
## Client: the host time (s) the other riders are drawn at.
var render_t: float = 0.0
## Client: the distance (m) the local rider is drawn at.
var local_d: float = 0.0
## The canvas (art px) to draw on instead of the SubViewport's (tests, render_frames).
var canvas_override: Vector2 = Vector2.ZERO
## The environment clock: seconds of frame time, never cadence, never speed.
var env_t: float = 0.0
var _canvas: Vector2 = Vector2(WorkoutArt.W, WorkoutArt.H)
var _built: bool = false
var _clock_set: bool = false
var _local_set: bool = false
## Client: the local rider's state distance last frame, and for how long it has not moved.
var _local_seen: float = 0.0
var _local_still_s: float = 0.0
var _material: ShaderMaterial = null
var _row: int = -1
## Rotor turns and grass frames, both integrated on the wind's own rate.
var _rotor_revs: float = 0.0
var _grass_frames: float = 0.0
var _foreground_frame: int = -1
var _poses: Dictionary = {}
## peer -> whole half-counts of revolutions last seen; peer -> [{age}] breath clouds.
var _breath_seen: Dictionary = {}
var _breath: Dictionary = {}
var _spots_for_s: float = -1.0


func bind(p_game: WorkoutGame) -> void:
	game = p_game
	name = "WorkoutRideView"
	_build()


func _ready() -> void:
	_build()
	refresh()


func _process(delta: float) -> void:
	advance(delta)


## One frame of `delta` seconds: every rider's cranks turn on, the environment clock moves, on a
## client the render clock and the local rider's drawn distance move on, then refresh(). The host
## and SOLO only refresh.
func advance(delta: float) -> void:
	if game != null:
		game.tick_cranks(delta)
	_env_step(delta)
	if _is_client() and game.state != null:
		_advance_clock(delta)
		_advance_local(delta)
	_breath_step(delta)
	refresh()


func _is_client() -> bool:
	return game != null and game.ctx != null and game.ctx.role == Wl.CLIENT


## Client: how far render_t runs behind the newest snapshot (s): the snapshot history's mean
## spacing, clamped to INTERP_DELAY_S..INTERP_DELAY_MAX_S (INTERP_DELAY_S before two snapshots
## are in). 0.1 at 10 Hz, 1.0 for snapshots a second apart.
func interp_delay() -> float:
	var spacing := game.history.mean_spacing() if game != null and game.history != null else 0.0
	return clampf(spacing, INTERP_DELAY_S, INTERP_DELAY_MAX_S)


## render_t moves with the frame clock, catches up softly when it is behind the newest
## snapshot's time minus interp_delay(), and stops at the newest snapshot. A delay that grows
## leaves render_t ahead of its goal: it runs on and waits at the newest snapshot, never back.
func _advance_clock(delta: float) -> void:
	var history := game.history
	if history == null or history.is_empty():
		return
	var newest := history.newest_t()
	var goal := newest - interp_delay()
	if not _clock_set or absf(goal - render_t) > CLOCK_RESYNC_S:
		render_t = goal
		_clock_set = true
		return
	render_t += delta
	var behind := goal - render_t
	if behind > 0.0:
		render_t += behind * (1.0 - exp(-delta / CLOCK_CATCHUP_TAU_S))
	render_t = minf(render_t, newest)


## The local rider moves on by its predicted speed, then blends toward the state's distance;
## it never goes backwards and jumps only past LOCAL_SNAP_M.
func _advance_local(delta: float) -> void:
	var r := game.state.rider(game.ctx.local_peer)
	if r == null:
		return
	var target := r.distance_m()
	if target != _local_seen:
		_local_seen = target
		_local_still_s = 0.0
	else:
		_local_still_s += delta
	if not _local_set or absf(target - local_d) > LOCAL_SNAP_M:
		local_d = target
		_local_set = true
		return
	var v := maxf(r.speed_mps(), 0.0) if _local_still_s <= LOCAL_STALE_S else 0.0
	var moved := local_d + v * delta
	moved += (target - moved) * (1.0 - exp(-delta / LOCAL_BLEND_TAU_S))
	local_d = maxf(local_d, moved)


## The distance `peer` is drawn at: the state's on the host and in SOLO; on a client the local
## rider's blended prediction and every other rider between the snapshots around render_t
## (the state's until the first advance()).
func shown_distance(peer: int) -> float:
	var r := game.state.rider(peer)
	if r == null:
		return 0.0
	if not _is_client():
		return r.distance_m()
	if peer == game.ctx.local_peer:
		return local_d if _local_set else r.distance_m()
	if _clock_set and game.history != null:
		return game.history.distance_at(peer, render_t, r.distance_m())
	return r.distance_m()


## The canvas the view draws on (art px): the override, else the PixelViewport's SubViewport, else
## the base (headless tests).
func canvas_size() -> Vector2:
	if canvas_override != Vector2.ZERO:
		return canvas_override
	var vp := get_viewport() if is_inside_tree() else null
	if vp is SubViewport:
		return Vector2((vp as SubViewport).size)
	return Vector2(WorkoutArt.W, WorkoutArt.H)


# --- build ---------------------------------------------------------------------------


func _build() -> void:
	if _built:
		return
	_built = true
	kit = WorkoutKit.shared()
	var seed_value := game.ctx.seed if game != null and game.ctx != null else 0
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER_PATH) as Shader
	_material.set_shader_parameter("lut", kit.texture(kit.data["lut"]["path"]))
	stage = Node2D.new()
	stage.name = "Stage"
	add_child(stage)
	sky_fill = ColorRect.new()
	sky_fill.size = Vector2.ZERO
	sky_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky = _plane("sky")
	stars = _plane("stars")
	sun = Sprite2D.new()
	sun.texture = kit.texture(kit.data["sun"]["path"])
	clouds = _plane("clouds_hi")
	clouds_lo = _plane("clouds_lo")
	far_hills = _plane("far_hills")
	mid_hills = _plane("mid_hills")
	mid_props = WorkoutPropLayer.new().prepare(kit, mid_hills.factor, 260, _mid_table(), seed_value)
	near_trees = _plane("near_trees")
	near_props = WorkoutPropLayer.new().prepare(
		kit, near_trees.factor, 520, _near_table(), seed_value
	)
	near_props.chimneys = true
	poles = _plane("poles")
	road_layer = WorkoutRoadLayer.new().prepare(kit, false)
	road_layer.material = _material
	crowd_layer = WorkoutCrowd.new().prepare(kit, seed_value)
	riders = WorkoutRiderLayer.new().prepare(kit)
	verge_near = WorkoutRoadLayer.new().prepare(kit, true)
	verge_near.material = _material
	bank = WorkoutBankLayer.new()
	bank.seed_value = seed_value
	foreground = _plane("foreground")
	track = WorkoutTrackLayer.new()
	for layer: CanvasItem in _layers():
		stage.add_child(layer)
	_set_foreground_frame(0)


## Back to front.
func _layers() -> Array[CanvasItem]:
	return [
		sky_fill,
		sky,
		stars,
		sun,
		clouds,
		clouds_lo,
		far_hills,
		mid_hills,
		mid_props,
		near_trees,
		near_props,
		poles,
		road_layer,
		crowd_layer,
		riders,
		verge_near,
		bank,
		foreground,
		track,
	]


func _strips() -> Array[ParallaxStrip]:
	return [sky, stars, clouds, clouds_lo, far_hills, mid_hills, near_trees, poles, foreground]


static func _mid_table() -> Array[String]:
	return ["cattle", "cattle", "cattle", "", "", "", "", ""]


static func _near_table() -> Array[String]:
	return ["windpump", "", "", ""]


## A plane of the kit as a world2d ParallaxStrip under the LUT, scrolled only by the world x
## refresh() sets (deterministic, no drift of its own) and the wind's tick().
func _plane(plane_name: String) -> ParallaxStrip:
	var p := kit.plane(plane_name)
	var strip := ParallaxStrip.new()
	strip.name = plane_name
	if p.has("path"):
		strip.texture = kit.texture(p["path"])
	strip.factor = float(p.get("factor", 0.0))
	strip.drift_px_s = float(p.get("drift", 0.0))
	strip.position.y = float(p.get("y", 0.0))
	strip.cover_width = float(WorkoutArt.W)
	strip.auto_process = false
	strip.material = _material
	return strip


# --- clocks --------------------------------------------------------------------------


## The environment clock: the wind's gust drives the pump's rotor and the grass, never cadence or
## speed.
func _env_step(delta: float) -> void:
	env_t += delta
	var gust := 0.5 + 0.5 * sin(env_t / 11.0) * sin(env_t / 3.7)
	_rotor_revs += (0.8 + 1.6 * gust) * delta
	_grass_frames += (2.0 + 4.0 * gust) * delta
	clouds.tick(delta)
	clouds_lo.tick(delta)


## Breath: one cloud each second revolution, while the air is cold; a rider who stops pedalling
## stops breathing clouds.
func _breath_step(delta: float) -> void:
	if game == null or game.state == null:
		return
	var cold := bool(kit.tod_row(_tod_row())["breath"])
	for peer: int in game.state.order:
		var half := floori(game.cranks.revs(peer) / 2.0)
		var kept: Array = []
		for c: Dictionary in _breath.get(peer, []):
			c["age"] = float(c["age"]) + delta
			if float(c["age"]) < BREATH_LIFE_S:
				kept.append(c)
		if cold and _breath_seen.has(peer) and half != int(_breath_seen[peer]):
			kept.append({"age": 0.0})
			if kept.size() > BREATH_MAX:
				kept.pop_front()
		_breath_seen[peer] = half
		_breath[peer] = kept


func _tod_row() -> int:
	return WorkoutTod.row(WorkoutTod.progress(game.state))


# --- refresh -------------------------------------------------------------------------


## Recomputes the drawing model from the game's state.
func refresh() -> void:
	if game == null or game.state == null:
		return
	var state := game.state
	_layout()
	var cam := state.rider(game.view_peer())
	var cam_d := shown_distance(cam.peer_id) if cam != null else 0.0
	var world_x := cam_d * VISUAL_PX_PER_M
	for layer in _strips():
		if layer.world_x != world_x:
			layer.world_x = world_x
	var row := _tod_row()
	_apply_row(row)
	var road := _road(state, cam, cam_d)
	var runs := WorkoutRoadLayer.runs_of(road, WorkoutTrackLayer.COLUMN_W)
	var scroll := roundi(world_x)
	var markers := _markers(state, cam_d, road)
	model = {
		"road": road,
		"runs": runs,
		"blocks": _blocks(state),
		"now_x": RIDER_X,
		"markers": markers,
		"draw_order": draw_order_of(markers),
		"row": row,
		"puffs": _puffs(markers),
	}
	_set_foreground_y(markers)
	var grass := floori(_grass_frames)
	road_layer.set_view(runs, scroll, grass % 4)
	verge_near.set_view(runs, scroll, grass % 4)
	_set_foreground_frame(floori(_grass_frames / 2.0) % 2)
	bank.set_view(runs, scroll, kit.tod_color(row, "bank"), kit.tod_color(row, "bank_hi"))
	if state.total_s() != _spots_for_s:
		_spots_for_s = state.total_s()
		var seed_value := game.ctx.seed if game.ctx != null else 0
		mid_props.set_spots(WorkoutSpots.build(seed_value, _spots_for_s))
	var rotor := floori(fposmod(_rotor_revs, 1.0) * float(kit.props["windpump"]["rotor"][4]))
	mid_props.set_view(world_x, _canvas.x, env_t, rotor, row, state.plan_t)
	near_props.set_view(world_x, _canvas.x, env_t, rotor, row, state.plan_t)
	crowd_layer.set_view(state, world_x, _canvas.x, road, hands_up(cam), env_t)
	riders.set_model(model)
	track.set_model(model)


## The crowd claps on the viewer's own cadence, and stops if the viewer stops.
func hands_up(cam: WorkoutRiderState) -> bool:
	return cam != null and floori(game.cranks.revs(cam.peer_id) * 2.0) % 2 == 1


## The canvas can change at runtime (PixelViewport.art_size_changed): the stage stays anchored to
## its bottom, because the HUD and the strip anchor to the bottom, and strips cover its width.
func _layout() -> void:
	var c := canvas_size()
	if c == _canvas:
		return
	_canvas = c
	stage.position.y = roundf(c.y - float(WorkoutArt.H))
	for layer in _strips():
		layer.cover_width = c.x
	# Above the sky tile's top: one flat colour, the row's sky_top.
	var above := maxf(stage.position.y + float(kit.plane("sky")["y"]), 0.0)
	sky_fill.position = Vector2(0.0, -stage.position.y)
	sky_fill.size = Vector2(c.x, above)


func _apply_row(row: int) -> void:
	if row == _row:
		return
	_row = row
	_material.set_shader_parameter("row", row)
	sky_fill.color = kit.tod_color(row, "sky_top")
	var tint := kit.tod_color(row, "rider_tint")
	for layer: CanvasItem in [riders, crowd_layer, mid_props, near_props]:
		layer.modulate = tint
	sun.position = Vector2(WorkoutKit.vec(kit.tod_row(row)["sun"]))


## The grass plane's two wind frames.
func _set_foreground_frame(frame: int) -> void:
	if frame == _foreground_frame:
		return
	_foreground_frame = frame
	var paths: Array = kit.plane("foreground")["paths"]
	foreground.texture = kit.texture(paths[frame % paths.size()])


## The foreground paints over the riders' layer, so it stays clear of the lowest wheel on screen:
## on a climb a trailing rider's contact sits below the plane's own y.
func _set_foreground_y(markers: Array) -> void:
	var y := int(kit.plane("foreground")["y"])
	for m: Dictionary in markers:
		if int(m["edge"]) == 0:
			y = maxi(y, maxi(int(m["rear_y"]), int(m["front_y"])) + FOREGROUND_CLEAR_PX)
	foreground.position.y = float(y)


# --- road ----------------------------------------------------------------------------


## How far the road has risen from flat into the course's profile, by plan time alone, so a phase
## start does not snap: it grows through a course phase's first ROAD_BLEND_S and falls through those
## of the phase right after.
static func road_blend(state: WorkoutState, index: int) -> float:
	if state.course == null or state.phase(index) == null:
		return 0.0
	var since := state.plan_t - state.phase_start_s(index)
	if state.is_course_phase(index):
		return clampf(since / ROAD_BLEND_S, 0.0, 1.0)
	if index > 0 and state.is_course_phase(index - 1):
		return 1.0 - clampf(since / ROAD_BLEND_S, 0.0, 1.0)
	return 0.0


## Road y per column; it follows the course elevation around the local rider in a course
## phase, and is flat otherwise. `cam_d` is the local rider's drawn distance: its course
## distance moves by the same offset from the state.
func _road(state: WorkoutState, cam: WorkoutRiderState, cam_d: float) -> PackedFloat64Array:
	var cols := int(ceil(_canvas.x / float(WorkoutTrackLayer.COLUMN_W)))
	var road := PackedFloat64Array()
	road.resize(cols)
	var index := cam.phase_index if cam != null and cam.phase_index >= 0 else state.phase_index
	var blend := road_blend(state, index)
	var cam_cd := maxf(cam.course_d + (cam_d - cam.distance_m()), 0.0) if cam != null else 0.0
	var e0 := state.course.elevation_at(cam_cd) if blend > 0.0 else 0.0
	for i in cols:
		var y := ROAD_Y
		if blend > 0.0:
			var x := float(i * WorkoutTrackLayer.COLUMN_W)
			var d := maxf(cam_cd + (x - RIDER_X) * MAP_M_PER_PX, 0.0)
			y = clampf(
				ROAD_Y - (state.course.elevation_at(d) - e0) * ELEV_PX_PER_M * blend,
				ROAD_MIN_Y,
				ROAD_MAX_Y
			)
		road[i] = y
	return road


# --- interval strip ------------------------------------------------------------------


## Interval blocks: one per phase, x by plan time around "now", height by % FTP.
func _blocks(state: WorkoutState) -> Array:
	var out: Array = []
	var t := 0.0
	for p in state.phases:
		var x0 := RIDER_X + (t - state.plan_t) * STRIP_PX_PER_S
		var x1 := RIDER_X + (t + p.duration_s - state.plan_t) * STRIP_PX_PER_S
		t += p.duration_s
		if x1 < 0.0 or x0 > _canvas.x or x1 - x0 < 1.0:
			continue
		var h0 := 0.0
		var h1 := 0.0
		var hatched := false
		if p.mode == Wl.ERG:
			h0 = _strip_h(p.target_pct)
			h1 = _strip_h(p.ramp_to_pct if p.has_ramp() else p.target_pct)
		elif p.kind == Wl.FREE and WorkoutSession.is_sprint(p):
			h0 = _strip_h(SPRINT_STRIP_PCT)
			h1 = h0
		elif p.kind == Wl.FREE:  # free riding (an imported FreeRide): no target, low and hatched
			h0 = _strip_h(FREE_STRIP_PCT)
			h1 = h0
			hatched = true
		else:
			h0 = _strip_h(float(state.band_pct[1]))
			h1 = h0
			hatched = true
		var a := x0 + 1.0
		(
			out
			. append(
				{
					"points":
					PackedVector2Array(
						[
							Vector2(a, STRIP_BASE - h0),
							Vector2(x1, STRIP_BASE - h1),
							Vector2(x1, STRIP_BASE),
							Vector2(a, STRIP_BASE)
						]
					),
					"color": WorkoutArt.phase_color(p),
					"hatched": hatched,
				}
			)
		)
	return out


static func _strip_h(pct: float) -> float:
	return clampf(pct / 150.0 * STRIP_MAX_H, 3.0, STRIP_MAX_H)


# --- riders --------------------------------------------------------------------------


## One marker per rider at its drawn distance from the local rider's (`cam_d`); the local rider
## is last in the list. `x` and `edge` are the map position, off-screen riders sit at the edge with
## an arrow; `draw_x` adds the group's formation (view only) and each rider's slow wander.
func _markers(state: WorkoutState, cam_d: float, road: PackedFloat64Array) -> Array:
	var out: Array = []
	var local_peer := game.view_peer()
	var peers: Array[int] = []
	for peer: int in state.order:
		if peer != local_peer:
			peers.append(peer)
	if state.riders.has(local_peer):
		peers.append(local_peer)
	for peer in peers:
		var r := state.rider(peer)
		var slot := game.ctx.player(peer) if game.ctx != null else null
		var look := Wl.slot_look(r.slot_index)
		if slot != null:
			look = {
				"color": slot.color,
				"shape": slot.shape,
				"pattern": slot.pattern,
				"hollow": slot.hollow
			}
		var shown := shown_distance(peer)
		var x := RIDER_X + (shown - cam_d) / MAP_M_PER_PX
		var edge := 0
		if x < EDGE_MARGIN_LEFT:
			x = EDGE_MARGIN_LEFT
			edge = -1
		elif x > _canvas.x - EDGE_MARGIN_RIGHT:
			x = _canvas.x - EDGE_MARGIN_RIGHT
			edge = 1
		var opts := {
			"bot": r.is_bot,
			"local": peer == local_peer,
			"in_band": r.in_band,
			"rescue": r.rescue,
			"afk": r.afk or not r.connected,
			"style": game.view_pennant() if peer == local_peer else "",
		}
		var m := {
			"peer": peer,
			"x": x,
			"y": road[_col(x, road)],
			"edge": edge,
			"shapes": _scaled(WorkoutArt.pennant_shapes(look, r.slot_index, opts), PENNANT_SCALE),
		}
		_place(m, state, r, shown, road)
		out.append(m)
	return out


func _col(x: float, road: PackedFloat64Array) -> int:
	return clampi(int(x / float(WorkoutTrackLayer.COLUMN_W)), 0, road.size() - 1)


## What the rider layer needs on top of the map position.
func _place(
	m: Dictionary, state: WorkoutState, r: WorkoutRiderState, shown: float, road: PackedFloat64Array
) -> void:
	var ordinal := state.order.find(r.peer_id)
	var is_local := r.peer_id == game.view_peer()
	var lane := WorkoutRig.lane_dy(ordinal)
	var px := roundi(_draw_x(m, ordinal, maxi(state.order.find(game.view_peer()), 0), is_local))
	var rear_y := roundi(road[_col(float(px - 20), road)]) + lane
	var front_y := roundi(road[_col(float(px + 20), road)]) + lane
	var pose := WorkoutRig.pose_of(
		int(_poses.get(r.peer_id, WorkoutRig.POSE_SEAT)), _facts(state, r)
	)
	_poses[r.peer_id] = pose
	m["draw_x"] = px
	m["rear_y"] = rear_y
	m["front_y"] = front_y
	m["pitch"] = clampi(front_y - rear_y, -6, 6)
	m["pose"] = pose
	m["crank_frame"] = WorkoutRig.crank_frame(game.cranks.revs(r.peer_id))
	m["wheel_frame"] = WorkoutRig.wheel_frame(shown)
	m["slot"] = r.slot_index
	m["lane"] = lane
	m["grey"] = grey_of(r)
	m["bubble"] = bubble_of(r)
	m["blink"] = floori(env_t * BLINK_HZ * 2.0) % 2
	m["flutter"] = floori(shown * FLUTTER_PER_M * 2.0) % 2
	m["dust"] = _dust(m, r, state, shown)


## Where a rider is drawn: its map position, plus its place in the group and its slow wander.
func _draw_x(m: Dictionary, ordinal: int, local_ord: int, is_local: bool) -> float:
	var x := float(m["x"])
	if int(m["edge"]) != 0:
		return x
	var wander := 0.0 if is_local else roundf(3.0 * sin(env_t / 7.0 + float(ordinal) * 1.7))
	return clampf(
		x + float(WorkoutRig.formation_dx(ordinal, local_ord)) + wander,
		EDGE_MARGIN_LEFT,
		_canvas.x - EDGE_MARGIN_RIGHT
	)


## How far a rider's sprite is dimmed and cooled.
static func grey_of(r: WorkoutRiderState) -> float:
	if not r.connected:
		return GREY_LINK
	if r.afk:
		return GREY_AFK
	return GREY_RESCUE if r.rescue else 0.0


## The fx bubble over a rider's head ("" for none).
static func bubble_of(r: WorkoutRiderState) -> String:
	if not r.connected:
		return "link"
	if r.afk:
		return "afk"
	return "rescue" if r.rescue else ""


## What the pose rules read, all from the rider's state.
func _facts(state: WorkoutState, r: WorkoutRiderState) -> Dictionary:
	var course := state.is_course_phase(r.phase_index) and state.course != null
	return {
		"rescue": r.rescue,
		"afk": r.afk,
		"disconnected": not r.connected,
		"v_mps": r.speed_mps(),
		"cadence_rpm": r.cadence_rpm,
		"power_w": r.power_w,
		"ftp": r.ftp,
		"sprint_phase": WorkoutSession.is_sprint(state.phase(r.phase_index)),
		"grade_pct": state.course.grade_at(r.course_d) if course else 0.0,
	}


## The dust behind a fast rider, stateless on distance: each puff stays where it was raised and
## ages by the metres since.
func _dust(m: Dictionary, r: WorkoutRiderState, state: WorkoutState, shown: float) -> Array:
	var out: Array = []
	var v := r.speed_mps()
	var fast := v > DUST_MPS or WorkoutSession.is_sprint(state.phase(r.phase_index))
	if not fast or v < WorkoutRig.STOPPED_MPS or int(m["edge"]) != 0:
		return out
	var hub := int(kit.rider["rear_hub"][0]) - int(kit.rider["origin"][0])
	var newest := floori(shown / DUST_EVERY_M)
	var box: Array = kit.data["fx"]["dust"]
	for i in DUST_PUFFS:
		var age_m := shown - float(newest - i) * DUST_EVERY_M
		var behind := roundi(age_m * VISUAL_PX_PER_M)
		var at := Vector2i(
			int(m["draw_x"]) + hub - int(box[2]) - behind, int(m["rear_y"]) - int(box[3])
		)
		out.append({"fx": "dust", "frame": i, "at": at})
	return out


## Every rider's breath clouds where they are now: from the mouth, trailing back as they age.
func _puffs(markers: Array) -> Array:
	var out: Array = []
	var origin := WorkoutKit.vec(kit.rider["origin"])
	var frames := int(kit.data["fx"]["breath"][4])
	for m: Dictionary in markers:
		if int(m["edge"]) != 0:
			continue
		var pose_name: String = WorkoutRig.POSE_NAMES[int(m["pose"])]
		var mouth := WorkoutKit.vec(kit.rider["mouth_by_pose"][pose_name])
		for c: Dictionary in _breath.get(int(m["peer"]), []):
			var age := float(c["age"])
			var at := Vector2i(
				int(m["draw_x"]) - origin.x + mouth.x - roundi(age * 14.0),
				int(m["rear_y"]) - origin.y + mouth.y - roundi(age * 6.0)
			)
			var frame := mini(floori(age / BREATH_LIFE_S * float(frames)), frames - 1)
			out.append({"fx": "breath", "frame": frame, "at": at})
	return out


## Paint order, separate from the model's order: marker indices by lane, far first, then x, the
## local rider (last in the list) last within its lane.
static func draw_order_of(markers: Array) -> Array:
	var keys: Array[int] = []
	for i in markers.size():
		var m: Dictionary = markers[i]
		var local := 1 if i == markers.size() - 1 else 0
		var lane := int(m["lane"]) + LANE_KEY_OFFSET
		var x := int(m["draw_x"]) + X_KEY_OFFSET
		keys.append((lane * 2 + local) * 1000000 + x * 100 + i)
	keys.sort()
	var out: Array = []
	for k in keys:
		out.append(k % 100)
	return out


static func _scaled(shapes: Array[Dictionary], k: float) -> Array[Dictionary]:
	for s in shapes:
		var pts := PackedVector2Array()
		for p in s["points"] as PackedVector2Array:
			pts.append(p * k)
		s["points"] = pts
	return shapes


## The marker for `peer` in the latest model ({} if none).
func marker(peer: int) -> Dictionary:
	for m: Dictionary in model.get("markers", []):
		if int(m["peer"]) == peer:
			return m
	return {}
