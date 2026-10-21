class_name WorkoutRideView
extends Node2D
## Workout's ride view (BRIEF 3.7): a 640 x 360 side-scrolling landscape. Sky, clouds and
## three parallax strips scroll with the local rider's distance; one pennant per rider
## (slot color + shape + pattern, BRIEF 3.9) sits on the road at its distance from the local
## rider; in Rolling road the road follows the course profile; the interval blocks are drawn
## on the ground with a "now" mark under the local rider. No people are drawn.
##
## It reads WorkoutGame.state (the host's rules state or a client's snapshot state) and
## never changes it. refresh() rebuilds the drawing model; _process calls it every frame.

const RIDER_X := 200.0
const ROAD_Y := 236.0
const ROAD_MIN_Y := 186.0
const ROAD_MAX_Y := 256.0
## Course and markers: metres per art pixel, vertical exaggeration (px per metre).
const MAP_M_PER_PX := 2.0
const ELEV_PX_PER_M := 1.5
## Parallax: art pixels per metre at factor 1 (gives a sense of speed).
const VISUAL_PX_PER_M := 3.0
## Interval strip: art pixels per plan second (640 px is about 21 minutes).
const STRIP_PX_PER_S := 0.5
const STRIP_BASE := 298.0
const STRIP_MAX_H := 32.0
const EDGE_MARGIN := 8.0

var game: WorkoutGame = null
var sky: WorkoutParallaxLayer = null
var clouds: WorkoutParallaxLayer = null
var far_hills: WorkoutParallaxLayer = null
var mid_hills: WorkoutParallaxLayer = null
var near_trees: WorkoutParallaxLayer = null
var track: WorkoutTrackLayer = null
## The latest model (tests and screenshots read it).
var model: Dictionary = {}
var _built: bool = false


func bind(p_game: WorkoutGame) -> void:
	game = p_game
	name = "WorkoutRideView"
	_build()


func _ready() -> void:
	_build()
	refresh()


func _process(_delta: float) -> void:
	refresh()


func _build() -> void:
	if _built:
		return
	_built = true
	sky = WorkoutParallaxLayer.make(ImageTexture.create_from_image(WorkoutArt.sky_image()), 0.0, 0.0)
	clouds = WorkoutParallaxLayer.make(ImageTexture.create_from_image(WorkoutArt.clouds_image()), 0.02, 30.0)
	far_hills = WorkoutParallaxLayer.make(ImageTexture.create_from_image(WorkoutArt.far_hills_image()), 0.06, 230.0 - WorkoutArt.FAR_SIZE.y)
	mid_hills = WorkoutParallaxLayer.make(ImageTexture.create_from_image(WorkoutArt.mid_hills_image()), 0.18, 238.0 - WorkoutArt.MID_SIZE.y)
	near_trees = WorkoutParallaxLayer.make(ImageTexture.create_from_image(WorkoutArt.trees_image()), 0.5, 244.0 - WorkoutArt.NEAR_SIZE.y)
	track = WorkoutTrackLayer.new()
	for layer: Node2D in [sky, clouds, far_hills, mid_hills, near_trees, track]:
		add_child(layer)


## Recomputes the drawing model from the game's state.
func refresh() -> void:
	if game == null or game.state == null:
		return
	var state := game.state
	var cam := state.rider(game.view_peer())
	var cam_d := cam.distance_m() if cam != null else 0.0
	var world_x := cam_d * VISUAL_PX_PER_M
	for layer: WorkoutParallaxLayer in [sky, clouds, far_hills, mid_hills, near_trees]:
		layer.set_scroll(world_x)
	var road := _road(state, cam)
	model = {
		"road": road,
		"dash_offset": fposmod(world_x, 16.0),
		"blocks": _blocks(state),
		"now_x": RIDER_X,
		"markers": _markers(state, cam, road),
	}
	track.set_model(model)


## Road y per column; it follows the course elevation around the local rider in a course
## phase, and is flat otherwise.
func _road(state: WorkoutState, cam: WorkoutRiderState) -> PackedFloat64Array:
	var cols := int(ceil(float(WorkoutArt.W) / float(WorkoutTrackLayer.COLUMN_W)))
	var road := PackedFloat64Array()
	road.resize(cols)
	var index := cam.phase_index if cam != null and cam.phase_index >= 0 else state.phase_index
	var course_on := state.is_course_phase(index) and state.course != null
	var cam_cd := cam.course_d if cam != null else 0.0
	var e0 := state.course.elevation_at(cam_cd) if course_on else 0.0
	for i in cols:
		var y := ROAD_Y
		if course_on:
			var x := float(i * WorkoutTrackLayer.COLUMN_W)
			var d := maxf(cam_cd + (x - RIDER_X) * MAP_M_PER_PX, 0.0)
			y = clampf(ROAD_Y - (state.course.elevation_at(d) - e0) * ELEV_PX_PER_M, ROAD_MIN_Y, ROAD_MAX_Y)
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
		elif p.kind == Wl.FREE:
			h0 = _strip_h(130.0)
			h1 = h0
		else:
			h0 = _strip_h(float(state.band_pct[1]))
			h1 = h0
			hatched = true
		var a := x0 + 1.0
		out.append({
			"points": PackedVector2Array([Vector2(a, STRIP_BASE - h0), Vector2(x1, STRIP_BASE - h1), Vector2(x1, STRIP_BASE), Vector2(a, STRIP_BASE)]),
			"color": WorkoutArt.phase_color(p),
			"hatched": hatched,
		})
	return out


static func _strip_h(pct: float) -> float:
	return clampf(pct / 150.0 * STRIP_MAX_H, 3.0, STRIP_MAX_H)


## One marker per rider at its distance from the local rider; the local rider is drawn
## last. Riders off screen sit at the edge with an arrow.
func _markers(state: WorkoutState, cam: WorkoutRiderState, road: PackedFloat64Array) -> Array:
	var out: Array = []
	var cam_d := cam.distance_m() if cam != null else 0.0
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
			look = {"color": slot.color, "shape": slot.shape, "pattern": slot.pattern, "hollow": slot.hollow}
		var x := RIDER_X + (r.distance_m() - cam_d) / MAP_M_PER_PX
		var edge := 0
		if x < EDGE_MARGIN:
			x = EDGE_MARGIN
			edge = -1
		elif x > float(WorkoutArt.W) - EDGE_MARGIN:
			x = float(WorkoutArt.W) - EDGE_MARGIN
			edge = 1
		var col := clampi(int(x / float(WorkoutTrackLayer.COLUMN_W)), 0, road.size() - 1)
		var opts := {
			"bot": r.is_bot, "local": peer == local_peer, "in_band": r.in_band,
			"rescue": r.rescue, "afk": r.afk or not r.connected,
			"style": game.view_pennant() if peer == local_peer else "",
		}
		out.append({
			"peer": peer, "x": x, "y": road[col], "edge": edge,
			"shapes": WorkoutArt.pennant_shapes(look, r.slot_index, opts),
		})
	return out


## The marker for `peer` in the latest model ({} if none).
func marker(peer: int) -> Dictionary:
	for m: Dictionary in model.get("markers", []):
		if int(m["peer"]) == peer:
			return m
	return {}
