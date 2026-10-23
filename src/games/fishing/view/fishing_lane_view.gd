class_name FishingLaneView
extends Node2D
## One rider's lane (brief 3.5), in lane-local art pixels (origin at the lane's top-left), drawn
## back to front:
##  1. sky bands (ordered dither; the day cycle's three variants with a 2 s dithered wipe), the
##     sun, far islands and clouds (ParallaxStrip, mirror_alternate), the palm islet and the
##     gulls over Bird Pile hints (4 Hz); a dithered sky cover keeps the HUD zone pure gradient;
##  2. water bands, light rays (SpriteWobble) and the surface strip;
##  3. reef_back;
##  4. hints at hint_x(d): bait balls, sonar marks (1-4 by strength), current seams, the selected
##     one bracketed (the pedal-scan highlight from the state);
##  5. the fish (FishingLayout.fish_mouth_x / fish_y, tail wobble, jumps as 2-3 leaps);
##  6. reef_front and sand with a flat code-drawn cap at the right end;
##  7. the boat and rig (FishingBoatView), the line from the rod tip, the lure;
##  8. effects (FishingEffects), then the border (local: 3 px in the slot's colour and pattern
##     with a "YOU" tag; others 1 px navy).
## FishingView sets `lane` and the shown values (interpolated for other lanes on clients) and
## calls advance(dt); the lane only reads.

const GULL_HZ := 4.0
const LEAP_S := 1.1
const LEAP_GAP_S := 0.35
const LEAP_PX := 14.0
const RIDE_PX_PER_SQRT_W := 1.6
const RIDE_MAX_PX_S := 40.0
const MOVING_PX_S := 2.0
const LANDING_ABOARD_S := 15.0
const LANDING_GONE_S := 25.0
const SNAP_ANIM_S := 0.8
const FRENZY_ANIM_S := 6.0
const STRIKE_Z := 0.3
const REEF_EDGE_Z := 0.3
const DROP_OFF_Z := 0.75
const SEAM_PX_PER_STEP := 12
const REEF_W := 416
const CAP_W := 8
const SAND_H := 8
const RAY_XS: Array[int] = [112, 252]
## The "YOU" tag's 3 x 5 glyphs (rows top to bottom, bit 2 = left column).
const GLYPHS := {
	"Y": [5, 5, 2, 2, 2],
	"O": [7, 5, 5, 5, 7],
	"U": [5, 5, 5, 5, 7],
}

var slot: int = 0
var n: int = 1
var local: bool = false
var look: Dictionary = {}
var content: FishingContent = null
var cosmetic_values: Dictionary = {}
var lane: FishingLaneState = null
## Shown values (FishingView: the state's, or interpolated between snapshots).
var shown_d: float = 0.0
var shown_z: float = 0.0
var shown_cad: float = 0.0
var shown_w: float = 0.0
var game_t: float = 0.0
var total_s: float = 0.0
## Art px travelled (ride out right, home left) and the reel's line speed (m/s, + retrieving).
var world_x: float = 0.0
var line_mps: float = 0.0
var rng: FishingRandom = null
## Geometry (lane-local).
var lane_h: int = 0
var sky_h: int = 0
var water_y: int = 0
var water_h: int = 0
## What the last advance() drew (tests and screenshots read it).
var model: Dictionary = {}

var sky_a: Sprite2D = null
var sky_b: Sprite2D = null
var sun: Sprite2D = null
var islands_far: ParallaxStrip = null
var clouds: ParallaxStrip = null
var palm: Sprite2D = null
var sky_cover: Sprite2D = null
var water: Sprite2D = null
var rays: Array[Sprite2D] = []
var surface: ParallaxStrip = null
var reef_back: Sprite2D = null
var fish: Sprite2D = null
var reef_front: Sprite2D = null
var boat: FishingBoatView = null
var effects: FishingEffects = null

var _wipe_mat: ShaderMaterial = null
var _fish_mat: ShaderMaterial = null
var _ray_mats: Array[ShaderMaterial] = []
var _layers: Array[FishingDrawLayer] = []
var _anim_t: float = 0.0
var _speed: float = 0.0
var _fish_sp: int = -2
var _fish_size: Vector2i = Vector2i.ZERO
var _prev_d: float = -1.0
var _jump_t: float = -1.0
var _jump_leaps: int = 0
var _leap_seen: int = -1
var _snap_t: float = -1.0
var _frenzy_t: float = -1.0
var _palm_x0: float = 0.0
var _boat_base: Vector2 = Vector2.ZERO


