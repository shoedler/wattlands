class_name FishingView
extends Node2D
## The 640 x 360 view: one ocean across the whole width (the HUD draws on top of it). The
## camera follows the local boat; every rider's boat, line, wobbler and fish is drawn when in
## sight. Back to front:
##  1. FishingScenery.paint_back: sky, clouds, haze islands, town and pier, water bands, the
##     stepped floor and its rocks, the edge's void and waterfall;
##  2. the local rider's menu hints (flat species silhouettes at their depth, the picked one
##     drawn) and every fish and wobbler, shifted along the palette ladder by the water around
##     them (FishingPaletteMap);
##  3. the prop wash, then the boats (others first, the local boat last; FishingBoatView);
##  4. the lines: straight even pixel runs (FishingRig.raster), the rod's slate above the water
##     and one colour under it that reads against the water where the line ends;
##  5. wakes (foam slabs in a fixed rhythm) and the bow wave, then the effects (splashes, catch
##     sparkles).
## It only reads `game.state`. On a client the boats are drawn between snapshots from a
## FishingSnapHistory with a render clock behind the newest snapshot by its mean spacing (GAME_SDK
## 12), never past the newest and never backwards. Effects and sounds come from FishingCues: the
## module's fx_event signal when it has one, else edges in the state. FishingAudio is a child.
## The HUD finds the view through the game's "fishing_view" meta and reads `model`.

const INTERP_DELAY_S := 0.1
const CLOCK_RESYNC_S := 1.5
const INTERP_DELAY_MAX_S := CLOCK_RESYNC_S - 0.1
const CLOCK_CATCHUP_TAU_S := 0.25
## Camera: the local boat's screen x while driving (heading right; mirrored heading left), the
## easing, and how the view depth follows the floor in sight.
const CAM_DRIVE_X := 210.0
const CAM_TAU_S := 1.1
## A camera goal this far away (a rejoin, a fast-forward) is jumped to, not eased toward.
const CAM_SNAP_M := 150.0
const DEPTH_TAU_S := 1.6
## Other riders' boats float this many px higher, on the far water (FishingScenery.FAR_ROWS),
## hazier and behind the local boat, so boats at the same x read as side by side.
const FAR_ROW_PX := 3
## A boat is drawn when its pivot is within this many px of the view.
const DRAW_MARGIN_PX := 120.0
## Leaps: one arc's length (s) and height (px).
const LEAP_S := 1.0
const LEAP_PX := 18.0
## Landing: inside ABOARD_M the fish hangs from the rod tip, ABOARD_DROP_PX under it.
const ABOARD_M := 6.0
const ABOARD_DROP_PX := 3.0
## Wake: foam slab lengths (px, at full wake) and the gap between them, on the surface row and
## two rows under it; the slabs step back GAIT_PX every GAIT_S so the foam seems to stream.
const WAKE_SLABS: Array[int] = [24, 16, 10, 6]
const WAKE_LOW: Array[int] = [12, 8, 4]
const WAKE_GAP_PX := 5
const GAIT_PX := 2
const GAIT_S := 0.2
## The bow wave, bottom row first: [offset ahead of the bow, width] per row (px).
const BOW_WAVE: Array[Vector2i] = [Vector2i(-2, 9), Vector2i(-1, 6), Vector2i(0, 4), Vector2i(0, 2)]
const META := "fishing_view"

var game: FishingGame = null
var scenery: FishingScenery = FishingScenery.new()
var cues: FishingCues = FishingCues.new()
var audio: FishingAudio = null
var effects: FishingEffects = null
var boats: Dictionary = {}
## World x (m) at the view's left edge.
var cam_m: float = 0.0
## Client: the host time (s) the boats are drawn at.
var render_t: float = 0.0
var events_connected: bool = false
## Every cue handled so far, newest last (tests read it; capped).
var cue_log: Array[Dictionary] = []
## What the last frame drew, for tests and the HUD: {"boats": {slot: Vector2 pivot}, "cam_m",
## "local", "hints": [{"pos", "sp", "selected"}], "fish": {slot: Rect2}, "lure": {slot: Vector2}}.
var model: Dictionary = {}

