extends SceneTree
## Renders the real WorkoutRideView (and the real HUD Controls of WorkoutHud.spec) in every scenario
## the art is judged on, one PNG each, with no platform session: synthetic snapshots at 10 Hz through
## game.apply_snapshot and view.advance at 60 Hz, so cranks, crowd and spots are real. It also proves
## the time-of-day LUT in a real render: a known sky pixel must come out as the LUT row says (exit 1
## otherwise), and a star must fade by the LUT's alpha. Needs a renderer, so run it windowed:
##
##   tools/godot.sh --timeout=300 --path . -s src/games/workout/tools/render_frames.gd -- --out=build/workout_frames
##
## User arguments: --out=<dir> (default build/workout_frames), --only=<id,id>.

const BASE := Vector2i(WorkoutArt.W, WorkoutArt.H)
const FRAME := 1.0 / 60.0
const FRAMES_PER_SNAPSHOT := 6
const SETTLE_S := 3.0
const SCALE := 2
const FTP := 200.0
const SKY := "res://assets/workout/world/sky.png"
const STARS := "res://assets/workout/world/stars.png"
const LUT := "res://assets/workout/world/tod_lut.png"
const STAGE_TOP := 180
## Over this the render disagrees with the LUT (two for a star, blended over the sky).
const TOLERANCE := 1.0 / 255.0 + 1e-4
const BLEND_TOLERANCE := 2.0 / 255.0 + 1e-4
const STRIP_FRAMES: Array[int] = [0, 4, 8, 12, 16, 20]
const STRIP_CROP := Vector2i(96, 96)
const STRIP_SCALE := 4
const IN_BAND := WorkoutSnapshot.F_IN_BAND
## What the HUD is shown per scenario, so each frame is a state a rider can really be in: `wbal` the
## share of W' left, `off` the local rider's watts against the plan (under, in band, over).
const HUD_STATE := {
	"dawn_solo": {"wbal": 1.0, "off": 1.0},
	"sunrise_4": {"wbal": 0.96, "off": 1.0},
	"golden_8": {"wbal": 0.64, "off": 0.8},
	"day_8_gaps": {"wbal": 0.17, "off": 1.14},
	"climb_4": {"wbal": 0.72, "off": 1.0},
	"descent_4": {"wbal": 0.9, "off": 1.0},
	"sprint_4": {"wbal": 0.38, "off": 1.0},
	"states_8": {"wbal": 0.7, "off": 1.0},
	"cooldown": {"wbal": 0.85, "off": 1.0},
	"flex_853x480": {"wbal": 0.64, "off": 1.0},
	"flex_1280x720": {"wbal": 0.64, "off": 1.0},
	"crank_strip": {"wbal": 1.0, "off": 1.0},
}
## In the course's band, from the middle of it.
const COURSE_SHARE := 0.92
const SPEED_MPS := 9.0

const SCENARIOS: Array[Dictionary] = [
	{"id": "dawn_solo", "content": "easy_30", "t": 20.0, "riders": 1},
	{"id": "sunrise_4", "content": "sweet_spot", "t": 330.0, "riders": 4},
	{"id": "golden_8", "content": "threshold", "t": 900.0, "riders": 8},
	{"id": "day_8_gaps", "content": "vo2", "t": 1800.0, "riders": 8},
	{"id": "climb_4", "content": "rolling_road", "t": 600.0, "riders": 4, "scan": 1.0},
	{"id": "descent_4", "content": "rolling_road", "t": 900.0, "riders": 4, "scan": -1.0},
	{"id": "sprint_4", "content": "easy_30", "t": 672.0, "riders": 4, "settle": 4.5},
	{"id": "states_8", "content": "sweet_spot", "t": 900.0, "riders": 8},
	{"id": "cooldown", "content": "easy_30", "t": 1600.0, "riders": 2},
	{
		"id": "flex_853x480",
		"content": "threshold",
		"t": 900.0,
		"riders": 8,
		"canvas": Vector2i(853, 480)
	},
	{
		"id": "flex_1280x720",
		"content": "threshold",
		"t": 900.0,
		"riders": 8,
		"canvas": Vector2i(1280, 720)
	},
	{"id": "crank_strip", "content": "easy_30", "t": 400.0, "riders": 1},
]

