class_name TankFx
extends Node2D
## Effects director (brief 3, "Particles"): owns the pooled particles and the two layers that draw
## them, and spawns every effect: muzzle blast, smoke ring, powder smoke, sparks, kicked-up dust,
## brass, explosions, impacts, exhaust by watts, steam puffs and vents, dynamo sparks, wreck
## smoke and fire, track dust. Cosmetic randomness comes from the view's own RNG (seeded from
## ctx.seed); particles never affect the rules. When the frame time rises the emitters thin out
## (`quality`) and the pool cap drops, so 60 fps holds on integrated graphics.

## Frame time (s) above which the emitters start to thin out, and where they bottom out.
const SLOW_FRAME_S := 0.0185
const SLOWEST_FRAME_S := 0.032
const MIN_QUALITY := 0.3
## The scene-lighting flash of a gun lasts about this long.
const FLASH_S := 0.13
## Heat shimmer quads drawn at once (stack mouths); the strongest requests of a frame win.
const SHIMMER_MAX := 3
## A shimmer quad's size (art px): it stands on the stack mouth.
const SHIMMER_SIZE := Vector2(16.0, 32.0)
## The fastest a source can move (art px/s; the hull tops out near 120): a camera jump (a fast
## forward, a new stage) is not motion, so faster readings are ignored.
const MAX_SOURCE_V := 160.0
## How much of a source's own motion its smoke keeps as it leaves (the rest it loses to drag).
const SMOKE_CARRY := 0.6
## Diesel exhaust colours (the lit underside; the top of each puff is about half as bright, see
## TankFxLayer.billow): a pale wisp at idle, dark iron at tempo (its shaded tops darker than the
## night sky, so the column reads as smoke against it rather than matching it), black in a sprint.
const EXHAUST_IDLE := Color("#62676d")
const EXHAUST_TEMPO := Color("#2c3035")
const EXHAUST_SPRINT := Color(0.07, 0.072, 0.08)
## Brass casings fall under this gravity (art px/s^2): a slow enough arc to follow.
const BRASS_GRAVITY := 300.0
## How far below the breech a spent casing falls before it is gone (art px).
const BRASS_DROP := 25.0
## The road dust a gun blast kicks up, and the dust and mud the tracks throw (lit a little by the
## rooms and fires above, so it reads against the dark road).
const MUZZLE_DUST := Color(0.52, 0.46, 0.36, 0.75)
const TRACK_DUST := Color(0.55, 0.48, 0.38, 0.72)
const TRACK_MUD := Color(0.3, 0.24, 0.17, 1.0)
## The fastest a dynamo spark climbs (art px/s): under its gravity it rises at most about 3 px.
const SPARK_MAX_RISE_V := 28.0
## Hull speed (m/s) where the tracks start to throw dust, and where it is in full (about 20 km/h).
const DUST_MIN_MPS := 0.8
const DUST_FULL_MPS := 5.6
## How far ahead of the rear sprocket (art px) the lower track run raises dust.
const DUST_RUN_PX := 70.0
## The deck vent's plume: each stroke feeds the column for PLUME_S at PLUME_RATE puffs/s, small
## grey-white puffs that swell, rise about 30 px and drift back, never brighter than PLUME_CORE (below
## the lamps).
const PLUME_S := 0.4
const PLUME_RATE := 18.0
const PLUME_CORE := Color("#cfd0cf")
## The air's drift (art px/s, toward the rear): a standing tank's plumes still lean back.
const PLUME_WIND := 6.0
const SHIMMER_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float strength = 0.0;
uniform float phase = 0.0;
void fragment() {
	float up = 1.0 - UV.y;
	float side = 1.0 - smoothstep(0.2, 0.5, abs(UV.x - 0.5));
	float fade = smoothstep(0.0, 0.12, up) * (1.0 - smoothstep(0.4, 1.0, up)) * side;
	float wob = sin(UV.y * 13.0 + TIME * 10.0 + phase);
	wob += 0.6 * sin(UV.y * 29.0 - TIME * 16.0 + phase * 1.7);
	vec2 off = vec2(wob * SCREEN_PIXEL_SIZE.x * 2.2 * strength, 0.0);
	vec4 c = texture(screen_tex, SCREEN_UV + off);
	// Hot air also bends the light: soft bands a shade lighter and darker that ride up with the
	// wobble over a faint warm lift, so the shimmer shows over flat sky too, not only over edges.
	float band = sin(UV.y * 20.0 - TIME * 9.0 + phase * 0.7 + wob * 0.8);
	c.rgb = c.rgb * (1.0 + 0.22 * band * strength) + vec3(0.035, 0.026, 0.014) * strength;
	COLOR = vec4(c.rgb, fade * clamp(strength, 0.0, 1.0));
}
"""

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var particles: TankParticles = TankParticles.new()
var alpha_layer: TankFxLayer = null
var add_layer: TankFxLayer = null
## 0.3 .. 1: scales every emission rate and count.
var quality: float = 1.0
## The gun's lighting flash, 1 at the shot fading to 0 over FLASH_S.
var flash: float = 0.0
var flash_color: Color = TankPalette.AMBER
## Where the last gun flash is (layer coordinates): the scene is lit around it.
var flash_pos: Vector2 = Vector2.ZERO
## Smoothed frame time (s).
var frame_time: float = 0.0
## The camera's speed (art px/s, smoothed): what an emitter riding on the hull moves at in the world.
var scroll_v: float = 0.0
## Live heat shimmer quads (tests).
var shimmer_live: int = 0
## Effect time (s), for pulsing emitters.
var time_s: float = 0.0

var _acc: Dictionary = {}
## Each keyed source's position last frame (layer coordinates), for the motion its smoke inherits.
var _src: Dictionary = {}
## This frame's shimmer requests: [position, strength].
var _heat: Array[Array] = []
var _shimmer: Array[ColorRect] = []
var _back_copy: BackBufferCopy = null
## The deck vent's column: where its mouth is and how long the last stroke still feeds it (s).
var _plume_at: Vector2 = Vector2.ZERO
var _plume_left: float = 0.0


func _init() -> void:
	alpha_layer = TankFxLayer.new(false)
	alpha_layer.name = "SmokeLayer"
	alpha_layer.particles = particles
	add_child(alpha_layer)
	# The heat shimmer re-reads what is already drawn (the planes, the rig and the young smoke
	# leaving the mouth) and shifts it by a pixel or two in waves just above the stack mouth, so
	# the stack's cap and the first puffs waver: a fresh back-buffer copy, then up to SHIMMER_MAX
	# small quads, under the fire and sparks. Built once; no frame creates a texture or a node.
	_back_copy = BackBufferCopy.new()
	_back_copy.name = "ShimmerCopy"
	_back_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_back_copy.visible = false
	add_child(_back_copy)
	var shader := Shader.new()
	shader.code = SHIMMER_SHADER
	for i in SHIMMER_MAX:
		var q := ColorRect.new()
		q.name = "Shimmer%d" % i
		q.size = SHIMMER_SIZE
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("phase", float(i) * 2.1)
		q.material = m
		q.visible = false
		add_child(q)
		_shimmer.append(q)
	add_layer = TankFxLayer.new(true)
	add_layer.name = "FireLayer"
	add_layer.particles = particles
	add_child(add_layer)


func seed_rng(seed_value: int) -> void:
	rng.seed = seed_value


## The emitter quality 0.3 .. 1 for a frame time of `ft` seconds.
static func quality_for(ft: float) -> float:
	if ft <= SLOW_FRAME_S:
		return 1.0
	var k := clampf((ft - SLOW_FRAME_S) / (SLOWEST_FRAME_S - SLOW_FRAME_S), 0.0, 1.0)
	return lerpf(1.0, MIN_QUALITY, k)


## Feeds one frame's real duration: smooths it and retunes quality and the pool cap.
func note_frame_time(ft: float) -> void:
	frame_time = ft if frame_time <= 0.0 else lerpf(frame_time, ft, 0.12)
	quality = quality_for(frame_time)
	particles.cap = roundi(lerpf(float(TankParticles.CAP) * 0.6, float(TankParticles.CAP), quality))


## Advances the particles and the flash (`scroll_px`: how far the camera moved); redraws the layers.
func step(dt: float, scroll_px: float = 0.0) -> void:
	particles.step(dt, float(TankConst.GROUND_Y), scroll_px)
	time_s += dt
	if dt > 0.0:
		var v := scroll_px / dt
		scroll_v = lerpf(scroll_v, v if absf(v) <= MAX_SOURCE_V else scroll_v, 0.3)
	flash = maxf(0.0, flash - dt / FLASH_S)
	_feed_plume(dt)
	_place_shimmer()
	alpha_layer.queue_redraw()
	add_layer.queue_redraw()


func live() -> int:
	return particles.count


## Whole particles to spawn this frame for a source emitting `per_s`, with a fractional carry.
## `thin`: false for the few emitters that carry the riders' effort (the diesel's exhaust), which
## never thin out (they are a handful of particles a second; the pool cap still holds).
func rate(key: String, per_s: float, dt: float, thin: bool = true) -> int:
	var a: float = float(_acc.get(key, 0.0)) + per_s * (quality if thin else 1.0) * dt
	var n := int(a)
	_acc[key] = a - float(n)
	return n


## Forgets the emission carries of the source `key` (and its `key_...` companions) when it is gone.
func forget(key: String) -> void:
	for k: String in _acc.keys():
		if k == key or k.begins_with(key + "_"):
			_acc.erase(k)
	_src.erase(key)


## The world velocity (art px/s) of the keyed source now at `at`: its own motion on screen plus the
## camera's (a stack on the hull moves at the hull's speed, a parked enemy's stack not at all).
## `plane`: the source's depth plane (a far source moves with half the camera's speed).
func source_velocity(key: String, at: Vector2, dt: float, plane: int = 0) -> Vector2:
	var v := Vector2(scroll_v * float(TankParticles.PLANE_SCROLL.get(plane, 1.0)), 0.0)
	if _src.has(key) and dt > 0.0:
		var d: Vector2 = (at - (_src[key] as Vector2)) / dt
		if d.length() <= MAX_SOURCE_V * 2.0:
			v += d
	_src[key] = at
	return v.limit_length(MAX_SOURCE_V)


## Asks for a heat shimmer over the stack mouth at `at` this frame (`strength` 0 .. 1).
func shimmer(at: Vector2, strength: float) -> void:
	_heat.append([at, clampf(strength, 0.0, 1.0)])


func _place_shimmer() -> void:
	_heat.sort_custom(_stronger)
	shimmer_live = mini(_heat.size(), SHIMMER_MAX)
	for i in SHIMMER_MAX:
		var q := _shimmer[i]
		q.visible = i < shimmer_live
		if q.visible:
			var h: Array = _heat[i]
			var foot := Vector2(SHIMMER_SIZE.x * 0.5, SHIMMER_SIZE.y - 3.0)
			q.position = ((h[0] as Vector2) - foot).round()
			(q.material as ShaderMaterial).set_shader_parameter("strength", float(h[1]))
	_back_copy.visible = shimmer_live > 0
	_heat.clear()


static func _stronger(a: Array, b: Array) -> bool:
	return float(a[1]) > float(b[1])


## A cosmetic random number in [lo, hi] from the view's own RNG.
func r(lo: float, hi: float) -> float:
	return rng.randf_range(lo, hi)


func _count(n: int) -> int:
	return maxi(1, roundi(float(n) * quality))


# --- Guns ------------------------------------------------------------------------------------


## The main gun fires at `at` along unit vector `dir`; `heavy` 0 .. 1 scales the blast.
func muzzle_blast(at: Vector2, dir: Vector2, heavy: float = 0.6, ground_dust: bool = true) -> void:
	flash = 1.0
	flash_color = TankPalette.AMBER
	flash_pos = at
	var big := 1.0 + heavy * 0.6
	particles.spawn(
		TankParticles.Kind.FLASH,
		at,
		Vector2.ZERO,
		0.1,
		50.0 * big,
		120.0 * big,
		TankPalette.GLOW_WARM
	)
	if particles.spawn(
		TankParticles.Kind.MUZZLE,
		at,
		Vector2.ZERO,
		0.09,
		22.0 * big,
		44.0 * big,
		TankPalette.WHITE_WARM
	):
		particles.tumble(dir.angle(), 0.0)
	for _i in _count(3):
		var v := dir.rotated(r(-0.3, 0.3)) * r(60.0, 150.0)
		particles.spawn(
			TankParticles.Kind.FIRE,
			at + dir * 3.0,
			v,
			r(0.1, 0.18),
			16.0 * big,
			5.0,
			TankPalette.AMBER,
			0.0,
			6.0
		)
	# The smoke ring: a lumpy roll of soft puffs thrown along the barrel that swells and breaks
	# up into separate wisps within about a quarter second (its seed jitters the puffs).
	if particles.spawn(
		TankParticles.Kind.RING,
		at + dir * 10.0,
		dir * 34.0 + Vector2(0, -4.0),
		0.75,
		12.0,
		36.0 * big,
		Color(0.58, 0.58, 0.57, 0.8),
		0.0,
		1.8
	):
		particles.tumble(r(0.0, 97.0), 0.0)
	# Powder smoke: a lingering bank of puffs off the muzzle, drifting up and downwind slowly.
	for _i in _count(9):
		var v := dir.rotated(r(-0.6, 0.6)) * r(10.0, 70.0) + Vector2(r(-4.0, 4.0), r(-10.0, -2.0))
		particles.spawn(
			TankParticles.Kind.SMOKE,
			at + dir * r(4.0, 22.0) + Vector2(0, r(-4.0, 4.0)),
			v,
			r(2.2, 3.6),
			r(8.0, 12.0),
			r(28.0, 44.0) * big,
			Color(0.46, 0.46, 0.46, 0.7),
			-6.0,
			1.2
		)
	for _i in _count(8):
		var v := dir.rotated(r(-0.45, 0.45)) * r(110.0, 260.0)
		particles.spawn(
			TankParticles.Kind.SPARK, at, v, r(0.25, 0.55), 1.0, 1.0, TankPalette.AMBER, 300.0, 0.4
		)
	if ground_dust:
		var gy := float(TankConst.GROUND_Y) - 2.0
		# The blast kicks the dust up off the road below and ahead of the muzzle: a low, wide
		# burst that rolls out along the ground and climbs clear of the road's dark edge.
		for k in _count(12):
			var side := -1.0 if k % 3 == 0 else 1.0
			particles.spawn(
				TankParticles.Kind.DUST,
				Vector2(at.x + r(-8.0, 36.0), gy - r(0.0, 3.0)),
				Vector2(side * r(20.0, 85.0), -r(22.0, 60.0)),
				r(1.1, 1.9),
				r(6.0, 10.0),
				r(28.0, 44.0),
				MUZZLE_DUST,
				-8.0,
				1.5
			)


## A spent casing leaves the breech at `at` (dir: roughly up and back).
func brass(at: Vector2, dir: Vector2) -> void:
	# It leaves the moving hull at the hull's speed.
	# A short visible arc: up 8-15 px, then down past the hull's side, tumbling (16-26 rad/s, so it
	# glints about once per half turn; see TankFxLayer._draw_brass).
	# It is gone (its last 15 % a fade) once it has fallen BRASS_DROP px below the breech, so it never
	# tumbles down across the cutaway rooms, where it would read as a room's own sparks.
	var v := dir.rotated(r(-0.25, 0.25)) * r(40.0, 60.0) + Vector2(scroll_v, -r(42.0, 58.0))
	var up := maxf(-v.y, 0.0)
	var ttl := (up + sqrt(up * up + 2.0 * BRASS_GRAVITY * BRASS_DROP)) / BRASS_GRAVITY
	if particles.spawn(
		TankParticles.Kind.BRASS, at, v, ttl, 3.0, 3.0, TankPalette.BRASS, BRASS_GRAVITY, 0.2
	):
		var sp := r(16.0, 26.0)
		particles.tumble(r(0.0, TAU), sp if rng.randf() < 0.5 else -sp)


## A small gun (a secondary or an enemy's) fires at `at`.
func small_blast(at: Vector2, dir: Vector2, color: Color = TankPalette.AMBER) -> void:
	particles.spawn(TankParticles.Kind.FLASH, at, Vector2.ZERO, 0.07, 22.0, 46.0, color)
	for _i in _count(2):
		particles.spawn(
			TankParticles.Kind.SMOKE,
			at,
			dir.rotated(r(-0.4, 0.4)) * r(15.0, 60.0),
			r(0.8, 1.3),
			5.0,
			r(14.0, 20.0),
			Color(0.5, 0.5, 0.52, 0.4),
			-8.0,
			1.5
		)
	for _i in _count(3):
		particles.spawn(
			TankParticles.Kind.SPARK,
			at,
			dir.rotated(r(-0.5, 0.5)) * r(80.0, 180.0),
			r(0.15, 0.3),
			1.0,
			1.0,
			color,
			250.0,
			0.4
		)


# --- Impacts and explosions ------------------------------------------------------------------


## A fireball at `at`; `big` for tanks and the Behemoth.
func explosion(at: Vector2, big: bool = false) -> void:
	var s1 := 66.0 if big else 36.0
	particles.spawn(
		TankParticles.Kind.EXPLOSION,
		at,
		Vector2.ZERO,
		0.5 if big else 0.36,
		s1 * 0.25,
		s1,
		Color.WHITE
	)
	particles.spawn(
		TankParticles.Kind.FLASH, at, Vector2.ZERO, 0.28, s1 * 1.2, s1 * 3.0, TankPalette.GLOW_WARM
	)
	for _i in _count(8 if big else 4):
		particles.spawn(
			TankParticles.Kind.FIRE,
			at + Vector2(r(-8.0, 8.0), r(-6.0, 6.0)),
			Vector2(r(-45.0, 45.0), r(-90.0, -20.0)),
			r(0.3, 0.6),
			s1 * 0.4,
			6.0,
			TankPalette.FIRE,
			40.0,
			1.5
		)
	for _i in _count(8 if big else 4):
		particles.spawn(
			TankParticles.Kind.SMOKE,
			at + Vector2(r(-10.0, 10.0), r(-8.0, 4.0)),
			Vector2(r(-30.0, 30.0), r(-60.0, -20.0)),
			r(1.8, 3.2),
			10.0,
			s1 * r(0.8, 1.2),
			Color(0.3, 0.31, 0.33, 0.6),
			-14.0,
			0.8
		)
	for _i in _count(14 if big else 6):
		var a := r(0.0, TAU)
		particles.spawn(
			TankParticles.Kind.SPARK,
			at,
			Vector2(cos(a), sin(a)) * r(60.0, 240.0),
			r(0.3, 0.7),
			1.0,
			1.0,
			TankPalette.AMBER,
			320.0,
			0.3
		)
	for _i in _count(5):
		particles.spawn(
			TankParticles.Kind.EMBER,
			at,
			Vector2(r(-80.0, 80.0), r(-130.0, -40.0)),
			r(0.8, 1.6),
			1.0,
			1.0,
			TankPalette.FIRE,
			260.0,
			0.1
		)


## A shell strikes armour at `at`: sparks and hot fragments (`away`: the direction they fly).
func impact_sparks(at: Vector2, away: Vector2 = Vector2.UP) -> void:
	particles.spawn(
		TankParticles.Kind.FLASH, at, Vector2.ZERO, 0.12, 16.0, 44.0, TankPalette.GLOW_WARM
	)
	for _i in _count(16):
		particles.spawn(
			TankParticles.Kind.SPARK,
			at,
			away.rotated(r(-1.3, 1.3)) * r(70.0, 260.0),
			r(0.25, 0.6),
			1.0,
			1.0,
			TankPalette.GLOW_WARM if rng.randf() < 0.6 else TankPalette.WHITE_WARM,
			340.0,
			0.3
		)
	for _i in _count(5):
		particles.spawn(
			TankParticles.Kind.EMBER,
			at,
			away.rotated(r(-1.2, 1.2)) * r(30.0, 100.0),
			r(0.7, 1.4),
			1.0,
			1.0,
			TankPalette.FIRE,
			300.0,
			0.2
		)
	# A dark smoke column off the struck armour, rising and spreading.
	for k in _count(5):
		particles.spawn(
			TankParticles.Kind.SMOKE,
			at + Vector2(r(-3.0, 3.0), -float(k) * 3.0),
			Vector2(r(-4.0, 8.0), -r(16.0, 30.0)),
			r(1.4, 2.4),
			6.0,
			r(18.0, 26.0),
			Color(0.13, 0.13, 0.14, 0.7),
			-4.0,
			0.6
		)


## A shell lands in the ground at `at`: a spray of dirt and clods and a dust cloud.
func dirt_spray(at: Vector2) -> void:
	for _i in _count(14):
		var clod := Color(0.27, 0.21, 0.15, 1.0).lerp(Color(0.2, 0.16, 0.12, 1.0), rng.randf())
		particles.spawn(
			TankParticles.Kind.DIRT,
			at,
			Vector2(r(-80.0, 80.0), r(-190.0, -60.0)),
			r(0.7, 1.3),
			r(2.0, 4.0),
			2.0,
			clod,
			380.0,
			0.1
		)
	for _i in _count(4):
		particles.spawn(
			TankParticles.Kind.DUST,
			at + Vector2(r(-8.0, 8.0), -2.0),
			Vector2(r(-35.0, 35.0), r(-34.0, -10.0)),
			r(0.7, 1.2),
			8.0,
			r(22.0, 34.0),
			Color(0.42, 0.36, 0.28, 0.5),
			0.0,
			1.6
		)


# --- Ambient emitters (per frame, keyed so each source keeps its own carry) -----------------------


## A diesel stack at `at` (its mouth): puffs whose rate, size and darkness follow watts (`frac`: 0
## idle .. 1 at FTP .. 1.2+ a sprint) plus a heat shimmer over the mouth. Idle is a thin grey wisp
## now and then, tempo a steady train of iron-grey puffs with a pale rim (lit warm by the room
## below as they leave), and a sprint a thick black column that reads against the haze. The puffs
## leave with the stack's own motion and lose it to the air, so a moving tank trails a diagonal
## plume instead of a flat streak.
func exhaust(key: String, at: Vector2, frac: float, dt: float) -> void:
	var f := clampf(frac, 0.0, 1.5)
	var tempo := clampf(f, 0.0, 1.0)
	var hard := smoothstep(1.0, 1.2, f)
	var src := source_velocity(key, at, dt)
	# The engine's beat: puffs come in clumps (one per beat, faster with watts), so the column
	# reads as a train of separate puffs; a sprint is a continuous column.
	var beat := 0.5 + 0.5 * sin(TAU * (1.6 + 1.2 * tempo) * time_s + float(key.hash() % 97))
	var per_s := lerpf(3.0, 10.0, tempo) * lerpf(0.2 + 1.6 * beat, 1.0, hard) + 12.0 * hard
	for _i in rate(key, per_s, dt, false):
		var core := EXHAUST_IDLE.lerp(EXHAUST_TEMPO, tempo).lerp(EXHAUST_SPRINT, hard)
		core.a = 0.5 + 0.4 * tempo + 0.08 * hard
		# The soft puff texture shows about half its quad, so these sizes are twice the visible puff.
		var s1 := (22.0 + 20.0 * tempo + 16.0 * hard) * r(0.75, 1.25)
		var ok := particles.spawn(
			TankParticles.Kind.EXHAUST,
			at + Vector2(r(-1.5, 1.5), r(-1.0, 1.0)),
			Vector2(
				src.x * SMOKE_CARRY + r(-9.0, 9.0) - 4.0 * f,
				-r(30.0, 42.0) - 18.0 * f - 12.0 * hard
			),
			r(1.7, 2.5) + 0.9 * hard,
			(8.0 + 4.0 * tempo + 6.0 * hard) * r(0.85, 1.15),
			s1,
			core,
			-8.0,
			0.4
		)
		if ok:
			particles.tumble(r(-0.35, 0.35), r(-0.25, 0.25))
	for _i in rate(key + "_heat", 3.0, dt):
		particles.spawn(
			TankParticles.Kind.HEAT,
			at + Vector2(r(-2.0, 2.0), -8.0),
			Vector2(src.x * SMOKE_CARRY + r(-3.0, 3.0), -26.0),
			0.8,
			12.0,
			18.0,
			Color(1, 1, 1, 0.07),
			0.0,
			0.5
		)
	if f > 0.05:
		shimmer(at, 0.45 + 0.55 * clampf(f, 0.0, 1.2))


## One white steam puff per stroke at `at` (the cylinder drain or chimney in the steam room): it
## rises inside the room with the hull (never smeared back by the scroll), swells and fades.
func steam_puff(at: Vector2) -> void:
	var hull := TankParticles.PLANE_HULL
	for i in 3:
		var big := i < 2
		particles.spawn(
			TankParticles.Kind.STEAM,
			at + Vector2(r(-2.5, 2.5), r(-2.0, 0.0) - 5.0 * float(i % 2)),
			(
				Vector2(r(-5.0, 5.0), -r(30.0, 46.0))
				if big
				else Vector2(r(-22.0, 22.0), -r(4.0, 12.0))
			),
			r(0.8, 1.1) if big else r(0.4, 0.55),
			(10.0 if i == 0 else 7.0) if big else 6.0,
			(r(30.0, 38.0) if i == 0 else r(20.0, 26.0)) if big else r(12.0, 16.0),
			Color(TankPalette.WHITE_COLD, 0.92 if big else 0.5),
			20.0,
			0.6,
			hull
		)


## A white plume out of a deck vent at `at` (the pipe's mouth), one per stroke: the stroke feeds a
## column of small puffs for PLUME_S that leave the mouth, swell, rise about 30 px and drift back
## (the steam engine's contrast to the diesel's dark smoke). Many small puffs, never one or two big
## round discs, and no brighter than PLUME_CORE, so the lamps stay the brightest things.
func steam_plume(at: Vector2) -> void:
	for _i in 2:
		_plume_puff(at)
	_plume_at = at
	_plume_left = PLUME_S


func _plume_puff(at: Vector2) -> void:
	var c := PLUME_CORE.lerp(TankPalette.STEEL_LIGHT, r(0.0, 0.35))
	c.a = r(0.5, 0.66)
	particles.spawn(
		TankParticles.Kind.STEAM,
		at + Vector2(r(-1.0, 1.0), r(0.5, 2.0)),
		Vector2(scroll_v * 0.35 - PLUME_WIND + r(-4.0, 4.0), -r(42.0, 54.0)),
		r(0.95, 1.35),
		r(4.5, 6.5),
		r(13.0, 19.0),
		c,
		-8.0,
		1.6
	)


## Feeds the deck vent's column while the last stroke's PLUME_S lasts.
func _feed_plume(dt: float) -> void:
	if _plume_left <= 0.0:
		return
	for _n in rate("plume", PLUME_RATE, dt):
		_plume_puff(_plume_at)
	_plume_left -= dt


## The hiss cloud when a shell latches: a white burst that jets sideways off the valve, hangs in the
## room and rolls up.
func steam_burst(at: Vector2) -> void:
	for i in _count(16):
		var jet := i % 4 == 0
		var side := -1.0 if i % 2 == 0 else 1.0
		particles.spawn(
			TankParticles.Kind.STEAM,
			at + Vector2(r(-3.0, 3.0), r(-2.0, 2.0)),
			(
				Vector2(side * r(70.0, 110.0), -r(4.0, 14.0))
				if jet
				else Vector2(r(-45.0, 45.0), -r(20.0, 60.0))
			),
			r(0.8, 1.4),
			10.0,
			r(34.0, 52.0),
			Color(TankPalette.WHITE_COLD, 0.75),
			10.0,
			1.6,
			TankParticles.PLANE_HULL
		)


## The dynamo throws cold sparks off its brushes (`frac` of FTP): fixed blue-white whatever the
## rider's colour (drawn blended, see TankParticles.is_additive), flung along the rim and falling,
## so they stay low in the room around the armature (carried with the hull, never climbing more
## than a few px, so they never reach the wall lamp and its badge up by the ceiling).
func dynamo_sparks(key: String, at: Vector2, frac: float, dt: float) -> void:
	if frac <= 0.0:
		return
	var per_s := lerpf(3.0, 26.0, clampf(frac, 0.0, 1.2))
	for _i in rate(key, per_s, dt):
		# The brushes ride the rim at upper left and upper right (see TankDynamoRoom.brush_tip).
		var a := deg_to_rad(-140.0 if rng.randf() < 0.5 else -40.0) + r(-0.25, 0.25)
		var rim := Vector2(cos(a), sin(a))
		var v := rim.rotated(PI * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0)) * r(18.0, 40.0)
		v += rim * r(4.0, 12.0)
		v.y = maxf(v.y, -SPARK_MAX_RISE_V)
		particles.spawn(
			TankParticles.Kind.SPARK,
			at + rim * r(7.0, 9.5),
			v,
			r(0.2, 0.42),
			1.0,
			1.0,
			TankPalette.COLD_LIGHT if rng.randf() < 0.6 else TankPalette.WHITE_COLD,
			140.0,
			0.5,
			TankParticles.PLANE_HULL
		)


## A wreck or fire at `at`: smoke, flames (while `burn` > 0) and embers.
func fire_and_smoke(
	key: String, at: Vector2, burn: float, smoke: float, dt: float, plane: int = 0
) -> void:
	# Pooled soft puffs, dark soot lit warm from below over a fire, drifting downwind: each grows
	# 2-3x and fades as it rises (never a regular stack, which reads as a coil).
	var soot := Color(0.13, 0.135, 0.145).lerp(TankPalette.RUST, 0.35 * clampf(burn, 0.0, 1.0))
	# A burning hull on the move trails its smoke; a wreck's stands where it is.
	var carry := source_velocity(key, at, dt, plane).x * 0.5
	for _i in rate(key + "_s", 5.0 * smoke, dt):
		var s0 := r(7.0, 12.0)
		particles.spawn(
			TankParticles.Kind.SMOKE,
			at + Vector2(r(-6.0, 6.0), r(-3.0, 1.0)),
			Vector2(carry + r(2.0, 13.0), -r(12.0, 24.0)),
			r(2.8, 4.6),
			s0,
			s0 * r(2.0, 3.0),
			Color(soot.r, soot.g, soot.b, r(0.45, 0.65) * smoke),
			-2.0,
			0.3,
			plane
		)
	if burn <= 0.0:
		return
	for _i in rate(key + "_f", 9.0 * burn, dt):
		particles.spawn(
			TankParticles.Kind.FIRE,
			at + Vector2(r(-5.0, 5.0), r(-2.0, 2.0)),
			Vector2(carry * 1.6 + r(-5.0, 5.0), -r(18.0, 40.0)),
			r(0.25, 0.5),
			9.0 * burn + 2.0,
			3.0,
			TankPalette.FIRE,
			-20.0,
			0.8,
			plane
		)
	for _i in rate(key + "_e", 1.8 * burn, dt):
		particles.spawn(
			TankParticles.Kind.EMBER,
			at,
			Vector2(r(-18.0, 18.0), -r(30.0, 70.0)),
			r(0.8, 1.6),
			1.0,
			1.0,
			TankPalette.AMBER,
			40.0,
			0.4,
			plane
		)


## Dust and mud flicked off the tracks for a hull speed of `speed_mps`; `at` is just behind the rear
## sprocket on the ground. Faint from a walk, full from about 20 km/h (DUST_FULL_MPS): dust rolls up
## off the lower track run under the rear half of the hull and off the sprocket, and clods of mud
## are flung up and back off the turning links. Each keeps part of the hull's motion as it leaves,
## so it hangs behind the wheels for a moment before the road carries it away.
func track_dust(key: String, at: Vector2, speed_mps: float, dt: float) -> void:
	if speed_mps < DUST_MIN_MPS:
		return
	var k := smoothstep(DUST_MIN_MPS, DUST_FULL_MPS, speed_mps)
	var src := source_velocity(key, at, dt)
	for _i in rate(key + "_d", 4.0 + 16.0 * k, dt):
		var along := r(0.0, 1.0)
		along *= along
		var c := TRACK_DUST
		c.a *= 0.45 + 0.55 * k
		particles.spawn(
			TankParticles.Kind.DUST,
			at + Vector2(4.0 + along * DUST_RUN_PX + r(-3.0, 3.0), r(-2.0, 1.0)),
			Vector2(src.x * r(0.55, 0.8) - r(4.0, 14.0), -r(8.0, 16.0) - 12.0 * k),
			r(0.8, 1.4),
			r(5.0, 8.0),
			r(14.0, 22.0) + 10.0 * k,
			c,
			-3.0,
			1.2
		)
	for _i in rate(key + "_m", 1.0 + 8.0 * k, dt):
		var m := TRACK_MUD.lerp(TRACK_DUST, r(0.0, 0.4))
		m.a = 1.0
		particles.spawn(
			TankParticles.Kind.DIRT,
			at + Vector2(r(2.0, 8.0), -r(4.0, 10.0)),
			Vector2(src.x * 0.9 - r(20.0, 55.0), -r(50.0, 95.0)),
			r(0.6, 1.0),
			r(1.6, 2.6),
			2.0,
			m,
			320.0,
			0.0
		)
