class_name FishingView
extends Node2D
## The view: one ocean across the whole width (the HUD draws on top of it), laid out from the
## art size of the SubViewport it draws in (the PixelViewport's: 640 x 360 at the base, any flex
## size; FishingScenery.set_size() every frame; the base size outside one). The camera follows
## the local boat; every rider's boat, line, wobbler and fish is drawn when in sight. Back to
## front:
##  1. FishingScenery.paint_back: sky, clouds, haze islands, town and pier, water bands, the
##     stepped floor and its rocks, the edge's void and waterfall;
##  2. the local rider's menu hints (flat species silhouettes at their depth, the picked one
##     drawn) and every fish (its pose from the line: swimming, pulling at 15 or 30 degrees,
##     tired) and wobbler, shifted along the palette ladder by the water around them
##     (FishingPaletteMap);
##  3. behind the hulls: each boat's far V arm and prop wash, the farther boats' whitewater
##     (FishingWhitewater) and the lines: each a FishingRope drawn as a clean 1 px curve, the
##     rod's slate above the water and a colour per water band under it;
##  4. the boats (others first, the local boat last; FishingBoatView; the hull heaves by whole
##     pixels and takes the pose its pitch asks for, the long-shaft prop always under water);
##  5. the local boat's whitewater (the wake, the stern mound, the rooster tail, the bow water,
##     towing and braking water), then the effects (splashes, catch sparkles).
## It only reads `game.state`. Boats and fish are drawn between states from a FishingSnapHistory
## every frame: on a client with a render clock behind the newest snapshot by its mean spacing
## (GAME_SDK 12), on the host and in SOLO one sim step behind the newest step (the sim-clock
## fraction), never past the newest and never backwards. Effects and sounds come from
## FishingCues: the module's fx_event signal when it has one, else edges in the state.
## FishingAudio is a child. The HUD finds the view through the game's "fishing_view" meta and
## reads `model`.