## Builds the lane for slot `p_slot` of `p_n`. `p_look` is the slot's {color, shape, pattern}.
func configure_lane(
	p_slot: int, p_n: int, p_local: bool, p_look: Dictionary, p_content: FishingContent, p_seed: int
) -> void:
	slot = p_slot
	n = clampi(p_n, 1, 4)
	local = p_local
	look = p_look
	content = p_content
	name = "Lane%d" % slot
	rng = FishingRandom.derive(p_seed, slot, FishingRandom.STREAM_VIEW)
	lane_h = FishingLayout.lane_h(n)
	var rows := FishingLayout.rows(lane_h)
	sky_h = int(rows["sky"])
	water_y = sky_h + FishingConst.SURFACE_H
	water_h = int(rows["water"])
	position = Vector2(0, FishingLayout.lane_y(slot, n))
	_palm_x0 = rng.range_f(120.0, 300.0)
	world_x = rng.range_f(0.0, 600.0)
	_build()
	set_cosmetics([0, 0, 0, 0])


## Equips cosmetics by index [line, canopy, trim, pennant] (cosmetics.json order per kind).
func set_cosmetics(idx: Array[int]) -> void:
	cosmetic_values = cosmetic_values_of(content, idx)
	boat.set_look(slot, look, cosmetic_values)


## {"line", "canopy", "trim", "pennant"} values of the equipped indexes (index 0, or one past
## the kind's items, is the default look: "").
static func cosmetic_values_of(p_content: FishingContent, idx: Array[int]) -> Dictionary:
	var out := {"line": "", "canopy": "", "trim": "", "pennant": ""}
	var items: Array = []
	if p_content != null and p_content.cosmetics.get("items") is Array:
		items = p_content.cosmetics["items"]
	for k in FishingContent.COSMETIC_KINDS.size():
		var kind: String = FishingContent.COSMETIC_KINDS[k]
		var want := idx[k] if k < idx.size() else 0
		var seen := 0
		for it: Variant in items:
			if it is Dictionary and str(it.get("kind", "")) == kind:
				seen += 1
				if seen == want:
					out[kind] = str(it.get("value", ""))
	return out


## 1-4 strength steps of a hint (1-4 gulls, 1-4 marks, a longer seam).
static func strength_steps(strength: float) -> int:
	return clampi(ceili(strength * float(FishingConst.STRENGTH_STEPS) - 0.001), 1, 4)


## The sprite id of species index `sp`.
static func fish_sprite_id(p_content: FishingContent, sp: int) -> String:
	if sp < 0 or sp >= FishingConst.SPECIES.size():
		return ""
	var id: String = FishingConst.SPECIES[sp]
	if p_content != null and p_content.species.has(id):
		var def: FishingSpeciesDef = p_content.species[id]
		if def.sprite != "":
			return def.sprite
	return "fish_" + id


## Reacts to one presentation cue for this lane (FishingCues).
func on_cue(cue: Dictionary) -> void:
	var fr := fish_rect()
	var mouth := Vector2(fr.position.x, fr.position.y + fr.size.y * 0.5)
	match str(cue.get("k", "")):
		FishingCues.CUE_CAST:
			var x := float(FishingLayout.hint_x(float(cue.get("d", 0.0))))
			effects.spawn("splash", Vector2(x, sky_h - 2))
		FishingCues.CUE_HOOKUP, FishingCues.CUE_THROWN, FishingCues.CUE_MISS:
			var at := mouth if fr.size.x > 0.0 else Vector2(line_end().x, sky_h - 2)
			effects.spawn("splash", Vector2(at.x, sky_h - 2))
		FishingCues.CUE_RUN:
			effects.spawn("spray", Vector2(fr.get_center().x, sky_h - 8))
		FishingCues.CUE_JUMP:
			_jump_t = 0.0
			_jump_leaps = clampi(int(cue.get("leaps", 3)), 2, 3)
			_leap_seen = -1
			effects.spawn("spray", Vector2(fr.get_center().x, sky_h - 8))
		FishingCues.CUE_SNAP:
			_snap_t = 0.0
			effects.spawn("splash", Vector2(mouth.x, sky_h - 2))
		FishingCues.CUE_LANDED:
			var at := boat.position + Vector2(FishingRig.ROD_TIP.x - 8.0, 10.0)
			effects.spawn("catch_flash", at)
			if int(cue.get("grade", 0)) == FishingConst.GRADE_TROPHY:
				effects.spawn("trophy_badge", at + Vector2(0, -10))
		FishingCues.CUE_FRENZY:
			_frenzy_t = 0.0