var _history: FishingSnapHistory = FishingSnapHistory.new()
var _own_history: bool = true
var _seen_tick: int = -1
var _clock_set: bool = false
var _built: bool = false
var _cam_set: bool = false
var _local_slot: int = -1
var _t: float = 0.0
var _fish: Dictionary = {}
var _fish_mat: Dictionary = {}
var _lure: Dictionary = {}
var _lure_mat: Dictionary = {}
var _hints: Array[Sprite2D] = []
var _hint_mats: Array[ShaderMaterial] = []
var _shown: Dictionary = {}
var _line_m: Dictionary = {}
var _leap: Dictionary = {}
var _boat_layer: Node2D = null
var _layers: Array[FishingDrawLayer] = []
var _pending: Array[Dictionary] = []


func _ready() -> void:
	name = "FishingView"
	_build()


func _process(delta: float) -> void:
	advance(delta)


## One frame of `delta` seconds: builds once the state exists, moves the clocks and the camera,
## places every boat, fish, wobbler and hint, hands out the cues.
func advance(delta: float) -> void:
	if not _built:
		_build()
	if not _built:
		return
	var st := game.state
	_t += delta
	if _is_client():
		_track_snapshots(st)
		_advance_clock(delta)
	for r in st.riders:
		_shown[r.slot] = _values(r)
	_camera(delta, st)
	var want_depth := scenery.target_view_depth(cam_m)
	if _t <= delta:
		scenery.view_depth_m = want_depth
	var ease := 1.0 - exp(-delta / DEPTH_TAU_S)
	scenery.view_depth_m += (want_depth - scenery.view_depth_m) * ease
	model["cam_m"] = cam_m
	model["local"] = _local_slot
	model["boats"] = {}
	model["fish"] = {}
	model["lure"] = {}
	for r in st.riders:
		_place_catch(r, delta)
	for r in st.riders:
		_place_boat(r, delta)
	_place_hints(st.rider(_local_slot))
	if not events_connected:
		for c in cues.diff(st):
			_pending.append(c)
	for c in _pending:
		_handle(c)
	_pending.clear()
	effects.tick(delta, cam_m)
	for layer in _layers:
		layer.queue_redraw()
	if audio != null:
		var local := st.rider(_local_slot)
		var bv: FishingBoatView = boats.get(_local_slot)
		audio.update(delta, local, bv.winch_mps if bv != null else 0.0)


## The local rider's slot (-1 when the local peer rides no boat).
func local_slot() -> int:
	return _local_slot


## The boat view of `slot` (null when there is none).
func boat_view(slot: int) -> FishingBoatView:
	return boats.get(slot)


## Client: how far render_t runs behind the newest snapshot.
func interp_delay() -> float:
	return clampf(_history.mean_spacing(), INTERP_DELAY_S, INTERP_DELAY_MAX_S)


## The module's fx_event handler: queues the event's cues for the next frame.
func on_fx_event(event: Dictionary) -> void:
	for c in FishingCues.from_event(event):
		_pending.append(c)


## The screen point of world `x_m` at `depth_m` (negative depth: above the surface).
func to_screen(x_m: float, depth_m: float) -> Vector2:
	var y := (
		scenery.y_of_depth(depth_m) if depth_m >= 0.0 else float(FishingScenery.SURF_Y) + depth_m
	)
	return Vector2(FishingScenery.screen_x(x_m, cam_m), y)


## The shown values of `slot` ({} before the first frame).
func shown(slot: int) -> Dictionary:
	return _shown.get(slot, {})


func _is_client() -> bool:
	return game != null and game.ctx != null and game.ctx.role == Wl.CLIENT


