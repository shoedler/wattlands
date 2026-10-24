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
const FLASH_S := 0.11

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var particles: TankParticles = TankParticles.new()
var alpha_layer: TankFxLayer = null
var add_layer: TankFxLayer = null
## 0.3 .. 1: scales every emission rate and count.
var quality: float = 1.0
## The gun's lighting flash, 1 at the shot fading to 0 over FLASH_S.
var flash: float = 0.0
var flash_color: Color = TankPalette.AMBER
## Smoothed frame time (s).
var frame_time: float = 0.0

var _acc: Dictionary = {}


func _init() -> void:
	alpha_layer = TankFxLayer.new(false)
	alpha_layer.name = "SmokeLayer"
	alpha_layer.particles = particles
	add_child(alpha_layer)
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
	flash = maxf(0.0, flash - dt / FLASH_S)
	alpha_layer.queue_redraw()
	add_layer.queue_redraw()


func live() -> int:
	return particles.count


## Whole particles to spawn this frame for a source emitting `per_s`, with a fractional carry.
func rate(key: String, per_s: float, dt: float) -> int:
	var a: float = float(_acc.get(key, 0.0)) + per_s * quality * dt
	var n := int(a)
	_acc[key] = a - float(n)
	return n


## Forgets the emission carries of the source `key` (and its `key_...` companions) when it is gone.
func forget(key: String) -> void:
	for k: String in _acc.keys():
		if k == key or k.begins_with(key + "_"):
			_acc.erase(k)


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
	particles.spawn(
		TankParticles.Kind.RING,
		at + dir * 8.0,
		dir * 34.0,
		0.7,
		8.0,
		46.0 * big,
		Color(0.65, 0.66, 0.68, 0.55),
		0.0,
		2.0
	)
	for _i in _count(6):
		var v := dir.rotated(r(-0.45, 0.45)) * r(25.0, 120.0)
		particles.spawn(
			TankParticles.Kind.SMOKE,
			at + dir * r(2.0, 12.0),
			v,
			r(1.3, 2.3),
			9.0,
			r(26.0, 38.0) * big,
			Color(0.55, 0.56, 0.58, 0.5),
			-10.0,
			1.4
		)
	for _i in _count(8):
		var v := dir.rotated(r(-0.45, 0.45)) * r(110.0, 260.0)
		particles.spawn(
			TankParticles.Kind.SPARK, at, v, r(0.25, 0.55), 1.0, 1.0, TankPalette.AMBER, 300.0, 0.4
		)
	if ground_dust:
		var gy := float(TankConst.GROUND_Y) - 2.0
		for _i in _count(5):
			particles.spawn(
				TankParticles.Kind.DUST,
				Vector2(at.x + r(-10.0, 10.0), gy),
				Vector2(r(-45.0, 45.0), r(-26.0, -8.0)),
				r(0.6, 1.0),
				7.0,
				r(22.0, 30.0),
				Color(0.42, 0.36, 0.28, 0.5),
				0.0,
				1.8
			)


## A spent casing leaves the breech at `at` (dir: roughly up and back).
func brass(at: Vector2, dir: Vector2) -> void:
	var v := dir.rotated(r(-0.4, 0.4)) * r(35.0, 75.0) + Vector2(0.0, r(-70.0, -35.0))
	if particles.spawn(
		TankParticles.Kind.BRASS, at, v, 1.6, 2.0, 2.0, TankPalette.BRASS, 420.0, 0.2
	):
		particles.tumble(r(0.0, TAU), r(-22.0, 22.0))


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
	for _i in _count(9):
		particles.spawn(
			TankParticles.Kind.SPARK,
			at,
			away.rotated(r(-1.1, 1.1)) * r(70.0, 230.0),
			r(0.2, 0.55),
			1.0,
			1.0,
			TankPalette.GLOW_WARM,
			340.0,
			0.3
		)
	for _i in _count(3):
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
	particles.spawn(
		TankParticles.Kind.SMOKE,
		at,
		away * 18.0,
		r(0.8, 1.3),
		5.0,
		18.0,
		Color(0.4, 0.4, 0.42, 0.4),
		-10.0,
		1.2
	)