## One frame of `dt` seconds (view clock): moves the backdrops, the boat, the fish and the effects.
func advance(dt: float) -> void:
	_anim_t += dt
	var st := lane.state if lane != null else FishingConst.ST_IDLE
	_ride(dt, st)
	_sky()
	_line_speed(dt, st)
	boat.tension = rod_tension()
	var end := line_end()
	var tip := boat.position + FishingRig.ROD_TIP
	boat.pull_dir = (end - tip).normalized() if end.distance_to(tip) > 1.0 else Vector2.DOWN
	boat.advance(dt, shown_cad, line_mps)
	_fish(dt, st)
	if _snap_t >= 0.0:
		_snap_t = _snap_t + dt if _snap_t + dt < SNAP_ANIM_S else -1.0
	if _frenzy_t >= 0.0:
		_frenzy_t = _frenzy_t + dt if _frenzy_t + dt < FRENZY_ANIM_S else -1.0
	effects.tick(dt)
	for m in _ray_mats:
		SpriteWobble.set_time(m, _anim_t)
	for layer in _layers:
		layer.queue_redraw()
	model["state"] = st
	model["moving"] = _speed > MOVING_PX_S
	model["fish_visible"] = fish.visible
	model["fish_rect"] = fish_rect()
	model["line_end"] = end
	model["rod_tip"] = boat.position + boat.rod_points()[-1]
	model["tension"] = boat.tension
	model["jumping"] = _jump_t >= 0.0
	model["flipped"] = boat.flipped


## Rod tension 0..1: a fight's strain (all of it on a run), the gaff sprint, a light retrieve.
func rod_tension() -> float:
	if lane == null:
		return 0.0
	match lane.state:
		FishingConst.ST_FIGHT:
			if lane.fish.off_line:
				return 0.0
			if lane.fish.run_active:
				return 1.0
			return clampf(0.4 + 0.6 * lane.strain - 0.3 * lane.slack, 0.0, 1.0)
		FishingConst.ST_LANDING:
			return 0.7 if lane.state_t < LANDING_ABOARD_S else 0.3
		FishingConst.ST_STRIKE:
			return 0.6
		FishingConst.ST_REEL:
			return 0.15
	return 0.0


## The fish's sprite rect in lane px (size 0 when no fish shows).
func fish_rect() -> Rect2:
	if fish == null or not fish.visible:
		return Rect2()
	return Rect2(fish.position - Vector2(_fish_size) * 0.5, Vector2(_fish_size))


## Where the line ends (lane px): the fish's mouth, the lure, or a short dangle under the tip.
func line_end() -> Vector2:
	var tip := boat.position + FishingRig.ROD_TIP
	if lane == null or boat.flipped:
		return tip + Vector2(0, 6)
	if fish.visible:
		var r := fish_rect()
		return Vector2(r.position.x, r.position.y + r.size.y * 0.5)
	match lane.state:
		FishingConst.ST_CAST:
			var u := clampf(lane.state_t / FishingConst.CAST_S, 0.0, 1.0)
			var target := Vector2(FishingLayout.hint_x(lane.lure_d), water_y + 2)
			var p := tip.lerp(target, u)
			return p - Vector2(0, sin(PI * u) * 16.0)
		FishingConst.ST_REEL, FishingConst.ST_STRIKE:
			return Vector2(FishingLayout.hint_x(lane.lure_d), water_y + 3)
	return tip + Vector2(0, 6)