const INTERP_DELAY_S := 0.1
const CLOCK_RESYNC_S := 1.5
const INTERP_DELAY_MAX_S := CLOCK_RESYNC_S - 0.1
const CLOCK_CATCHUP_TAU_S := 0.25
## Camera: the local boat's screen x while driving (heading right; mirrored heading left) as a
## share of the view's width, and the easing.
const CAM_DRIVE_U := 210.0 / 640.0
const CAM_TAU_S := 1.1
## A camera goal this far away (a rejoin, a fast-forward) is jumped to, not eased toward.
const CAM_SNAP_M := 150.0
## The view depth (FishingScenery.view_depth_m) eases toward a goal over DEPTH_TAU_S; the goal
## moves only when the floor in sight asks for DEPTH_DEEPER more depth or DEPTH_SHALLOWER less
## (hysteresis), so the floor rows keep still while the boat moves over small steps, and the
## easing ends on the goal.
const DEPTH_TAU_S := 0.9
const DEPTH_DEEPER := 0.08
const DEPTH_SHALLOWER := 0.3
const DEPTH_DONE := 0.002
## The boat's heave in whole px per m (FishingRiderState.heave_m) and its range (the prop stays
## in the water: at most HEAVE_UP_PX up).
const HEAVE_PX_PER_M := 60.0
const HEAVE_UP_PX := 4
## Down the hull moves less (it sinks into its own foam otherwise): HEAVE_DOWN_PX_PER_M, at most
## HEAVE_DOWN_PX.
const HEAVE_DOWN_PX_PER_M := 20.0
const HEAVE_DOWN_PX := 2
## The hull's trim and heave made plain per water state (shown_pitch(), shown_heave()): bow up
## and stern squatting on the hump (pose 5 and a row down: stern 3, bow 7 up), flat on the plane
## (pose 2 at most), towed stern first (pose 4 and 3 rows down: stern 5 down, bow 3 up).
const CLIMB_PITCH := 12.6
## Cruising in displacement (mockup E4 50 %) the hull rides at its waterline, the bow up at
## least pose 1.
const CRUISE_PITCH := 1.6
## Cruising, the bow wave carries the hull this many px up, so at least six dark hull rows show
## above the water midships.
const CRUISE_LIFT_PX := 1
const CLIMB_SQUAT_PX := 1
const PLANE_PITCH := 3.6
const TOW_PITCH := 9.0
const TOW_SQUAT_PX := 3
## Fish poses: tired under TIRED_S stamina (and in the Landing); a pull pose from rod tension
## PULL15_AT (the 15 degree pose) or PULL30_AT (up to the 30 degree one), picked by the line's
## angle at the mouth (level under PULL15_DEG, steep from PULL30_DEG); the swim cycle at SWIM_FPS
## (SWIM_RUN_FPS on a run).
const TIRED_S := 0.12
const PULL15_AT := 0.45
const PULL30_AT := 0.6
const PULL15_DEG := 8.0
const PULL30_DEG := 22.0
const SWIM_FPS := 7.0
const SWIM_RUN_FPS := 12.0
## Other riders' boats float this many px higher, on the far water (FishingScenery.FAR_ROWS),
## hazier and behind the local boat, so boats at the same x read as side by side.
const FAR_ROW_PX := 6
## A farther boat's foam waterline: its rows and how far it runs past the hull at each end.
## A menu hint's least gap to the edges of the water band it swims in (px).
const HINT_BAND_GAP_PX := 2
const FAR_WATERLINE_ROWS := 2
const FAR_WATERLINE_OVER := 3
## A boat is drawn when its pivot is within this many px of the view.
const DRAW_MARGIN_PX := 120.0
## Leaps: one arc's length (s) and height (px).
const LEAP_S := 1.0
const LEAP_PX := 18.0
## A hooked fish keeps this many px clear of the floor.
const FISH_FLOOR_GAP_PX := 6.0
## Landing: inside ABOARD_M the fish hangs from the rod tip, ABOARD_DROP_PX under it.
const ABOARD_M := 6.0
const ABOARD_DROP_PX := 3.0
## The rope's slack and strain while a wobbler works (nearly taut, so a trolled line sweeps
## back), the least strain it shows in a fight, and the water's push on a line per m/s of the
## boat (px/s^2).
const WAIT_SLACK := 0.15
const WAIT_STRAIN := 0.3
const FIGHT_STRAIN_MIN := 0.3
## A rod in a fight is never drawn straight: at least this tension (FishingRig.ROD_BENT_AT and up).
const FIGHT_BEND_MIN := 0.4
const FLOW_PER_MPS := 10.0
## The camera leads ahead of a driving boat by LEAD_S seconds of its speed (at most LEAD_MAX_PX),
## eased over LEAD_TAU_S.
const LEAD_S := 2.2
const LEAD_MAX_PX := 150.0
const LEAD_TAU_S := 1.5
const META := "fishing_view"

var game: FishingGame = null
var scenery: FishingScenery = FishingScenery.new()
var cues: FishingCues = FishingCues.new()
var audio: FishingAudio = null
var effects: FishingEffects = null
var boats: Dictionary = {}
## World x (m) at the view's left edge.
var cam_m: float = 0.0
## The game time (s) boats and fish are drawn at (the host's on a client).
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
## slot -> FishingRope: each rider's line, stepped every frame.
var _ropes: Dictionary = {}
## The boats' water (FishingWhitewater) and each boat's odometer: px it travelled, shown.
var whitewater: FishingWhitewater = FishingWhitewater.new()
var _odo: Dictionary = {}
var _last_x: Dictionary = {}
## The camera's eased lead (px).
var _lead: float = 0.0
## The view depth's goal (m; see DEPTH_DEEPER) and the frame time since the newest state.
var _depth_goal: float = -1.0
var _since: float = 0.0


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
	var vp := get_viewport() if is_inside_tree() else null
	if vp is SubViewport:
		scenery.set_size((vp as SubViewport).size)
	_track_snapshots(st)
	if _is_client():
		_advance_clock(delta)
	else:
		_advance_local_clock(delta)
	for r in st.riders:
		_shown[r.slot] = _values(r)
	_camera(delta, st)
	_ease_depth(delta)
	model["cam_m"] = cam_m
	model["size"] = scenery.size()
	model["mouth"] = {}
	model["fish_frame"] = {}
	model["local"] = _local_slot
	model["boats"] = {}
	model["fish"] = {}
	model["lure"] = {}
	for r in st.riders:
		_place_boat(r, delta)
	for r in st.riders:
		_place_catch(r, delta)
	_place_hints(st.rider(_local_slot))
	for r in st.riders:
		_step_rope(r, delta)
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
		audio.update(delta, boats, st, _local_slot)


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