## A shell lands in the ground at `at`: a spray of dirt and clods and a dust cloud.
func dirt_spray(at: Vector2) -> void:
	for _i in _count(9):
		particles.spawn(
			TankParticles.Kind.DIRT,
			at,
			Vector2(r(-70.0, 70.0), r(-170.0, -60.0)),
			r(0.6, 1.2),
			r(1.5, 3.5),
			2.0,
			Color(0.25, 0.2, 0.15, 1.0),
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


## A diesel stack at `at`: black-grey smoke whose rate and thickness follow watts (`frac`: 0 idle ..
## 1 at FTP .. 1.4 a sprint, a visible black plume) plus a faint heat shimmer.
func exhaust(key: String, at: Vector2, frac: float, dt: float) -> void:
	var f := clampf(frac, 0.0, 1.5)
	var sprint := f >= 1.15
	var per_s := lerpf(2.5, 14.0, clampf(f, 0.0, 1.0)) * (1.6 if sprint else 1.0)
	for _i in rate(key, per_s, dt):
		var thick := clampf(f, 0.0, 1.2)
		var col := Color(0.3, 0.31, 0.33, 0.2 + 0.35 * thick).lerp(
			Color(0.05, 0.05, 0.06, 0.8), 1.0 if sprint else 0.0
		)
		particles.spawn(
			TankParticles.Kind.SMOKE,
			at + Vector2(r(-1.5, 1.5), 0.0),
			Vector2(r(-5.0, 9.0), -r(18.0, 34.0) - 24.0 * f),
			r(0.9, 1.7),
			4.0 + 3.0 * thick,
			(14.0 if not sprint else 26.0) * r(0.8, 1.2),
			col,
			-4.0,
			0.5
		)
	for _i in rate(key + "_heat", 5.0, dt):
		particles.spawn(
			TankParticles.Kind.HEAT,
			at + Vector2(r(-2.0, 2.0), -8.0),
			Vector2(r(-3.0, 3.0), -26.0),
			0.8,
			12.0,
			18.0,
			Color(1, 1, 1, 0.07)
		)


## One steam puff per stroke at `at`.
func steam_puff(at: Vector2) -> void:
	for _i in _count(3):
		particles.spawn(
			TankParticles.Kind.STEAM,
			at + Vector2(r(-1.5, 1.5), 0.0),
			Vector2(r(-8.0, 8.0), r(-46.0, -26.0)),
			r(0.7, 1.1),
			5.0,
			r(16.0, 24.0),
			Color(0.88, 0.9, 0.92, 0.6),
			-8.0,
			0.9
		)


## The hiss cloud when a shell latches.
func steam_burst(at: Vector2) -> void:
	for _i in _count(14):
		particles.spawn(
			TankParticles.Kind.STEAM,
			at + Vector2(r(-3.0, 3.0), r(-2.0, 2.0)),
			Vector2(r(-55.0, 55.0), r(-60.0, -10.0)),
			r(0.7, 1.3),
			6.0,
			r(20.0, 34.0),
			Color(0.9, 0.92, 0.94, 0.55),
			-6.0,
			1.2
		)


## The dynamo throws cold sparks around its armature (`frac` of FTP).
func dynamo_sparks(key: String, at: Vector2, frac: float, dt: float) -> void:
	var per_s := lerpf(0.0, 16.0, clampf(frac, 0.0, 1.2))
	for _i in rate(key, per_s, dt):
		var a := r(0.0, TAU)
		(
			particles
			. spawn(
				TankParticles.Kind.SPARK,
				at + Vector2(cos(a), sin(a)) * 6.0,
				# Short hops off the armature: they die within about 24 px of the dynamo room's arc.
				Vector2(cos(a), sin(a)) * r(15.0, 42.0),
				r(0.3, 0.5),
				1.0,
				1.0,
				TankPalette.COLD_LIGHT if rng.randf() < 0.7 else TankPalette.WHITE_COLD,
				110.0,
				0.5
			)
		)


## A wreck or fire at `at`: smoke, flames (while `burn` > 0) and embers.
func fire_and_smoke(
	key: String, at: Vector2, burn: float, smoke: float, dt: float, plane: int = 0
) -> void:
	# Pooled soft puffs, dark soot lit warm from below over a fire, drifting downwind: each grows
	# 2-3x and fades as it rises (never a regular stack, which reads as a coil).
	var soot := Color(0.13, 0.135, 0.145).lerp(TankPalette.RUST, 0.35 * clampf(burn, 0.0, 1.0))
	for _i in rate(key + "_s", 5.0 * smoke, dt):
		var s0 := r(7.0, 12.0)
		particles.spawn(
			TankParticles.Kind.SMOKE,
			at + Vector2(r(-6.0, 6.0), r(-3.0, 1.0)),
			Vector2(r(2.0, 13.0), -r(12.0, 24.0)),
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
			Vector2(r(-5.0, 5.0), -r(18.0, 40.0)),
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


## Dust and mud flicked off the tracks at `at` for a hull speed of `speed_mps`.
func track_dust(key: String, at: Vector2, speed_mps: float, dt: float) -> void:
	if speed_mps < 0.8:
		return
	for _i in rate(key + "_d", speed_mps * 1.7, dt):
		particles.spawn(
			TankParticles.Kind.DUST,
			at + Vector2(r(-4.0, 4.0), r(-3.0, 0.0)),
			Vector2(-speed_mps * r(1.0, 3.0), -r(6.0, 20.0)),
			r(0.5, 0.9),
			4.0,
			r(12.0, 20.0),
			Color(0.42, 0.36, 0.28, 0.32),
			0.0,
			1.2
		)
	for _i in rate(key + "_m", speed_mps * 0.45, dt):
		particles.spawn(
			TankParticles.Kind.DIRT,
			at,
			Vector2(-r(25.0, 70.0), -r(25.0, 60.0)),
			r(0.5, 0.9),
			2.0,
			2.0,
			Color(0.2, 0.16, 0.12, 1.0),
			300.0,
			0.0
		)