func _build() -> void:
	if _built or game == null or game.state == null or game.ctx == null:
		return
	_built = true
	game.set_meta(META, self)
	scenery.world = game.state.world
	if game.has_signal("fx_event"):
		game.connect("fx_event", on_fx_event)
		events_connected = true
	var h: Variant = game.get("history")
	if h is FishingSnapHistory:
		_history = h
		_own_history = false
	_local_slot = -1
	for r in game.state.riders:
		if r.peer == game.ctx.local_peer:
			_local_slot = r.slot
	_layer("Back", _paint_back)
	var under := Node2D.new()
	under.name = "Underwater"
	add_child(under)
	for i in FishingConst.HINTS_PER_STOP:
		var s := _sprite(under, "Hint%d" % i)
		_hints.append(s)
		_hint_mats.append(FishingPaletteMap.apply(s))
	for r in game.state.riders:
		_fish[r.slot] = _sprite(under, "Fish%d" % r.slot)
		_fish_mat[r.slot] = FishingPaletteMap.apply(_fish[r.slot])
		_lure[r.slot] = _sprite(under, "Lure%d" % r.slot)
		_lure_mat[r.slot] = FishingPaletteMap.apply(_lure[r.slot])
	_layer("Wash", _paint_wash)
	_boat_layer = Node2D.new()
	_boat_layer.name = "Boats"
	add_child(_boat_layer)
	var order: Array[FishingRiderState] = []
	for r in game.state.riders:
		if r.slot != _local_slot:
			order.append(r)
	var local := game.state.rider(_local_slot)
	if local != null:
		order.append(local)
	for r in order:
		var b := FishingBoatView.new()
		b.name = "Boat%d" % r.slot
		b.set_slot(r.slot, _line_colour(r))
		b.set_far(r.slot != _local_slot)
		boats[r.slot] = b
		_boat_layer.add_child(b)
	_layer("Lines", _paint_lines)
	_layer("Front", _paint_front)
	effects = FishingEffects.new()
	add_child(effects)
	audio = FishingAudio.new()
	add_child(audio)


func _layer(p_name: String, painter: Callable) -> void:
	var layer := FishingDrawLayer.make(p_name, painter)
	_layers.append(layer)
	add_child(layer)