## The art size drawn (px).
func art_size() -> Vector2i:
	return scenery.size()


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
	_layer("Lines", _paint_lines)
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
	_layer("Front", _paint_front)
	effects = FishingEffects.new()
	add_child(effects)
	audio = FishingAudio.new()
	audio.rng_seed = SeededRng.derive(game.ctx.seed, "fishing:audio")
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


## Records the state: on a client each new tick (a snapshot just applied) unless the module
## does; on the host and in SOLO every frame (a push at the newest time replaces it).
func _track_snapshots(st: FishingState) -> void:
	if not _own_history:
		return
	if st.tick != _seen_tick:
		_seen_tick = st.tick
		_since = 0.0
		_history.push(st.t, st)
	elif not _is_client():
		_history.push(st.t, st)


## Host and SOLO: render_t runs one sim step behind the newest state, moving with the frame
## clock between steps (the sim-clock fraction), catching up when steps come faster than frames.
func _advance_local_clock(delta: float) -> void:
	if _history.is_empty():
		return
	var newest := _history.newest_t()
	var goal := newest - Wl.SIM_DT + minf(_since, Wl.SIM_DT)
	_since += maxf(delta, 0.0)
	if not _clock_set or absf(goal - render_t) > CLOCK_RESYNC_S:
		render_t = goal
		_clock_set = true
		return
	var next := maxf(render_t + maxf(delta, 0.0), goal - Wl.SIM_DT)
	render_t = clampf(next, render_t, newest)


## The view depth eases toward its goal, which moves only past the hysteresis band.
func _ease_depth(delta: float) -> void:
	var want := scenery.target_view_depth(cam_m)
	var first := _depth_goal < 0.0
	if (
		first
		or want > _depth_goal * (1.0 + DEPTH_DEEPER)
		or want < _depth_goal * (1.0 - DEPTH_SHALLOWER)
	):
		_depth_goal = want
	if first:
		scenery.view_depth_m = _depth_goal
		return
	var ease := 1.0 - exp(-delta / DEPTH_TAU_S)
	scenery.view_depth_m += (_depth_goal - scenery.view_depth_m) * ease
	if absf(_depth_goal - scenery.view_depth_m) <= _depth_goal * DEPTH_DONE:
		scenery.view_depth_m = _depth_goal


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
	if _clock_set:
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
	var vw := float(scenery.w)
	var sx := vw * 0.5
	var lead := lead_px(r.v_mps)
	var centre_m := cam_m + vw * 0.5 / FishingScenery.PX_PER_M
	var snap := not _cam_set or absf(float(v["x"]) - centre_m) > CAM_SNAP_M
	_lead = lead if snap else _lead + (lead - _lead) * (1.0 - exp(-delta / LEAD_TAU_S))
	match r.action:
		FishingConst.A_DRIVE, FishingConst.A_DRIFT, FishingConst.A_HOME:
			var x := roundf(vw * CAM_DRIVE_U) - _lead
			sx = x if r.heading > 0 else vw - x
		FishingConst.A_FIGHT, FishingConst.A_LAND:
			var half := clampf(absf(float(v["fdx"])) * FishingScenery.PX_PER_M * 0.5, 0.0, 200.0)
			sx += half * signf(-float(v["fdx"])) if absf(float(v["fdx"])) > 0.1 else 0.0
	var goal := float(v["x"]) - sx / FishingScenery.PX_PER_M
	if not _cam_set or absf(goal - cam_m) > CAM_SNAP_M:
		cam_m = goal
		_cam_set = true
	else:
		cam_m += (goal - cam_m) * (1.0 - exp(-delta / CAM_TAU_S))


## How far (px) the camera leads ahead of a boat driving at `v_mps`.
static func lead_px(v_mps: float) -> float:
	return clampf(absf(v_mps) * LEAD_S * FishingScenery.PX_PER_M, 0.0, LEAD_MAX_PX)


