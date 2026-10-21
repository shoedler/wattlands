class_name WorkoutRideView
extends Node2D
## Workout's ride view (BRIEF 3.7): a 640 x 360 side-scrolling landscape. Sky, clouds and
## three parallax strips (world2d ParallaxStrip, BRIEF 3.9) scroll with the local rider's
## distance; one pennant per rider
## (slot color + shape + pattern, BRIEF 3.9) sits on the road at its distance from the local
## rider; in Rolling road the road follows the course profile; the interval blocks are drawn
## on the ground with a "now" mark under the local rider. No people are drawn.
##
## It reads WorkoutGame.state (the host's rules state or a client's snapshot state) and
## never changes it. refresh() rebuilds the drawing model; _process calls advance() every
## frame, which on a client first moves the client display (BRIEF 5.1) on by the frame's delta:
## the other riders are drawn between the two snapshots around render_t (WorkoutGame.history),
## the local rider from its own prediction blended softly toward the host's value. The host and
## SOLO draw the state as it is.

const RIDER_X := 200.0
const ROAD_Y := 236.0
const ROAD_MIN_Y := 186.0
const ROAD_MAX_Y := 256.0
## Course and markers: metres per art pixel, vertical exaggeration (px per metre).
const MAP_M_PER_PX := 2.0
const ELEV_PX_PER_M := 2.5
## Parallax: art pixels per metre at factor 1 (gives a sense of speed).
const VISUAL_PX_PER_M := 3.0
## Interval strip: art pixels per plan second (640 px is about 21 minutes).
const STRIP_PX_PER_S := 0.5
const STRIP_BASE := 298.0
const STRIP_MAX_H := 32.0
## Strip heights (% FTP scale) of FREE phases, which have no target: a sprint stands tall, free
## riding (a FreeRide longer than a sprint, W4r2 R15) sits low and hatched.
const SPRINT_STRIP_PCT := 130.0
const FREE_STRIP_PCT := 55.0
## Pennants are drawn at this scale of WorkoutArt's base geometry.
const PENNANT_SCALE := 1.5
## Off-screen riders sit this far inside the left and right edges (the flag points right).
const EDGE_MARGIN_LEFT := 10.0
const EDGE_MARGIN_RIGHT := 30.0
## Client display, other riders: render_t runs on the frame clock INTERP_DELAY_S behind the
## newest snapshot's host time (NetSession's documented 100 ms interpolation, host_time() - 0.1;
## a game has no NetSession handle, so the snapshot's tick is the host time) and never passes
## the newest snapshot (no extrapolation).
const INTERP_DELAY_S := 0.1
## render_t further than this from where it belongs (the first snapshot, a rejoin, a stall)
## jumps there.
const CLOCK_RESYNC_S := 1.5
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

var game: WorkoutGame = null
var sky: ParallaxStrip = null
var clouds: ParallaxStrip = null
var far_hills: ParallaxStrip = null
var mid_hills: ParallaxStrip = null
var near_trees: ParallaxStrip = null
var track: WorkoutTrackLayer = null
## The latest model (tests and screenshots read it).
var model: Dictionary = {}
## Client: the host time (s) the other riders are drawn at.
var render_t: float = 0.0
## Client: the distance (m) the local rider is drawn at.
var local_d: float = 0.0
var _built: bool = false
var _clock_set: bool = false
var _local_set: bool = false
## Client: the local rider's state distance last frame, and for how long it has not moved.
var _local_seen: float = 0.0
var _local_still_s: float = 0.0


func bind(p_game: WorkoutGame) -> void:
	game = p_game
	name = "WorkoutRideView"
	_build()


func _ready() -> void:
	_build()
	refresh()


func _process(delta: float) -> void:
	advance(delta)


## One frame of `delta` seconds: on a client the render clock and the local rider's drawn
## distance move on, then refresh(). The host and SOLO only refresh.
func advance(delta: float) -> void:
	if _is_client() and game.state != null:
		_advance_clock(delta)
		_advance_local(delta)
	refresh()


func _is_client() -> bool:
	return game != null and game.ctx != null and game.ctx.role == Wl.CLIENT


## render_t moves with the frame clock, catches up softly when it is behind the newest
## snapshot's time minus INTERP_DELAY_S, and stops at the newest snapshot.
func _advance_clock(delta: float) -> void:
	var history := game.history
	if history == null or history.is_empty():
		return
	var newest := history.newest_t()
	var goal := newest - INTERP_DELAY_S
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