func _build() -> void:
	sky_a = _sprite("SkyA", Vector2.ZERO)
	sky_b = _sprite("SkyB", Vector2.ZERO)
	_wipe_mat = DitherDissolve.apply(sky_b, 1.0, 1)
	sky_b.visible = false
	sun = _sprite("Sun", Vector2.ZERO, FishingSprites.texture("sun"))
	sun.centered = true
	islands_far = _strip("IslandsFar", "islands_far", 0.05, float(sky_h))
	islands_far.align_bottom = true
	palm = _sprite("Palm", Vector2.ZERO, FishingSprites.texture("island_palm"))
	clouds = _strip("Clouds", "clouds", 0.02, 0.0)
	clouds.drift_px_s = 1.5
	sky_cover = _sprite("SkyCover", Vector2(FishingConst.HUD_X - FishingPalette.COVER_EDGE, 0))
	_layer("SkyHints", _paint_sky_hints)
	water = _sprite("Water", Vector2(0, water_y), FishingPalette.water_texture(lane_h - water_y))
	for x in RAY_XS:
		var ray := _sprite("Rays%d" % x, Vector2(x, water_y), FishingSprites.texture("light_rays"))
		ray.region_enabled = true
		var tex_h := ray.texture.get_height()
		ray.region_rect = Rect2(0, 0, ray.texture.get_width(), mini(tex_h, water_h))
		_ray_mats.append(SpriteWobble.water(ray, 1.0, 0.4))
		rays.append(ray)
	surface = _strip("Surface", "surface_strip", 1.0, float(sky_h - 1))
	surface.mirror_alternate = true
	surface.drift_px_s = 4.0
	var back_tex := FishingSprites.texture("reef_back")
	reef_back = _sprite(
		"ReefBack", Vector2(0, lane_h - SAND_H + 2 - back_tex.get_height()), back_tex
	)
	_layer("WaterHints", _paint_water_hints)
	fish = _sprite("Fish", Vector2.ZERO)
	fish.centered = true
	fish.visible = false
	_fish_mat = SpriteWobble.fish_tail(fish, true, 1.0, 2.0)
	var front_tex := FishingSprites.texture("reef_front")
	reef_front = _sprite(
		"ReefFront", Vector2(0, lane_h - SAND_H + 3 - front_tex.get_height()), front_tex
	)
	_layer("Sand", _paint_sand)
	boat = FishingBoatView.new()
	_boat_base = FishingRig.boat_pos(sky_h)
	boat.position = _boat_base
	add_child(boat)
	_layer("Line", _paint_line)
	effects = FishingEffects.new()
	add_child(effects)
	_layer("Border", _paint_border)


func _sprite(p_name: String, pos: Vector2, tex: Texture2D = null) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = p_name
	s.centered = false
	s.position = pos
	s.texture = tex
	add_child(s)
	return s


func _strip(p_name: String, id: String, factor: float, y: float) -> ParallaxStrip:
	var s := ParallaxStrip.new()
	s.name = p_name
	s.texture = FishingSprites.texture(id)
	s.factor = factor
	s.mirror_alternate = true
	s.auto_process = false
	s.cover_width = float(FishingConst.HUD_X)
	s.position.y = y
	add_child(s)
	return s


func _layer(p_name: String, painter: Callable) -> void:
	var layer := FishingDrawLayer.make(p_name, painter)
	_layers.append(layer)
	add_child(layer)


func _ride(dt: float, st: int) -> void:
	var moving := st == FishingConst.ST_RIDE_OUT or st == FishingConst.ST_HOME
	var target := (
		minf(sqrt(maxf(shown_w, 0.0)) * RIDE_PX_PER_SQRT_W, RIDE_MAX_PX_S) if moving else 0.0
	)
	_speed += (target - _speed) * (1.0 - exp(-dt / 0.6))
	var heading := -1.0 if st == FishingConst.ST_HOME else 1.0
	world_x += heading * _speed * dt
	for s: ParallaxStrip in [islands_far, clouds, surface]:
		s.world_x = world_x
		s.tick(dt)
	var period := 900.0
	palm.position = Vector2(
		roundf(fposmod(_palm_x0 - world_x * 0.15, period) - 80.0),
		float(sky_h - palm.texture.get_height() + 1)
	)
	boat.flipped = st == FishingConst.ST_HOME
	var bob := 1.0 if sin(_anim_t * 1.7 + float(slot)) > 0.55 else 0.0
	boat.position = (
		_boat_base
		+ Vector2(FishingConst.BOAT_X1 - FishingConst.BOAT_X0 if boat.flipped else 0, bob)
	)
	boat.wake_on = _speed > MOVING_PX_S
	boat.wake_x += _speed * dt