func _place_boat(r: FishingRiderState, delta: float) -> void:
	var b: FishingBoatView = boats.get(r.slot)
	if b == null:
		return
	var v: Dictionary = _shown[r.slot]
	var sx := FishingScenery.screen_x(float(v["x"]), cam_m)
	b.visible = sx > -DRAW_MARGIN_PX and sx < float(scenery.w) + DRAW_MARGIN_PX
	var wx := float(v["x"]) * FishingScenery.PX_PER_M
	b.heading = r.heading
	b.pitch_deg = shown_pitch(r, float(v["pitch"]))
	b.brake = float(v["brake"])
	b.bob_px = -float(FishingScenery.wave(wx, _t))
	b.heave_px = shown_heave(r, heave_px(float(v["heave"])))
	b.cadence = raw_cadence(r, float(v["cad"]))
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
	b.advance(delta)
	var was_x := float(_last_x.get(r.slot, float(v["x"])))
	_last_x[r.slot] = float(v["x"])
	var moved := absf(float(v["x"]) - was_x) * FishingScenery.PX_PER_M
	_odo[r.slot] = float(_odo.get(r.slot, 0.0)) + (moved if moved < CAM_SNAP_M else 0.0)
	(model["boats"] as Dictionary)[r.slot] = b.position


## The trim the hull shows: the physics' pitch, with the water's state made plain: cruising in
## displacement the bow is up at least a little (CRUISE_PITCH; braking passes), climbing onto the plane
## (FishingWhitewater.HUMP) the bow stands up at least CLIMB_PITCH, on the plane
## the hull lies flat (at most PLANE_PITCH), towed stern first by a fish the bow is up at least
## TOW_PITCH.
func shown_pitch(r: FishingRiderState, pitch: float) -> float:
	if towed(r):
		return maxf(pitch, TOW_PITCH)
	match whitewater.level_of(r.slot, r.v_mps, r.plane):
		FishingWhitewater.CRUISE:
			return maxf(pitch, CRUISE_PITCH) if pitch >= 0.0 else pitch
		FishingWhitewater.HUMP:
			return maxf(pitch, CLIMB_PITCH)
		FishingWhitewater.PLANE:
			return minf(pitch, PLANE_PITCH)
	return pitch


## The heave the hull shows (whole px): never down while idle, CRUISE_LIFT_PX up cruising,
## squatting at least
## CLIMB_SQUAT_PX on the hump, up at least HEAVE_UP_PX on the plane, the stern dragged down at
## least TOW_SQUAT_PX when towed.
func shown_heave(r: FishingRiderState, px: int) -> int:
	if towed(r):
		return mini(px, -TOW_SQUAT_PX)
	match whitewater.level_of(r.slot, r.v_mps, r.plane):
		FishingWhitewater.IDLE:
			return maxi(px, 0)
		FishingWhitewater.CRUISE:
			return maxi(px, CRUISE_LIFT_PX)
		FishingWhitewater.HUMP:
			return mini(px, -CLIMB_SQUAT_PX)
		FishingWhitewater.PLANE:
			return maxi(px, HEAVE_UP_PX)
	return px


## True while a fish tows rider `r`'s boat (FishingWhitewater.TOW_AT of the most tension).
static func towed(r: FishingRiderState) -> bool:
	return r.tow_n / FishingConst.TOW_MAX_N >= FishingWhitewater.TOW_AT


## The hull's heave in whole px (up positive) for `heave_m`.
static func heave_px(heave_m: float) -> int:
	if heave_m < 0.0:
		return maxi(roundi(heave_m * HEAVE_DOWN_PX_PER_M), -HEAVE_DOWN_PX)
	return mini(roundi(heave_m * HEAVE_PX_PER_M), HEAVE_UP_PX)


## The cadence the crank turns at: the local rider's raw telemetry (FishingGame.local_tm), any
## other rider's shown cadence `shown_rpm`.
func raw_cadence(r: FishingRiderState, shown_rpm: float) -> float:
	if r.slot == _local_slot and game != null and game.local_tm != null:
		return game.local_tm.cadence_rpm
	return shown_rpm