var _out: String = "build/workout_frames"
var _only: PackedStringArray = PackedStringArray()
var _failed: bool = false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--only="):
			_only = arg.substr(7).split(",", false)
	DirAccess.make_dir_recursive_absolute(_abs(_out))
	_run.call_deferred()


func _run() -> void:
	for sc: Dictionary in SCENARIOS:
		if _only.is_empty() or _only.has(str(sc["id"])):
			await _scene(sc)
	if _failed:
		printerr("render_frames: failed")
	else:
		print("render_frames: ok, %s" % _abs(_out))
	quit(1 if _failed else 0)


func _abs(path: String) -> String:
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join(path)


# --- one scenario ---------------------------------------------------------------------


func _scene(sc: Dictionary) -> void:
	var canvas: Vector2i = sc.get("canvas", BASE)
	var game := _game(sc)
	var art := _viewport(canvas, false)
	var view := game.make_view() as WorkoutRideView
	view.canvas_override = Vector2(canvas)
	view.set_process(false)
	art.add_child(view)
	var hud := _viewport(canvas * SCALE, true)
	var ride := _ride(sc, game)
	var settle := float(sc.get("settle", SETTLE_S))
	var t := float(sc["t"]) - settle
	while t < float(sc["t"]):
		game.apply_snapshot(_snapshot(game, ride, t))
		for i in FRAMES_PER_SNAPSHOT:
			view.advance(FRAME)
		t += FRAME * float(FRAMES_PER_SNAPSHOT)
	_add_hud(game, hud, canvas, ride, sc)
	if str(sc["id"]) == "crank_strip":
		await _crank_strip(game, view, art, sc)
	else:
		await _capture(sc, game, art, hud)
	art.queue_free()
	hud.queue_free()
	game.free()
	await process_frame