func _sky() -> void:
	var v := FishingPalette.day_variant(game_t, total_s)
	var p := FishingPalette.wipe_progress(game_t, total_s)
	if p < 1.0 and v > 0:
		sky_a.texture = FishingPalette.sky_texture(sky_h, v - 1)
		sky_b.texture = FishingPalette.sky_texture(sky_h, v)
		sky_b.visible = true
		DitherDissolve.set_amount(_wipe_mat, 1.0 - p)
	else:
		sky_a.texture = FishingPalette.sky_texture(sky_h, v)
		sky_b.visible = false
	sky_cover.texture = FishingPalette.sky_cover_texture(sky_h, v if p >= 0.5 else maxi(v - 1, 0))
	var f := FishingPalette.sun_fraction(game_t, total_s)
	var x := 110.0 + f * 260.0
	var y := float(sky_h) * 0.8 - sin(PI * f) * float(sky_h) * 0.55
	sun.position = Vector2(roundf(x), roundf(maxf(y, 7.0)))
	model["variant"] = v
	model["wipe"] = p


func _line_speed(dt: float, st: int) -> void:
	var target := 0.0
	match st:
		FishingConst.ST_REEL:
			target = FishingConst.LURE_MPS * shown_cad / FishingConst.LURE_REF_RPM
		FishingConst.ST_FIGHT, FishingConst.ST_LANDING:
			if _prev_d >= 0.0 and dt > 0.0:
				target = clampf((_prev_d - shown_d) / dt, -4.0, 4.0)
			if lane != null and lane.fish.run_active:
				target = minf(target, -1.5)
	_prev_d = shown_d
	line_mps += (target - line_mps) * (1.0 - exp(-dt / 0.25)) if dt > 0.0 else 0.0
	model["line_mps"] = line_mps


func _fish(dt: float, st: int) -> void:
	var show := false
	if lane != null and lane.fish.sp >= 0 and not lane.fish.off_line:
		show = st == FishingConst.ST_STRIKE or st == FishingConst.ST_FIGHT
		show = show or (st == FishingConst.ST_LANDING and lane.state_t < LANDING_GONE_S)
	fish.visible = show
	if not show:
		_jump_t = -1.0
		return
	if lane.fish.sp != _fish_sp:
		_fish_sp = lane.fish.sp
		fish.texture = FishingSprites.texture(fish_sprite_id(content, _fish_sp))
		_fish_size = Vector2i(fish.texture.get_size())
	var d_max := lane.fish.d_max
	if d_max <= 0.0 and content != null and content.species.has(FishingConst.SPECIES[_fish_sp]):
		d_max = (content.species[FishingConst.SPECIES[_fish_sp]] as FishingSpeciesDef).d_max
	var w := _fish_size.x
	var h := _fish_size.y
	var ly := float(FishingLayout.lane_y(slot, n))
	var x := float(FishingLayout.fish_mouth_x(shown_d, d_max, w))
	var y := float(FishingLayout.fish_y(shown_z, slot, n, h)) - ly
	if st == FishingConst.ST_STRIKE:
		x = minf(
			float(FishingLayout.hint_x(lane.lure_d)),
			float(FishingConst.FISH_X0 + FishingConst.FISH_SPAN - w)
		)
		y = float(FishingLayout.fish_y(STRIKE_Z, slot, n, h)) - ly
	var top_left := Vector2(x, y)
	var rot := 0.0
	if st == FishingConst.ST_LANDING and lane.state_t > LANDING_ABOARD_S:
		var u := clampf(
			(lane.state_t - LANDING_ABOARD_S) / (LANDING_GONE_S - LANDING_ABOARD_S), 0.0, 1.0
		)
		var aboard := Vector2(FishingConst.ROD_TIP_X + 2, sky_h - h - 2)
		top_left = top_left.lerp(aboard, u)
		rot = -0.4 * u
	if _jump_t >= 0.0:
		var jumped := _jump(dt, top_left, h)
		top_left = jumped[0]
		rot = jumped[1]
	fish.position = (top_left + Vector2(w, h) * 0.5).round()
	fish.rotation = rot
	SpriteWobble.set_time(_fish_mat, _anim_t)


## Moves the jump clock on; returns [top-left, rotation] of the fish in a leap (or under water
## between leaps) and splashes at each exit and entry.
func _jump(dt: float, base: Vector2, h: int) -> Array:
	_jump_t += dt
	var cycle := LEAP_S + LEAP_GAP_S
	var k := floori(_jump_t / cycle)
	if k >= _jump_leaps:
		_jump_t = -1.0
		return [base, 0.0]
	var u := fmod(_jump_t, cycle) / LEAP_S
	if k != _leap_seen:
		_leap_seen = k
		effects.spawn("splash", Vector2(base.x + float(_fish_size.x) * 0.5, sky_h - 2))
	if u > 1.0:
		return [Vector2(base.x, float(water_y + 1)), 0.0]
	var top := float(sky_h) - float(h) * 0.5 - LEAP_PX * sin(PI * u)
	return [Vector2(base.x, top), -0.6 * cos(PI * u)]