## Rod tension 0..1: a fight's strain (all of it on a run, the rod bent at least
## FIGHT_BEND_MIN), the landing, a wobbler working.
func _tension(r: FishingRiderState) -> float:
	match r.action:
		FishingConst.A_FIGHT:
			if r.fish.off_line:
				return 0.0
			if r.fish.run_active or r.surging:
				return 1.0
			return clampf(0.35 + 0.65 * r.strain - 0.3 * r.slack, FIGHT_BEND_MIN, 1.0)
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
		var lfy := scenery.floor_y(float(v["x"]) + float(v["ldx"]))
		if not is_inf(lfy):
			p.y = minf(p.y, lfy - 3.0)
		p.y = minf(p.y, float(scenery.h) - 3.0)
		var id := "lure"
		lure.texture = FishingSprites.frame(id, floori(_t * 6.0))
		lure.flip_h = r.heading < 0
		p = p.floor()
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
	var a := Vector2(FishingSprites.anchor(id2))
	var k := _fish_frame(r, mouth, b.rod_tip() if b != null else mouth)
	var box := FishingSprites.bounds(id2, k)
	var floor_y := scenery.floor_y(float(v["x"]) + float(v["fdx"]))
	var bottom := float(scenery.h) - 2.0
	if not aboard and not is_inf(floor_y):
		bottom = minf(bottom, floorf(floor_y) - FISH_FLOOR_GAP_PX)
	if not aboard:
		mouth.y = minf(mouth.y, bottom - float(box.end.y) + a.y)
	fish.texture = FishingSprites.frame(id2, k)
	var boat_x := FishingScenery.screen_x(float(v["x"]), cam_m)
	fish.flip_h = mouth.x < boat_x if not aboard else r.heading > 0
	if not aboard:
		mouth = mouth.round()
	var top_left := mouth - a
	var left := float(box.position.x)
	if fish.flip_h:
		top_left = mouth - Vector2(float(size.x) - a.x, a.y)
		left = float(size.x - box.end.x)
	fish.position = top_left.round()
	_map_depth(_fish_mat[r.slot], depth if mouth.y > float(FishingScenery.SURF_Y) else 0.0, true)
	var drawn := Rect2(fish.position + Vector2(left, float(box.position.y)), Vector2(box.size))
	(model["fish"] as Dictionary)[r.slot] = drawn
	(model["mouth"] as Dictionary)[r.slot] = mouth
	(model["fish_frame"] as Dictionary)[r.slot] = k


## The fish frame (FishingSprites.FISH_*): tired when spent or in the Landing; a pull pose while
## the rod is under tension, as steep as the line at the mouth (toward the rod tip `tip`) and the
## tension allow; else the swim cycle, faster on a run.
func _fish_frame(r: FishingRiderState, mouth: Vector2, tip: Vector2) -> int:
	if r.action == FishingConst.A_LAND or r.fish.s < TIRED_S:
		return FishingSprites.FISH_TIRED
	var t := _tension(r)
	var d := tip - mouth
	var deg := rad_to_deg(atan2(absf(d.y), maxf(absf(d.x), 0.001)))
	var want := 0 if deg < PULL15_DEG else (1 if deg < PULL30_DEG else 2)
	var allow := 2 if t >= PULL30_AT else (1 if t >= PULL15_AT else 0)
	match mini(want, allow):
		1:
			return FishingSprites.FISH_PULL15
		2:
			return FishingSprites.FISH_PULL30
	var fps := SWIM_RUN_FPS if r.fish.run_active else SWIM_FPS
	return FishingSprites.FISH_SWIM[floori(_t * fps) % FishingSprites.FISH_SWIM.size()]


