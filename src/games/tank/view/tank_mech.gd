class_name TankMech
extends TankMechKit
## The station machines (v4: the six seats' machines) as
## procedural pixel art, painted into an Image with the Image API only (works headless, per frame):
## diesel (Drive), dynamo (Gun: turret traverse + gun charge), steam (Loader), arc (Lights),
## feed (v3, Secondaries: the crank-driven twin belt feed of the bow guns) and repair (v4, Repairs: the
## cam-lifted rivet hammer and the plate press). Designed for 112 x 64;
## other sizes get the 112 x 64 picture scaled (nearest).
##
## Coupling (docs/games/tank.md 3.4): `phase` = crank revolutions (integral of the rider's cadence,
## rpm / 60 per second); every moving part turns at a fixed integer ratio of it (PARTS), so one
## crank revolution is one seamless loop. `power` = watts / target (1 = in band): heat, light,
## smoke, sparks and needles. `t` (seconds) only flickers and drifts. `slot` tints the room lamp
## while in band and a small enamel tag.
##
## Rendering, cheap enough to repaint four cards every frame: the parts that never move are drawn
## once per kind and cached; the moving parts are drawn on a copy; the room light (lamp, fire, arc
## lamp; it depends on power only) is a cached shade overlay per power step, blended natively; the
## glowing parts (hot metal, fire, arcs, sparks, jars) are added last.
##
## This class is the one name outsiders use: it holds paint and the caches. TankMechKit holds what all the machines
## share (and this class inherits it); TankMechDiesel, Dynamo, Steam, Arc, Feed and Repair hold one machine each.

## The repair machine's hammer, which TankInterior draws too: outsiders read it here, as they do the rest.
const R_CAM := TankMechRepair.R_CAM
const R_CAM_R := TankMechRepair.R_CAM_R
const R_HEAD_X := TankMechRepair.R_HEAD_X
const R_REST_Y := TankMechRepair.R_REST_Y
const R_HEAD_LIFT := TankMechRepair.R_HEAD_LIFT
const R_LIFT := TankMechRepair.R_LIFT
const R_SPARK := TankMechRepair.R_SPARK

static var _seen: Dictionary = {}
static var _static_cache: Dictionary = {}
static var _lit_cache: Dictionary = {}


## The contract (MOCK_SPEC_R2): clears and paints the whole Image. The rpm for the needles and
## motion blur is estimated from successive calls (phase over t) per kind and slot.
static func paint(
	img: Image, kind: String, phase: float, power: float, t: float, slot: Color
) -> void:
	paint_ex(img, kind, phase, power, t, slot, -1.0)


## As paint(), with the crank rpm given (rpm < 0: estimate it from successive calls).
static func paint_ex(
	img: Image, kind: String, phase: float, power: float, t: float, slot: Color, rpm: float
) -> void:
	var k := kind if kind in RATIO else "diesel"
	var rate := rpm / 60.0 if rpm >= 0.0 else _rate_of(k, slot, phase, t)
	var pw := clampf(power, 0.0, 1.6)
	_key = KEYS[k]
	_amb_key = AMBS[k]
	var cv := Cv.new(W, H)
	if not _static_cache.has(k):
		match k:
			"diesel":
				TankMechDiesel._diesel_static(cv)
			"dynamo":
				TankMechDynamo._dynamo_static(cv)
			"steam":
				TankMechSteam._steam_static(cv)
			"arc":
				TankMechArc._arc_static(cv)
			"feed":
				TankMechFeed._feed_static(cv)
			"repair":
				TankMechRepair._repair_static(cv)
		_static_cache[k] = cv.al
	var bucket := roundi(pw * 20.0)
	var key := "%s|%d|%s" % [k, bucket, slot.to_html(false)]
	if not _lit_cache.has(key):
		if _lit_cache.size() > 160:
			_lit_cache.clear()
		var lc := Cv.new(W, H)
		var pb := float(bucket) / 20.0
		match k:
			"diesel":
				_lamp_light(lc, TankMechDiesel.D_LAMP, pb, slot)
				TankMechDiesel._diesel_lights(lc, pb)
			"dynamo":
				_lamp_light(lc, TankMechDynamo.Y_LAMP, pb, slot)
			"steam":
				_lamp_light(lc, TankMechSteam.S_LAMP, pb, slot)
				TankMechSteam._steam_lights(lc, pb)
			"arc":
				_lamp_light(lc, TankMechArc.A_LAMP, pb, slot)
				TankMechArc._arc_lights(lc, pb)
			"feed":
				_lamp_light(lc, TankMechFeed.F_LAMP, pb, slot)
				TankMechFeed._feed_lights(lc, pb)
			"repair":
				_lamp_light(lc, TankMechRepair.R_LAMP, pb, slot)
				TankMechRepair._repair_lights(lc, pb)
		_lit_cache[key] = lc.bake(_static_cache[k])
	var lit: Array = _lit_cache[key]
	cv.al = (lit[0] as PackedByteArray).duplicate()
	cv.lm = lit[1]
	cv.use_light = true
	match k:
		"diesel":
			TankMechDiesel._diesel(cv, phase, pw, t, slot, rate)
		"dynamo":
			TankMechDynamo._dynamo(cv, phase, pw, t, slot, rate)
		"steam":
			TankMechSteam._steam(cv, phase, pw, t, slot, rate)
		"arc":
			TankMechArc._arc(cv, phase, pw, t, slot, rate)
		"feed":
			TankMechFeed._feed(cv, phase, pw, t, slot, rate)
		"repair":
			TankMechRepair._repair(cv, phase, pw, t, slot, rate)
	# over power: the whole machine shakes by a pixel
	cv.shake = _over(pw) > 0.4 and _h(floorf(t * 14.0)) > 0.45
	cv.finish(img)


## Crank revolutions per second from the previous call with the same kind and slot.
static func _rate_of(kind: String, slot: Color, phase: float, t: float) -> float:
	var key := kind + slot.to_html()
	var prev: Array = _seen.get(key, [phase, t, 0.0])
	var rate := float(prev[2])
	var dt := t - float(prev[1])
	if dt > 0.0005 and dt < 1.0:
		var r := maxf((phase - float(prev[0])) / dt, 0.0)
		rate = lerpf(rate, r, clampf(dt * 5.0, 0.0, 1.0))
	_seen[key] = [phase, t, rate]
	return rate


## See TankMechRepair.hammer_lift.
static func hammer_lift(revs: float) -> float:
	return TankMechRepair.hammer_lift(revs)


## See TankMechRepair.since_strike.
static func since_strike(revs: float) -> float:
	return TankMechRepair.since_strike(revs)