func _build() -> void:
	if _built:
		return
	_built = true
	sky = _strip(WorkoutArt.sky_image(), 0.0, 0.0)
	clouds = _strip(WorkoutArt.clouds_image(), 0.02, 30.0)
	far_hills = _strip(WorkoutArt.far_hills_image(), 0.06, 230.0 - WorkoutArt.FAR_SIZE.y)
	mid_hills = _strip(WorkoutArt.mid_hills_image(), 0.18, 238.0 - WorkoutArt.MID_SIZE.y)
	near_trees = _strip(WorkoutArt.trees_image(), 0.5, 244.0 - WorkoutArt.NEAR_SIZE.y)
	track = WorkoutTrackLayer.new()
	for layer: Node2D in [sky, clouds, far_hills, mid_hills, near_trees, track]:
		add_child(layer)


## A world2d ParallaxStrip of a seamless procedural image, its top edge at `top_y`, covering
## the 640 px view and scrolled only by the world x refresh() sets (deterministic, no drift).
static func _strip(image: Image, factor: float, top_y: float) -> ParallaxStrip:
	var strip := ParallaxStrip.new()
	strip.texture = ImageTexture.create_from_image(image)
	strip.factor = factor
	strip.position.y = top_y
	strip.cover_width = float(WorkoutArt.W)
	strip.auto_process = false
	return strip


## Recomputes the drawing model from the game's state.
func refresh() -> void:
	if game == null or game.state == null:
		return
	var state := game.state
	var cam := state.rider(game.view_peer())
	var cam_d := shown_distance(cam.peer_id) if cam != null else 0.0
	var world_x := cam_d * VISUAL_PX_PER_M
	for layer: ParallaxStrip in [sky, clouds, far_hills, mid_hills, near_trees]:
		if layer.world_x != world_x:
			layer.world_x = world_x
	var road := _road(state, cam, cam_d)
	model = {
		"road": road,
		"dash_offset": fposmod(world_x, 16.0),
		"blocks": _blocks(state),
		"now_x": RIDER_X,
		"markers": _markers(state, cam_d, road),
	}
	track.set_model(model)


## Road y per column; it follows the course elevation around the local rider in a course
## phase, and is flat otherwise. `cam_d` is the local rider's drawn distance: its course
## distance moves by the same offset from the state.
func _road(state: WorkoutState, cam: WorkoutRiderState, cam_d: float) -> PackedFloat64Array:
	var cols := int(ceil(float(WorkoutArt.W) / float(WorkoutTrackLayer.COLUMN_W)))
	var road := PackedFloat64Array()
	road.resize(cols)
	var index := cam.phase_index if cam != null and cam.phase_index >= 0 else state.phase_index
	var course_on := state.is_course_phase(index) and state.course != null
	var cam_cd := maxf(cam.course_d + (cam_d - cam.distance_m()), 0.0) if cam != null else 0.0
	var e0 := state.course.elevation_at(cam_cd) if course_on else 0.0
	for i in cols:
		var y := ROAD_Y
		if course_on:
			var x := float(i * WorkoutTrackLayer.COLUMN_W)
			var d := maxf(cam_cd + (x - RIDER_X) * MAP_M_PER_PX, 0.0)
			y = clampf(
				ROAD_Y - (state.course.elevation_at(d) - e0) * ELEV_PX_PER_M, ROAD_MIN_Y, ROAD_MAX_Y
			)
		road[i] = y
	return road


## Interval blocks: one per phase, x by plan time around "now", height by % FTP.
func _blocks(state: WorkoutState) -> Array:
	var out: Array = []
	var t := 0.0
	for p in state.phases:
		var x0 := RIDER_X + (t - state.plan_t) * STRIP_PX_PER_S
		var x1 := RIDER_X + (t + p.duration_s - state.plan_t) * STRIP_PX_PER_S
		t += p.duration_s
		if x1 < 0.0 or x0 > float(WorkoutArt.W) or x1 - x0 < 1.0:
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


## One marker per rider at its drawn distance from the local rider's (`cam_d`); the local
## rider is drawn last. Riders off screen sit at the edge with an arrow.
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
		var x := RIDER_X + (shown_distance(peer) - cam_d) / MAP_M_PER_PX
		var edge := 0
		if x < EDGE_MARGIN_LEFT:
			x = EDGE_MARGIN_LEFT
			edge = -1
		elif x > float(WorkoutArt.W) - EDGE_MARGIN_RIGHT:
			x = float(WorkoutArt.W) - EDGE_MARGIN_RIGHT
			edge = 1
		var col := clampi(int(x / float(WorkoutTrackLayer.COLUMN_W)), 0, road.size() - 1)
		var opts := {
			"bot": r.is_bot,
			"local": peer == local_peer,
			"in_band": r.in_band,
			"rescue": r.rescue,
			"afk": r.afk or not r.connected,
			"style": game.view_pennant() if peer == local_peer else "",
		}
		(
			out
			. append(
				{
					"peer": peer,
					"x": x,
					"y": road[col],
					"edge": edge,
					"shapes":
					_scaled(WorkoutArt.pennant_shapes(look, r.slot_index, opts), PENNANT_SCALE),
				}
			)
		)
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