func _sprite(parent: Node, p_name: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = p_name
	s.centered = false
	s.visible = false
	parent.add_child(s)
	return s


## The line cosmetic's colour (cosmetics.json "line" items; the default is FishingPalette.LINE).
func _line_colour(r: FishingRiderState) -> Color:
	var want := r.cosmetics[0] if r.cosmetics.size() > 0 else 0
	if want <= 0 or game.content == null:
		return FishingPalette.LINE
	var items := game.content.cosmetics_of("line")
	if want - 1 < items.size() and items[want - 1] is Dictionary:
		return FishingPalette.color_of(str(items[want - 1].get("value", "")), FishingPalette.LINE)
	return FishingPalette.LINE


## Client: a new tick in the state is a snapshot just applied; record it unless the module does.
func _track_snapshots(st: FishingState) -> void:
	if _own_history and st.tick != _seen_tick:
		_seen_tick = st.tick
		_history.push(st.t, st)


## render_t moves with the frame clock, catches up softly toward newest - interp_delay() and
## stops at the newest snapshot; it never runs backwards except by a resync jump.
func _advance_clock(delta: float) -> void:
	if _history.is_empty():
		return
	var newest := _history.newest_t()
	var goal := newest - interp_delay()
	if not _clock_set or absf(goal - render_t) > CLOCK_RESYNC_S:
		render_t = goal
		_clock_set = true
		return
	render_t += maxf(delta, 0.0)
	var behind := goal - render_t
	if behind > 0.0:
		render_t += behind * (1.0 - exp(-maxf(delta, 0.0) / CLOCK_CATCHUP_TAU_S))
	render_t = minf(render_t, newest)


func _values(r: FishingRiderState) -> Dictionary:
	var v := FishingSnapHistory.values_of(r)
	if _is_client() and _clock_set:
		for k: String in FishingSnapHistory.KEYS:
			v[k] = _history.value_at(r.slot, k, render_t, float(v[k]))
	return v


func _camera(delta: float, st: FishingState) -> void:
	var r := st.rider(_local_slot)
	if r == null and not st.riders.is_empty():
		r = st.riders[0]
	if r == null:
		return
	var v: Dictionary = _shown[r.slot]
	var sx := float(FishingScenery.W) * 0.5
	match r.action:
		FishingConst.A_DRIVE, FishingConst.A_DRIFT, FishingConst.A_HOME:
			sx = CAM_DRIVE_X if r.heading > 0 else float(FishingScenery.W) - CAM_DRIVE_X
		FishingConst.A_FIGHT, FishingConst.A_LAND:
			var half := clampf(absf(float(v["fdx"])) * FishingScenery.PX_PER_M * 0.5, 0.0, 200.0)
			sx += half * signf(-float(v["fdx"])) if absf(float(v["fdx"])) > 0.1 else 0.0
	var goal := float(v["x"]) - sx / FishingScenery.PX_PER_M
	if not _cam_set or absf(goal - cam_m) > CAM_SNAP_M:
		cam_m = goal
		_cam_set = true
	else:
		cam_m += (goal - cam_m) * (1.0 - exp(-delta / CAM_TAU_S))


func _place_boat(r: FishingRiderState, delta: float) -> void:
	var b: FishingBoatView = boats.get(r.slot)
	if b == null:
		return
	var v: Dictionary = _shown[r.slot]
	var sx := FishingScenery.screen_x(float(v["x"]), cam_m)
	b.visible = sx > -DRAW_MARGIN_PX and sx < float(FishingScenery.W) + DRAW_MARGIN_PX
	var wx := float(v["x"]) * FishingScenery.PX_PER_M
	b.heading = r.heading
	b.pitch_deg = float(v["pitch"])
	b.bob_px = -float(FishingScenery.wave(wx, _t))
	b.cadence = float(v["cad"])
	var line := r.line_m()
	var was := float(_line_m.get(r.slot, line))
	_line_m[r.slot] = line
	b.winch_mps = (was - line) / delta if delta > 0.0 else 0.0
	b.fishing_target = (
		1.0
		if (
			r.action
			in [FishingConst.A_CAST, FishingConst.A_WAIT, FishingConst.A_FIGHT, FishingConst.A_LAND]
		)
		else 0.0
	)
	b.prop_drive = clampf(absf(r.v_mps) / 4.0, 0.0, 1.5)
	b.tension = _tension(r)
	b.position = Vector2(roundf(sx), float(FishingScenery.SURF_Y - (FAR_ROW_PX if b.far else 0)))
	var end := _line_end(r)
	var tip := b.rod_tip()
	if end != Vector2.INF and end.distance_to(tip) > 1.0:
		var d := (end - tip).normalized()
		b.pull_dir = Vector2(d.x * float(r.heading), d.y)
	else:
		b.pull_dir = Vector2.DOWN
	b.advance(delta)
	(model["boats"] as Dictionary)[r.slot] = b.position


## Rod tension 0..1: a fight's strain (all of it on a run), the landing, a wobbler working.
func _tension(r: FishingRiderState) -> float:
	match r.action:
		FishingConst.A_FIGHT:
			if r.fish.off_line:
				return 0.0
			if r.fish.run_active:
				return 1.0
			return clampf(0.35 + 0.65 * r.strain - 0.3 * r.slack, 0.0, 1.0)
		FishingConst.A_LAND:
			return 0.6
		FishingConst.A_WAIT:
			return 0.15
		FishingConst.A_CAST:
			return 0.25
	return 0.0


## The fish on the line (fight, landing) and the wobbler (cast, wait), placed and tinted.
func _place_catch(r: FishingRiderState, delta: float) -> void:
	var v: Dictionary = _shown[r.slot]
	var fish: Sprite2D = _fish[r.slot]
	var lure: Sprite2D = _lure[r.slot]
	var on := r.in_fight() and r.fish.sp >= 0 and not r.fish.off_line
	fish.visible = on
	lure.visible = r.action == FishingConst.A_CAST or r.action == FishingConst.A_WAIT
	if lure.visible:
		var p := to_screen(float(v["x"]) + float(v["ldx"]), float(v["lz"]))
		var id := "lure"
		lure.texture = FishingSprites.frame(id, floori(_t * 6.0))
		lure.flip_h = r.heading < 0
		lure.position = (p - Vector2(FishingSprites.anchor(id))).round()
		_map_depth(_lure_mat[r.slot], float(v["lz"]))
		(model["lure"] as Dictionary)[r.slot] = p
	if not on:
		_leap.erase(r.slot)
		return
	var id2 := FishingSprites.fish_id(r.fish.sp)
	var depth := float(v["fz"])
	var mouth := to_screen(float(v["x"]) + float(v["fdx"]), depth)
	var b: FishingBoatView = boats.get(r.slot)
	var aboard := (
		r.action == FishingConst.A_LAND and r.fish.d < ABOARD_M and b != null and b.visible
	)
	if aboard:
		mouth = b.rod_tip().round() + Vector2(0, ABOARD_DROP_PX)
		depth = 0.0
	var leap: Dictionary = _leap.get(r.slot, {})
	if not leap.is_empty():
		leap["t"] = float(leap["t"]) + delta
		var u := float(leap["t"]) / LEAP_S
		if u >= float(leap["n"]):
			_leap.erase(r.slot)
		else:
			var f := fmod(u, 1.0)
			mouth.y = float(FishingScenery.SURF_Y) - sin(PI * f) * LEAP_PX
			if int(u) != int(leap["k"]):
				leap["k"] = int(u)
				effects.spawn("fx_splash", float(v["x"]) + float(v["fdx"]), FishingScenery.SURF_Y)
	var size := FishingSprites.size_of(id2)
	fish.texture = FishingSprites.frame(id2, floori(_t * (8.0 if r.fish.run_active else 4.0)))
	var boat_x := FishingScenery.screen_x(float(v["x"]), cam_m)
	fish.flip_h = mouth.x < boat_x if not aboard else r.heading > 0
	var a := Vector2(FishingSprites.anchor(id2))
	var top_left := mouth - a
	if fish.flip_h:
		top_left = mouth - Vector2(float(size.x) - a.x, a.y)
	fish.position = top_left.round()
	_map_depth(_fish_mat[r.slot], depth if mouth.y > float(FishingScenery.SURF_Y) else 0.0)
	(model["fish"] as Dictionary)[r.slot] = Rect2(fish.position, Vector2(size))


## A fish or wobbler at `depth_m`: dark on the light water bands, lit below (palette shift).
func _map_depth(m: ShaderMaterial, depth_m: float) -> void:
	FishingPaletteMap.set_flat(m, false)
	FishingPaletteMap.set_shift(m, FishingPaletteMap.shift_for(FishingScenery.band_at(depth_m)))


## The local rider's menu: each fish hint as its species' flat silhouette at its depth (a step
## off the water colour); the highlighted cast entry shows the fish itself.
func _place_hints(r: FishingRiderState) -> void:
	var out: Array = []
	for i in _hints.size():
		var s := _hints[i]
		s.visible = r != null and r.action == FishingConst.A_MENU and i < r.hint_count()
		if not s.visible:
			continue
		var sp := int(r.hints[4 * i])
		var id := FishingSprites.fish_id(sp)
		var x := float(_shown[r.slot]["x"]) + float(r.hints[4 * i + 1])
		var depth := float(r.hints[4 * i + 2])
		var fl := scenery.world.floor_depth_m(x) if scenery.world != null else INF
		depth = minf(depth, maxf(fl - 1.0, 0.5))
		var p := to_screen(x, depth)
		s.texture = FishingSprites.frame(id, floori(_t * 3.0) + i)
		s.position = (p - Vector2(FishingSprites.size_of(id)) * 0.5).round()
		var lit := r.selected >= 0 and r.selected < r.menu.size() and r.menu[r.selected] == i
		_map_depth(_hint_mats[i], depth)
		if not lit:
			FishingPaletteMap.set_flat(_hint_mats[i], true, silhouette(depth))
		out.append({"pos": p, "sp": sp, "selected": lit, "index": i})
	model["hints"] = out


## Where the line ends in view px: the fish's mouth or the wobbler (Vector2.INF: no line out).
func _line_end(r: FishingRiderState) -> Vector2:
	var fr: Variant = (model.get("fish", {}) as Dictionary).get(r.slot)
	if fr is Rect2 and (_fish[r.slot] as Sprite2D).visible:
		var rect: Rect2 = fr
		var y := rect.position.y + float(FishingSprites.anchor(_fish_id(r)).y)
		var flip := (_fish[r.slot] as Sprite2D).flip_h
		return Vector2(rect.end.x - 1.0 if flip else rect.position.x, y)
	var lp: Variant = (model.get("lure", {}) as Dictionary).get(r.slot)
	if lp is Vector2 and (_lure[r.slot] as Sprite2D).visible:
		return lp
	return Vector2.INF


func _fish_id(r: FishingRiderState) -> String:
	return FishingSprites.fish_id(r.fish.sp)


func _handle(c: Dictionary) -> void:
	cue_log.append(c)
	if cue_log.size() > 64:
		cue_log.pop_front()
	var l := int(c.get("l", -1))
	var r := game.state.rider(l)
	if r != null and _shown.has(l):
		var v: Dictionary = _shown[l]
		match str(c.get("k", "")):
			FishingCues.CUE_CAST:
				effects.spawn("fx_splash", float(v["x"]) + float(v["ldx"]), FishingScenery.SURF_Y)
			FishingCues.CUE_HOOKUP, FishingCues.CUE_SNAP, FishingCues.CUE_THROWN:
				effects.spawn("fx_splash", float(v["x"]) + float(v["fdx"]), FishingScenery.SURF_Y)
			FishingCues.CUE_JUMP:
				_leap[l] = {"t": 0.0, "n": int(c.get("leaps", 2)), "k": -1}
			FishingCues.CUE_LANDED:
				var b: FishingBoatView = boats.get(l)
				var y := b.rod_tip().y + 6.0 if b != null else FishingScenery.SURF_Y - 10.0
				effects.spawn("fx_sparkle", float(v["x"]), y)
	if audio != null:
		audio.cue(c, l == _local_slot)


func _paint_back(c: CanvasItem) -> void:
	scenery.paint_back(c, cam_m, _t)


## Prop wash under the surface behind every driving boat's screw: two short slabs streaming
## back.
## The farther boats' wakes are drawn here too, behind every boat.
func _paint_wash(c: CanvasItem) -> void:
	var gait := (floori(_t / GAIT_S) % 2) * GAIT_PX
	for slot: int in boats:
		var b: FishingBoatView = boats[slot]
		var r := game.state.rider(slot)
		var v: Dictionary = _shown.get(slot, {})
		if b.visible and b.far and not v.is_empty() and float(v["wake"]) > 0.04:
			_paint_wake(c, b, float(v["wake"]))
		if not b.visible or b.far or r == null or absf(r.v_mps) < 0.3:
			continue
		var hub := b.pixel_of(Vector2i(FishingRig.PROP_HUB))
		var dir := -b.heading
		for k in 2:
			var w: int = [5, 3][k]
			var x0 := hub.x + float(dir * (3 + gait + k * 8))
			var x := x0 if dir > 0 else x0 - float(w - 1)
			c.draw_rect(Rect2(x, hub.y + float(k), w, 1), FishingPalette.HAZE)


func _paint_lines(c: CanvasItem) -> void:
	for slot: int in boats:
		var b: FishingBoatView = boats[slot]
		var r := game.state.rider(slot)
		if r == null:
			continue
		var end := _line_end(r)
		if end == Vector2.INF:
			continue
		var tip := b.rod_tip()
		if not b.visible and (end.x < 0.0 or end.x > float(FishingScenery.W)):
			continue
		_draw_line(c, Vector2i(tip), Vector2i(end.floor()), r)


## The line: one straight run from the rod tip to where it enters the water (the rod's slate,
## or the line cosmetic), then straight in an even slope (or, slack, in two runs) to the fish in
## one colour that reads against the water where it ends.
func _draw_line(c: CanvasItem, tip: Vector2i, end: Vector2i, r: FishingRiderState) -> void:
	var b: FishingBoatView = boats[r.slot]
	var surf := FishingScenery.SURF_Y
	var strain := r.strain if r.action == FishingConst.A_FIGHT else 0.2
	var slack := r.slack if r.action == FishingConst.A_FIGHT else 0.3
	if end.y < surf:
		_run(c, [tip, end], b.line_above())
		return
	var k := clampf(0.1 + 0.15 * (1.0 - strain), 0.1, 0.3)
	var natural := roundi(lerpf(float(tip.x), float(end.x), k))
	var entry := Vector2i(FishingRig.even_entry(natural, end, surf), surf)
	_run(c, [tip, entry - Vector2i(0, 1)], b.line_above())
	_run(c, FishingRig.line(entry, end, slack, strain), under_line(scenery.depth_of_y(end.y)))


func _run(c: CanvasItem, points: Array[Vector2i], col: Color) -> void:
	for p in FishingRig.raster_path(points):
		c.draw_rect(Rect2(Vector2(p), Vector2.ONE), col)


## The line's colour under water when it ends at `depth_m`: dark slate-teal in the two light
## bands, haze below (it reads against every band it crosses on the way).
static func under_line(depth_m: float) -> Color:
	return FishingPalette.DEEP if FishingScenery.band_at(depth_m) <= 1 else FishingPalette.HAZE


## A hint's silhouette at `depth_m`: one step darker than the water (lighter in the abyss).
static func silhouette(depth_m: float) -> Color:
	var w := FishingScenery.water_at(depth_m)
	return FishingPalette.darker(w, 1 if w != FishingPalette.ABYSS else -1)


func _paint_front(c: CanvasItem) -> void:
	for slot: int in boats:
		var b: FishingBoatView = boats[slot]
		var v: Dictionary = _shown.get(slot, {})
		if b.visible and not b.far and not v.is_empty() and float(v["wake"]) > 0.04:
			_paint_wake(c, b, float(v["wake"]))


## The wake: foam slabs on the surface row behind the stern (and a shorter row two rows under
## it), each WAKE_GAP_PX apart, their lengths scaled by the wake; at higher wake a bow wave.
func _paint_wake(c: CanvasItem, b: FishingBoatView, wake: float) -> void:
	var dir := -b.heading
	var stern := b.pixel_of(FishingRig.WAKE_AT)
	var y0 := b.position.y
	var gait := (floori(_t / GAIT_S) % 2) * GAIT_PX
	var rows: Array = [[WAKE_SLABS, 0, 0], [WAKE_LOW, 2, 4]]
	for row: Array in rows:
		var x := stern.x + float(dir * (gait + int(row[2])))
		for len_full: int in row[0]:
			var w := roundi(float(len_full) * clampf(wake, 0.0, 1.0))
			if w < 2:
				break
			var left := x if dir > 0 else x - float(w - 1)
			c.draw_rect(Rect2(left, y0 + float(row[1]), w, 1), FishingPalette.FOAM)
			x += float(dir * (w + WAKE_GAP_PX))
	if wake < 0.3:
		return
	var bow := b.pixel_of(FishingRig.SPRAY_AT)
	var h := b.heading
	var y_surf := float(FishingScenery.SURF_Y - (FAR_ROW_PX if b.far else 0))
	for k in BOW_WAVE.size():
		var row: Vector2i = BOW_WAVE[k]
		var w := row.y if wake >= 0.7 or k < 2 else row.y / 2
		var x0 := bow.x + float(row.x * h)
		var left := x0 if h > 0 else x0 - float(w - 1)
		c.draw_rect(Rect2(left, y_surf - float(k), w, 1), FishingPalette.FOAM)