func _capture(sc: Dictionary, game: WorkoutGame, art: SubViewport, hud: SubViewport) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := art.get_texture().get_image()
	var overlay := hud.get_texture().get_image()
	if img == null or overlay == null:
		_fail("%s: no image (run without --headless)" % sc["id"])
		return
	_check_lut(str(sc["id"]), img, game)
	img.convert(Image.FORMAT_RGBA8)
	overlay.convert(Image.FORMAT_RGBA8)
	img.resize(img.get_width() * SCALE, img.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
	img.blend_rect(overlay, Rect2i(Vector2i.ZERO, overlay.get_size()), Vector2i.ZERO)
	_save(img, "%s.png" % sc["id"])


## Six crops around the rider at 4x, proving the rig in the real view: frames 0, 4, 8, 12, 16, 20.
func _crank_strip(
	game: WorkoutGame, view: WorkoutRideView, art: SubViewport, sc: Dictionary
) -> void:
	var size := STRIP_CROP * STRIP_SCALE
	var sheet := Image.create_empty(size.x * STRIP_FRAMES.size(), size.y, false, Image.FORMAT_RGBA8)
	var at := Vector2i(int(WorkoutRideView.RIDER_X) - 48, int(WorkoutRideView.ROAD_Y) - 88)
	var n := 0
	for k in STRIP_FRAMES:
		game.cranks.clear()
		game.cranks.step(1, 60.0, (float(k) + 0.5) / float(WorkoutRig.CRANK_FRAMES))
		view.refresh()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := art.get_texture().get_image()
		if img == null:
			_fail("%s: no image (run without --headless)" % sc["id"])
			return
		img.convert(Image.FORMAT_RGBA8)
		var crop := img.get_region(Rect2i(at, STRIP_CROP))
		crop.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(crop, Rect2i(Vector2i.ZERO, size), Vector2i(n * size.x, 0))
		n += 1
	_save(sheet, "%s.png" % sc["id"])


func _viewport(size: Vector2i, transparent: bool) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = transparent
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(vp)
	return vp


## The game's own HUD Controls, each at its anchored rect, as a real HudLayer places them.
func _add_hud(
	game: WorkoutGame, hud: SubViewport, canvas: Vector2i, ride: Array, sc: Dictionary
) -> void:
	var spec := WorkoutHud.spec(game)
	var tm := _telemetry(game, ride[0], sc)
	for c: Dictionary in spec.controls:
		var control := c["control"] as Control
		var at: Variant = c["at"]
		if control == null or not at is Rect2i:
			continue
		var rect := PixelViewport.anchor_rect(at, BASE, canvas)
		hud.add_child(control)
		control.position = Vector2(rect.position * SCALE)
		control.size = Vector2(rect.size * SCALE)
		if control.has_method("set_telemetry"):
			control.call("set_telemetry", tm)


## The local rider's telemetry at the frame's t, as the trainer would report it: the plan's target and
## mode, the course's grade under the wheels, W' and the watts the scenario says.
func _telemetry(game: WorkoutGame, rider: Dictionary, sc: Dictionary) -> Telemetry:
	var state := game.state
	var index := _phase_at(state, float(sc["t"]))
	var p := state.phase(index)
	var t := Telemetry.new()
	t.peer_id = int(rider["peer"])
	t.power_w = float(rider["w"])
	t.cadence_rpm = float(rider["rpm"])
	t.speed_kmh = float(rider["v"]) * 3.6
	t.ftp_pct = t.power_w / FTP * 100.0
	t.mode = p.mode
	t.coasting = t.cadence_rpm <= 0.0
	t.wbal_j = HudRiderNumbers.wprime_j() * float(_hud_state(sc)["wbal"])
	t.connected = true
	if p.mode == Wl.ERG:
		t.applied_target_w = roundi(_plan_w(state, index, float(sc["t"])))
	if state.is_course_phase(index):
		t.applied_grade_pct = state.course.grade_at(float(rider["cd"]))
	return t


func _hud_state(sc: Dictionary) -> Dictionary:
	return HUD_STATE[str(sc["id"])]


## The plan's watts at time `t` (0 in a phase with no ERG target).
func _plan_w(state: WorkoutState, index: int, t: float) -> float:
	var p := state.phase(index)
	if p == null or p.mode != Wl.ERG:
		return 0.0
	var pct := p.target_pct
	if p.has_ramp() and p.duration_s > 0.0:
		var f := clampf((t - state.phase_start_s(index)) / p.duration_s, 0.0, 1.0)
		pct = lerpf(p.target_pct, p.ramp_to_pct, f)
	return pct / 100.0 * FTP


func _game(sc: Dictionary) -> WorkoutGame:
	var n := int(sc["riders"])
	var players: Array[PlayerSlot] = []
	for i in n:
		var bot := str(sc["id"]) == "states_8" and i == 6
		var s := Bots.make_slot(1, i, FTP) if bot else PlayerSlot.new()
		if not bot:
			s.peer_id = i + 1
			s.name = "Rider %d" % (i + 1)
			s.apply_look(i)
			s.ftp = FTP
			s.ftp_verified = true
			s.p_eff_per_w = 250.0 / FTP
		players.append(s)
	var ctx := GameContext.new()
	ctx.game_id = "workout"
	ctx.content_id = str(sc["content"])
	ctx.players = players
	ctx.role = Wl.CLIENT
	ctx.local_peer = 1
	ctx.seed = 7
	ctx.rng = SeededRng.make(7)
	ctx.strings = GameStrings.new()
	ctx.progress = ProgressStore.open("workout", "")
	ctx.game_dir = "res://src/games/workout"
	ctx.content_dir = "res://content/workout"
	ctx.assets_dir = "res://assets/workout"
	var game := WorkoutGame.new()
	game.configure(ctx)
	return game


# --- the scenario table -----------------------------------------------------------------


## One entry per rider, in state order: {peer, gap (m ahead of the local rider), rpm, w, v, flags,
## cd (course distance at the frame's t, for the local rider's stretch)}. Everybody rides the plan a
## little differently, and the in-band flag says what the watts say.
func _ride(sc: Dictionary, game: WorkoutGame) -> Array:
	var out: Array = []
	var id := str(sc["id"])
	var cd := _scan_course(game, float(sc.get("scan", 0.0)))
	var state := game.state
	var index := _phase_at(state, float(sc["t"]))
	var planned := _plan_w(state, index, float(sc["t"]))
	if planned <= 0.0:
		planned = COURSE_SHARE * FTP
	for i in state.order.size():
		var e := {
			"peer": state.order[i],
			"gap": float(i) * 6.0 - 12.0 if i > 0 else 0.0,
			"rpm": 78.0 + float((i * 7) % 24),
			"w": planned * (1.0 + float((i * 37) % 9 - 4) * 0.008 if i > 0 else 1.0),
			"v": SPEED_MPS,
			"flags": 0,
			"cd": cd,
			"tib": 985 - i * 22,
			"block": 960 - i * 15,
			"end_t": float(sc["t"]),
		}
		_tune(id, i, e, planned)
		var off := float(_hud_state(sc)["off"])
		if i == 0 and off != 1.0:
			e["w"] = float(e["w"]) * off
			e["tib"] = 780
			e["block"] = 640
		if state.riders.has(e["peer"]):
			_flag_band(e, state, index, planned)
		out.append(e)
	return out


func _tune(id: String, i: int, e: Dictionary, planned: float) -> void:
	match id:
		"dawn_solo":
			e["rpm"] = 90.0
			e["v"] = 7.0
		"sunrise_4":
			e["rpm"] = 80.0 + float(i) * 20.0 / 3.0
			if i == 2:
				e["w"] = planned * 1.16
		"golden_8", "flex_853x480", "flex_1280x720":
			e["rpm"] = 70.0 + float(i) * 5.0
			if i == 5:
				e["w"] = planned * 0.82
		"day_8_gaps":
			var gaps: Array[float] = [0.0, 10.0, -20.0, 40.0, 80.0, 150.0, -700.0, 1400.0]
			e["gap"] = gaps[i]
			e["v"] = 11.0 if i % 2 == 0 else 9.0
			e["rpm"] = 82.0 + float(i) * 3.0
		"climb_4":
			e["w"] = 200.0 - float(i) * 8.0
			e["rpm"] = 62.0 + float(i) * 6.0
			e["v"] = 5.0
		"descent_4":
			e["rpm"] = 0.0 if i < 2 else 90.0 + float(i) * 3.0
			e["w"] = 0.0 if i < 2 else 120.0
			e["v"] = 16.0
		"sprint_4":
			e["w"] = 340.0 - float(i) * 12.0
			e["rpm"] = 105.0 + float(i) * 2.0
			e["v"] = 14.0
		"states_8":
			_tune_state(i, e)


## A rider's in-band flag from its watts: the plan's tolerance, or the published band of a SIM phase
## (none: nothing to be out of). A state's own flags stay.
func _flag_band(e: Dictionary, state: WorkoutState, index: int, planned: float) -> void:
	if int(e["flags"]) != 0:
		return
	var w := float(e["w"])
	var lo := planned * (1.0 - WorkoutRules.ERG_TOLERANCE)
	var hi := planned * (1.0 + WorkoutRules.ERG_TOLERANCE)
	if state.phase(index).mode != Wl.ERG:
		var band := WorkoutHud.band_for(state, index, state.rider(int(e["peer"])))
		lo = float(band[0]) if not band.is_empty() else -INF
		hi = float(band[1]) if not band.is_empty() else INF
	if w >= lo and w <= hi:
		e["flags"] = IN_BAND


## rescue, AFK moving, AFK stopped, disconnected, (bot and in band ride on).
func _tune_state(i: int, e: Dictionary) -> void:
	match i:
		1:
			e["flags"] = WorkoutSnapshot.F_RESCUE
			e["rpm"] = 40.0
		2:
			e["flags"] = WorkoutSnapshot.F_AFK
			e["rpm"] = 0.0
			e["w"] = 0.0
		3:
			e["flags"] = WorkoutSnapshot.F_AFK
			e["rpm"] = 0.0
			e["w"] = 0.0
			e["v"] = 0.0
		4:
			e["flags"] = WorkoutSnapshot.F_DISCONNECTED | WorkoutSnapshot.F_AFK
			e["rpm"] = 0.0
			e["w"] = 0.0
			e["v"] = 0.0


## The course distance of the steepest (`sign` 1) or the most downhill (`sign` -1) stretch, 0 with no
## scan or course.
func _scan_course(game: WorkoutGame, sign_of: float) -> float:
	var course := game.state.course
	if sign_of == 0.0 or course == null:
		return 0.0
	var best := -INF
	var at := 0.0
	var d := 400.0
	while d < course.window_m:
		var g := course.grade_at(d) * sign_of
		if g > best:
			best = g
			at = d
		d += 25.0
	return at


func _snapshot(game: WorkoutGame, ride: Array, t: float) -> Dictionary:
	var rows: Array = []
	var d0 := 4000.0 + t * float(ride[0]["v"])
	for e: Dictionary in ride:
		var d := d0 + float(e["gap"])
		var cd := float(e["cd"]) - (float(ride[0]["end_t"]) - t) * float(ride[0]["v"])
		(
			rows
			. append(
				[
					int(e["peer"]),
					roundi(d * 10.0),
					roundi(maxf(cd + float(e["gap"]), 0.0) * 10.0),
					roundi(float(e["v"]) * 100.0),
					int(e["flags"]),
					int(e["tib"]),
					roundi(float(e["w"])),
					roundi(float(e["rpm"])),
					int(e["block"]),
				]
			)
		)
	return {
		"t": roundi(t / Wl.SIM_DT),
		"p": _phase_at(game.state, t),
		"pt": roundi(t * 10.0),
		"r": rows,
	}


func _phase_at(state: WorkoutState, t: float) -> int:
	var at := 0.0
	for i in state.phases.size():
		at += state.phases[i].duration_s
		if t < at:
			return i
	return state.phases.size() - 1


# --- the LUT in a real render -------------------------------------------------------------


func _check_lut(id: String, img: Image, game: WorkoutGame) -> void:
	if img.get_size().y != BASE.y:
		return
	var sky := _png(SKY)
	var stars := _png(STARS)
	var lut := _png(LUT)
	if sky == null or stars == null or lut == null:
		_fail("cannot decode the sky, the stars or the LUT")
		return
	var row := WorkoutTod.row(WorkoutTod.progress(game.state))
	var plain := _find(stars, 0, 19, false)
	if plain.x >= 0:
		var want := lut.get_pixel(
			sky.get_pixel(plain.x % sky.get_width(), plain.y + STAGE_TOP).r8 / 2, row
		)
		_compare(id, "sky", want, img.get_pixel(plain.x, plain.y), TOLERANCE)
	var star := _find(stars, 0, 19, true)
	if star.x < 0:
		return
	var under := lut.get_pixel(
		sky.get_pixel(star.x % sky.get_width(), star.y + STAGE_TOP).r8 / 2, row
	)
	var over := lut.get_pixel(stars.get_pixel(star.x, star.y + STAGE_TOP).r8 / 2, row)
	var blended := under.lerp(over, over.a)
	_compare(id, "star", blended, img.get_pixel(star.x, star.y), BLEND_TOLERANCE)


## A screen pixel at the top of the stage, over which nothing but the sky and the stars draws.
func _find(stars: Image, y0: int, y1: int, opaque: bool) -> Vector2i:
	for y in range(y0, y1 + 1):
		for x in range(0, stars.get_width()):
			if (stars.get_pixel(x, y + STAGE_TOP).a > 0.5) == opaque:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _compare(id: String, what: String, want: Color, got: Color, tolerance: float) -> void:
	var off := maxf(maxf(absf(want.r - got.r), absf(want.g - got.g)), absf(want.b - got.b))
	if off > tolerance:
		_fail("%s: the %s pixel is %s, the LUT says %s" % [id, what, got, want])


func _png(path: String) -> Image:
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return img


func _save(img: Image, file: String) -> void:
	var path := _abs(_out).path_join(file)
	var err := img.save_png(path)
	print("render_frames: wrote %s (error %d)" % [path, err])
	if err != OK:
		_failed = true


func _fail(why: String) -> void:
	printerr("render_frames: %s" % why)
	_failed = true