func _paint_sky_hints(c: CanvasItem) -> void:
	var frame := floori(_anim_t * GULL_HZ)
	if lane != null and lane.state == FishingConst.ST_PICK:
		for i in lane.hint_count():
			if int(lane.hints[3 * i]) != FishingConst.SPOT_BIRD_PILE:
				continue
			var x := FishingLayout.hint_x(lane.hints[3 * i + 1])
			var steps := strength_steps(lane.hints[3 * i + 2])
			for k in steps:
				var gx := x - 5 + (k - (steps - 1) / 2) * 9 + roundi(sin(_anim_t * 1.3 + k) * 2.0)
				var gy := maxi(sky_h - 11 - (k % 2) * 5, 1)
				_gull(c, Vector2(gx, gy), (frame + k) % 2 == 0)
	if _frenzy_t >= 0.0:
		var fx := fish_rect().get_center().x if fish.visible else float(FishingLayout.hint_x(60.0))
		for k in 4:
			var ang := _anim_t * 2.0 + float(k) * TAU / 4.0
			var p := Vector2(
				fx + cos(ang) * 14.0 - 5.0, maxf(float(sky_h) - 14.0 + sin(ang) * 4.0, 1.0)
			)
			_gull(c, p.round(), (frame + k) % 2 == 0)


func _gull(c: CanvasItem, at: Vector2, up: bool) -> void:
	c.draw_texture(FishingSprites.texture("gull_up" if up else "gull_down"), at)


func _paint_water_hints(c: CanvasItem) -> void:
	if lane == null or lane.state != FishingConst.ST_PICK:
		return
	for i in lane.hint_count():
		var type := int(lane.hints[3 * i])
		var x := FishingLayout.hint_x(lane.hints[3 * i + 1])
		var steps := strength_steps(lane.hints[3 * i + 2])
		var r := _hint_rect(type, x, steps)
		match type:
			FishingConst.SPOT_BIRD_PILE:
				c.draw_texture(FishingSprites.texture("bait_ball"), r.position)
			FishingConst.SPOT_CURRENT_SEAM:
				var tex := FishingSprites.texture("current_seam")
				var w := mini(SEAM_PX_PER_STEP * steps, tex.get_width())
				c.draw_texture_rect_region(
					tex,
					Rect2(r.position, Vector2(w, tex.get_height())),
					Rect2(0, 0, w, tex.get_height())
				)
			_:
				var tex := FishingSprites.texture("sonar_mark")
				for k in steps:
					var mx := r.position.x + float(k * 7)
					var my := r.position.y + float((k % 2) * 2)
					c.draw_texture(tex, Vector2(mx, my))
		if i == lane.selected:
			_bracket(c, r.grow(2))


## The rect a hint covers (lane px) for its type, centre x and strength steps.
func _hint_rect(type: int, x: int, steps: int) -> Rect2:
	match type:
		FishingConst.SPOT_BIRD_PILE:
			return Rect2(x - 16, water_y + 1, 32, 12)
		FishingConst.SPOT_CURRENT_SEAM:
			var w := SEAM_PX_PER_STEP * steps
			return Rect2(x - w / 2, sky_h, w, 4)
	var z := REEF_EDGE_Z if type == FishingConst.SPOT_REEF_EDGE else DROP_OFF_Z
	var y := water_y + roundi(z * float(maxi(water_h - 7, 0)))
	var w2 := (steps - 1) * 7 + 8
	return Rect2(x - w2 / 2, y, w2, 7)


## The pedal-scan highlight: white corner brackets (gold on the blink) and a down arrow.
func _bracket(c: CanvasItem, r: Rect2) -> void:
	var col := FishingPalette.WHITE if floori(_anim_t * 4.0) % 2 == 0 else FishingPalette.YELLOW
	var a := r.position.floor()
	var b := r.end.floor()
	for corner: Vector2 in [a, Vector2(b.x, a.y), Vector2(a.x, b.y), b]:
		var dx := 3.0 if corner.x == a.x else -3.0
		var dy := 3.0 if corner.y == a.y else -3.0
		c.draw_line(corner, corner + Vector2(dx, 0), col, 1.0)
		c.draw_line(corner, corner + Vector2(0, dy), col, 1.0)
	var mid := roundf((a.x + b.x) * 0.5)
	var top := minf(a.y, float(sky_h)) - 7.0
	var arrow := PackedVector2Array(
		[Vector2(mid - 3, top), Vector2(mid + 3, top), Vector2(mid, top + 3)]
	)
	c.draw_colored_polygon(arrow, col)