## A fish (`fish`) or wobbler at `depth_m`: dark on the light water bands, darker on the teals
## (a fish's belly stays darker than the back ridge and floor of its band: fish_shift()).
func _map_depth(m: ShaderMaterial, depth_m: float, fish: bool = false) -> void:
	FishingPaletteMap.set_flat(m, false)
	var band := FishingScenery.band_at(depth_m)
	var steps := FishingPaletteMap.fish_shift(band) if fish else FishingPaletteMap.shift_for(band)
	FishingPaletteMap.set_shift(m, steps)


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
		var box := FishingSprites.bounds(id, 0)
		var sz := Vector2(box.size)
		var fy := scenery.floor_y(x)
		if not is_inf(fy):
			depth = minf(depth, scenery.depth_of_y(fy - sz.y * 0.5 - FISH_FLOOR_GAP_PX))
		depth = maxf(depth, 0.5)
		var band := FishingScenery.band_at(depth)
		var p := hint_inside_band(to_screen(x, depth), sz, scenery.band_rows(band))
		var cycle := FishingSprites.FISH_SWIM
		s.texture = FishingSprites.frame(id, cycle[(floori(_t * 3.0) + i) % cycle.size()])
		s.position = (p - sz * 0.5 - Vector2(box.position)).round()
		var lit := r.selected >= 0 and r.selected < r.menu.size() and r.menu[r.selected] == i
		_map_depth(_hint_mats[i], depth, true)
		if not lit:
			FishingPaletteMap.set_flat(_hint_mats[i], true, silhouette(depth))
		out.append({"pos": p, "sp": sp, "selected": lit, "index": i})
	model["hints"] = out


## Where the line ends in view px: the fish's mouth or the wobbler (Vector2.INF: no line out).
func _line_end(r: FishingRiderState) -> Vector2:
	var mp: Variant = (model.get("mouth", {}) as Dictionary).get(r.slot)
	if mp is Vector2 and (_fish[r.slot] as Sprite2D).visible:
		var flip := (_fish[r.slot] as Sprite2D).flip_h
		return (mp as Vector2) - Vector2(1.0 if flip else 0.0, 0.0)
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
	var spans: Array[Vector2] = []
	for slot: int in boats:
		var b: FishingBoatView = boats[slot]
		if b.visible:
			var a := b.pixel_of(Vector2i(0, 0)).x
			var z := b.pixel_of(Vector2i(FishingRig.HULL_SIZE.x, 0)).x
			spans.append(Vector2(minf(a, z), maxf(a, z)))
	scenery.clear_x = spans
	scenery.paint_back(c, cam_m, _t)


## Behind every hull: each boat's far V arm and prop wash, and a farther boat's whole water (a
## step paler: FishingWhitewater).
func _paint_wash(c: CanvasItem) -> void:
	for slot: int in boats:
		var b: FishingBoatView = boats[slot]
		var w := water_state(slot)
		if not b.visible or w.is_empty():
			continue
		whitewater.paint_behind(c, b, w)
		if b.far:
			whitewater.paint_front(c, b, w)


## What FishingWhitewater draws for `slot`'s boat ({} without a rider): its odometer, the time,
## speed, planing level, line tow (0..1) and braking.
func water_state(slot: int) -> Dictionary:
	var r := game.state.rider(slot)
	var b: FishingBoatView = boats.get(slot)
	if r == null or b == null:
		return {}
	return {
		"slot": slot,
		"odo": float(_odo.get(slot, 0.0)),
		"t": _t,
		"v": r.v_mps,
		"plane": r.plane,
		"tow": clampf(r.tow_n / FishingConst.TOW_MAX_N, 0.0, 1.0),
		"brake": b.braking(),
		"p": r.p_eff_w / FishingConst.P_EFF_REF_W,
	}


## Steps rider `r`'s rope toward this frame's rod end and line end (none without a line out).
func _step_rope(r: FishingRiderState, delta: float) -> void:
	var b: FishingBoatView = boats.get(r.slot)
	var end := _line_end(r)
	if b == null or end == Vector2.INF:
		_ropes.erase(r.slot)
		return
	var start := Vector2i(b.rod_tip())
	var rope: FishingRope = _ropes.get(r.slot)
	if rope == null:
		rope = FishingRope.new()
		_ropes[r.slot] = rope
	var fight := r.action == FishingConst.A_FIGHT or r.action == FishingConst.A_LAND
	var slack := r.slack if fight else WAIT_SLACK
	var strain := maxf(r.strain, FIGHT_STRAIN_MIN) if fight else WAIT_STRAIN
	if fight and r.fish.run_active:
		strain = 1.0
	var flow := -float(r.heading) * absf(r.v_mps) * FLOW_PER_MPS
	var surf := float(FishingScenery.SURF_Y)
	rope.step(Vector2(start), end, slack, strain, delta, surf, flow, fight)