func _paint_sand(c: CanvasItem) -> void:
	var tex := FishingSprites.texture("sand_strip")
	var y := float(lane_h - SAND_H)
	var x := 0
	while x < FishingConst.PIXEL_W:
		c.draw_texture(tex, Vector2(x, y))
		x += tex.get_width()
	var cap := PackedVector2Array(
		[
			Vector2(REEF_W, y - 4),
			Vector2(REEF_W + CAP_W, y),
			Vector2(REEF_W + CAP_W, y + 1),
			Vector2(REEF_W - 2, y + 1),
			Vector2(REEF_W - 2, y - 4),
		]
	)
	c.draw_colored_polygon(cap, FishingPalette.GREY_3)
	c.draw_line(Vector2(REEF_W - 2, y - 4.5), Vector2(REEF_W, y - 4.5), FishingPalette.NAVY, 1.0)
	c.draw_line(Vector2(REEF_W, y - 4), Vector2(REEF_W + CAP_W, y), FishingPalette.NAVY, 1.0)


func _paint_line(c: CanvasItem) -> void:
	if lane == null:
		return
	var tip := boat.position + boat.rod_points()[-1]
	if boat.flipped:
		return
	var col := FishingPalette.color_of(str(cosmetic_values.get("line", "")), FishingPalette.LINE)
	if _snap_t >= 0.0:
		var u := _snap_t / SNAP_ANIM_S
		var loose := FishingRig.line(tip, tip + Vector2(10.0, 4.0 + 14.0 * u), 1.0, 0.0, 6)
		c.draw_polyline(FishingRig.snapped(loose), col, 1.0)
		return
	var end := line_end()
	var slack := lane.slack if lane.state == FishingConst.ST_FIGHT else 0.4
	var strain := lane.strain if lane.state == FishingConst.ST_FIGHT else 0.0
	if lane.state == FishingConst.ST_FIGHT and lane.fish.run_active:
		strain = 1.0
	var pts := FishingRig.line(tip, end, slack, strain)
	c.draw_polyline(FishingRig.snapped(pts), col, 1.0)
	var lure := (
		lane.state in [FishingConst.ST_CAST, FishingConst.ST_REEL]
		or (lane.state == FishingConst.ST_STRIKE and not fish.visible)
	)
	if lure:
		c.draw_rect(Rect2(end.floor() - Vector2(1, 0), Vector2(2, 2)), FishingPalette.CORAL)
	model["lure"] = lure


func _paint_border(c: CanvasItem) -> void:
	var r := Rect2(0, 0, FishingConst.PIXEL_W, lane_h)
	if not local:
		c.draw_rect(Rect2(0, 0, r.size.x, 1), FishingPalette.NAVY)
		c.draw_rect(Rect2(0, r.size.y - 1, r.size.x, 1), FishingPalette.NAVY)
		c.draw_rect(Rect2(0, 0, 1, r.size.y), FishingPalette.NAVY)
		c.draw_rect(Rect2(r.size.x - 1, 0, 1, r.size.y), FishingPalette.NAVY)
		return
	var col: Color = look.get("color", Wl.slot_look(slot)["color"])
	FishingView.draw_pattern_frame(c, r, col, str(look.get("pattern", "solid")), 3)
	var tag := Rect2(4, lane_h - 13, 17, 9)
	c.draw_rect(tag, col)
	c.draw_rect(tag, FishingPalette.NAVY, false, 1.0)
	var text_col := FishingView.text_on(col)
	var x := 6.0
	for ch in "YOU":
		_glyph(c, Vector2(x, tag.position.y + 2.0), GLYPHS[ch], text_col)
		x += 4.0


func _glyph(c: CanvasItem, at: Vector2, rows: Array, col: Color) -> void:
	for yy in rows.size():
		var bits := int(rows[yy])
		for xx in 3:
			if bits & (4 >> xx):
				c.draw_rect(Rect2(at + Vector2(xx, yy), Vector2(1, 1)), col)