## Rider `slot`'s rope (null without a line out).
func rope_of(slot: int) -> FishingRope:
	return _ropes.get(slot)


func _paint_lines(c: CanvasItem) -> void:
	_paint_line_parts(c, false)


## Each rope's pixels (only `only`'s when set) above the water (`under` false: drawn behind the
## hulls) or under it (`under` true: drawn in front, so a hull's shadow slab never breaks it).
func _paint_line_parts(c: CanvasItem, under: bool, only: int = -1) -> void:
	for slot: int in _ropes:
		if only >= 0 and slot != only:
			continue
		var b: FishingBoatView = boats.get(slot)
		var rope: FishingRope = _ropes[slot]
		if b == null or rope.points.is_empty():
			continue
		var first := rope.points[0]
		var last := rope.points[rope.points.size() - 1]
		if not b.visible and (last.x < 0.0 or last.x > float(scenery.w)):
			continue
		var path: Array[Vector2i] = []
		var tip := Vector2i(b.rod_tip())
		if Vector2i(first.round()) != tip:
			path = FishingRig.bresenham(tip, Vector2i(first.round()))
			path.pop_back()
		path.append_array(rope.pixels())
		_draw_line(c, path, b, under)


## The line's pixels on one side of the surface: the rod's slate (or the line cosmetic) above
## the water, the deep teal (line_under()) under it.
func _draw_line(c: CanvasItem, path: Array[Vector2i], b: FishingBoatView, under: bool) -> void:
	var surf := FishingScenery.SURF_Y
	var above := b.line_above()
	for p in path:
		if (p.y >= surf) == under:
			c.draw_rect(Rect2(Vector2(p), Vector2.ONE), line_under() if under else above)


## The line's colour under the water: the deep teal, in every band.
static func line_under() -> Color:
	return FishingPalette.DEEP


## A hint's centre `p` moved up or down so its `size` box stays HINT_BAND_GAP_PX inside the
## band rows `rows` (Vector2(top, bottom)), so the silhouette never touches the next band (which
## has its colour); unchanged when the band is too thin for it.
static func hint_inside_band(p: Vector2, size: Vector2, rows: Vector2) -> Vector2:
	var lo := rows.x + float(HINT_BAND_GAP_PX) + size.y * 0.5
	var hi := rows.y - float(HINT_BAND_GAP_PX) - size.y * 0.5
	if hi < lo:
		return p
	return Vector2(p.x, clampf(p.y, lo, hi))


## A hint's silhouette at `depth_m`: one step darker than the water.
static func silhouette(depth_m: float) -> Color:
	return FishingPalette.darker(FishingScenery.water_at(depth_m), 1)


func _paint_front(c: CanvasItem) -> void:
	_paint_line_parts(c, true)
	for slot: int in boats:
		var b: FishingBoatView = boats[slot]
		if b.visible and b.far:
			_paint_far_waterline(c, b)
		var w := water_state(slot)
		if b.visible and not b.far and not w.is_empty():
			whitewater.paint_front(c, b, w)
			# towed, the line leaves the bent rod over the foam piled at the transom
			var r := game.state.rider(slot)
			if r != null and towed(r):
				_paint_line_parts(c, false, slot)


## A farther boat's own surface: a FAR_WATERLINE_ROWS foam slab on its waterline, a little
## wider than the hull, so it sits in the far water instead of hovering over the near surface.
func _paint_far_waterline(c: CanvasItem, b: FishingBoatView) -> void:
	var a := b.pixel_of(Vector2i(FishingRig.STERN_X - FAR_WATERLINE_OVER, FishingRig.WATERLINE))
	var z := b.pixel_of(Vector2i(FishingRig.BOW_X + FAR_WATERLINE_OVER, FishingRig.WATERLINE))
	var x0 := minf(a.x, z.x)
	var w := absf(z.x - a.x) + 1.0
	c.draw_rect(Rect2(x0, b.position.y, w, FAR_WATERLINE_ROWS), FishingPalette.FOAM)
