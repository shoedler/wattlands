class_name SiegeShotSounds
extends RefCounted
## What each shot in the air lands on, from what every peer already has: the `shot` event, replayed the way the
## picture replays it (SiegeV2ShotReplay), and the enemies of the state, a client's from its snapshots. The rules are
## not asked and nothing goes back to them: this is what the host's own impact rules (SiegeProjectiles) would see at
## that moment, close enough for a sound. Pure: step() hands SiegeAudio the impacts that are due.
##
##   arrows      each lands alone: the nearest body within hit_r + its radius, else the ground. A volley's misses are
##               one patter at its first miss, its hits at most MAX_HITS_PER_VOLLEY of a surface: 12 arrows must not be
##               12 voices. A shield bearer's block comes from the same hash stream as the host's.
##   bolts       fly frame by frame: each body the path passes. The ballista's bolt goes on through them as long as it
##               has damage left, a Scorpion's stops at the first; a bolt that reaches the ground ends there.
##   stones      land once: the ground under them, and whatever stands within the splash.

const SURFACE_DIRT := "dirt"
const SURFACE_WATER := "water"
const SURFACE_FLESH := "flesh"
const SURFACE_WOOD := "wood"
const SURFACE_SHIELD := "shield"
const SURFACES: Array[String] = [
	SURFACE_DIRT, SURFACE_WATER, SURFACE_FLESH, SURFACE_WOOD, SURFACE_SHIELD
]
const WEAPON_ARROW := "arrow"
const WEAPON_BOLT := "bolt"
const WEAPON_SCORPION := "scorpion"
const WEAPON_STONE := "stone"
const MAX_HITS_PER_VOLLEY := 2
## The moat (src/games/siege/art/world.mjs): a band around the fort on three sides, the bridge across it.
const FORT_MIN := Vector2(0.0, 2.0)
const FORT_MAX := Vector2(84.0, 60.0)
const MOAT_IN_M := 4.0
const MOAT_OUT_M := 14.0
const BRIDGE_X_M := 44.0
const BRIDGE_HALF_M := 3.5


class Flying:
	var replay: SiegeV2ShotReplay
	var start_s: float = 0.0
	var weapon: String = WEAPON_BOLT
	var hit_r: float = 0.6
	var damage: float = 0.0
	var keep_infantry: float = 0.75
	var keep_engine: float = 0.3
	var stop_below: float = 10.0
	var splash_m: float = 5.0
	var landed := PackedByteArray()
	var blocks := PackedByteArray()
	var left: int = 0
	var swept_to: PackedFloat32Array = PackedFloat32Array()
	var hit_ids: Dictionary = {}
	var patter_done: bool = false
	var hits: Dictionary = {}


var content: SiegeContent = null
var path: SiegePath = null
var flying: Array[Flying] = []


## Starts one `shot` event's flight; {flight_s, from: launch point, to: where it comes down}.
func add(ev: Dictionary, start_s: float) -> Dictionary:
	var r := SiegeV2ShotReplay.from_event(ev, path, content)
	var def := SiegeV2ShotReplay.def_for(content, r.src)
	var f := Flying.new()
	f.replay = r
	f.start_s = start_s
	f.weapon = weapon_of(r.kind)
	f.hit_r = float(def.get("hit_r_m", 0.6))
	f.damage = float(def.get("damage", 1.0))
	f.keep_infantry = float(def.get("keep_infantry", 0.75))
	f.keep_engine = float(def.get("keep_engine", 0.3))
	f.stop_below = float(def.get("stop_below", 10.0))
	f.splash_m = float(def.get("splash_m", 5.0))
	f.landed.resize(r.n)
	f.landed.fill(0)
	f.swept_to.resize(r.n)
	f.swept_to.fill(0.0)
	f.left = r.n
	if r.kind == SiegeIds.SHOT_ARROW:
		f.blocks = _blocks(r, float(def.get("testudo_block", 0.7)))
	flying.append(f)
	var sum := 0.0
	for j in r.n:
		sum += r.land_t[j]
	return {
		"flight_s": sum / float(r.n),
		"from": r.origin,
		"to": r.landing(0),
	}


## How many of `weapon`'s shots are still flying.
func in_air(weapon: String) -> int:
	var n := 0
	for f in flying:
		if f.weapon == weapon:
			n += 1
	return n


## The impacts due by `now_s`, oldest shot first: {weapon, surface, at, count}.
func step(now_s: float, enemies: Array[SiegeEnemyState]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var keep: Array[Flying] = []
	for f in flying:
		var t := now_s - f.start_s
		match f.replay.kind:
			SiegeIds.SHOT_ARROW:
				_arrows(f, t, enemies, out)
			SiegeIds.SHOT_STONE:
				_stone(f, t, enemies, out)
			_:
				_bolt(f, t, enemies, out)
		if f.left > 0:
			keep.append(f)
	flying = keep
	return out


static func weapon_of(kind: int) -> String:
	match kind:
		SiegeIds.SHOT_ARROW:
			return WEAPON_ARROW
		SiegeIds.SHOT_STONE:
			return WEAPON_STONE
		SiegeIds.SHOT_SCORPION:
			return WEAPON_SCORPION
	return WEAPON_BOLT


## What an enemy sounds like when struck.
static func surface_of(enemy_type: int) -> String:
	match enemy_type:
		SiegeIds.ENEMY_SPEAR:
			return SURFACE_FLESH
		SiegeIds.ENEMY_SHIELD:
			return SURFACE_SHIELD
	return SURFACE_WOOD


## The ground or the water at `p`: the moat's band around the fort, on its three open sides, off the bridge.
static func ground_at(p: Vector3) -> String:
	if p.y <= FORT_MIN.y + 2.0 or (p.y <= 14.0 and p.x >= FORT_MIN.x and p.x <= FORT_MAX.x):
		return SURFACE_DIRT
	var dx := maxf(maxf(FORT_MIN.x - p.x, p.x - FORT_MAX.x), 0.0)
	var dy := maxf(maxf(FORT_MIN.y - p.y, p.y - FORT_MAX.y), 0.0)
	var d := sqrt(dx * dx + dy * dy)
	if d < MOAT_IN_M or d > MOAT_OUT_M:
		return SURFACE_DIRT
	return SURFACE_DIRT if absf(p.x - BRIDGE_X_M) <= BRIDGE_HALF_M else SURFACE_WATER


## The host draws one block per arrow, in launch order, from a second stream of the shot's seed.
static func _blocks(r: SiegeV2ShotReplay, chance: float) -> PackedByteArray:
	var out := PackedByteArray()
	var stream := SiegeHashRng.new(r.seed_value ^ SiegeProjectiles.TESTUDO_SALT)
	for _j in r.n:
		out.append(1 if stream.randf01() < chance else 0)
	return out


func _arrows(f: Flying, t: float, enemies: Array[SiegeEnemyState], out: Array[Dictionary]) -> void:
	for j in f.replay.n:
		if f.landed[j] != 0 or t < f.replay.land_t[j]:
			continue
		f.landed[j] = 1
		f.left -= 1
		var at := f.replay.landing(j)
		var body := _nearest(at, f.hit_r, enemies)
		if body == null:
			if not f.patter_done:
				f.patter_done = true
				var misses := _misses_left(f, enemies)
				out.append(_impact(f, ground_at(at), at, misses))
			continue
		var surface := surface_of(body.type)
		if body.type == SiegeIds.ENEMY_SHIELD and f.blocks[j] == 0:
			surface = SURFACE_FLESH
		var n := int(f.hits.get(surface, 0))
		if n < MAX_HITS_PER_VOLLEY:
			f.hits[surface] = n + 1
			out.append(_impact(f, surface, at, 1))


## This arrow and those still in the air that would come down on nothing as things stand.
func _misses_left(f: Flying, enemies: Array[SiegeEnemyState]) -> int:
	var n := 1
	for j in f.replay.n:
		if f.landed[j] == 0 and _nearest(f.replay.landing(j), f.hit_r, enemies) == null:
			n += 1
	return n


func _stone(f: Flying, t: float, enemies: Array[SiegeEnemyState], out: Array[Dictionary]) -> void:
	if f.landed[0] != 0 or t < f.replay.land_t[0]:
		return
	f.landed[0] = 1
	f.left = 0
	var at := f.replay.landing(0)
	var surface := ground_at(at)
	var reach := f.splash_m * f.splash_m
	for e in enemies:
		if not e.alive():
			continue
		if Vector2(e.pos.x - at.x, e.pos.y - at.y).length_squared() > reach:
			continue
		var s := surface_of(e.type)
		if s == SURFACE_WOOD:
			surface = s
			break
		surface = s
	out.append(_impact(f, surface, at, 1))


func _bolt(f: Flying, t: float, enemies: Array[SiegeEnemyState], out: Array[Dictionary]) -> void:
	var end := minf(t, f.replay.land_t[0])
	var from := f.swept_to[0]
	while from < end:
		var to := minf(from + SiegeBallistics.DT, end)
		var a := f.replay.position(0, from)
		var b := f.replay.position(0, to)
		from = to
		for e in _passed(a, b, f, enemies):
			f.hit_ids[e.id] = true
			out.append(_impact(f, surface_of(e.type), b, 1))
			if f.weapon == WEAPON_SCORPION:
				f.left = 0
				return
			f.damage *= f.keep_engine if SiegeIds.is_engine(e.type) else f.keep_infantry
			if f.damage < f.stop_below:
				f.left = 0
				return
	f.swept_to[0] = from
	if t >= f.replay.land_t[0]:
		f.left = 0
		var at := f.replay.landing(0)
		out.append(_impact(f, ground_at(at), at, 1))


## The bodies segment a..b passes, by the host's test: within hit_r + radius in plan, between feet and head.
func _passed(
	a: Vector3, b: Vector3, f: Flying, enemies: Array[SiegeEnemyState]
) -> Array[SiegeEnemyState]:
	var out: Array[SiegeEnemyState] = []
	var seg := b - a
	var seg2 := maxf(seg.length_squared(), 1e-9)
	for e in enemies:
		if not e.alive() or f.hit_ids.has(e.id):
			continue
		var u := clampf((e.pos - a).dot(seg) / seg2, 0.0, 1.0)
		var c := a + seg * u
		var r := f.hit_r + _body_r(e.type)
		if Vector2(c.x - e.pos.x, c.y - e.pos.y).length_squared() > r * r:
			continue
		if c.z >= e.pos.z - 0.2 and c.z <= e.pos.z + _body_h(e.type):
			out.append(e)
	return out


func _nearest(at: Vector3, hit_r: float, enemies: Array[SiegeEnemyState]) -> SiegeEnemyState:
	var best: SiegeEnemyState = null
	var best_d := INF
	for e in enemies:
		if not e.alive():
			continue
		var d := Vector2(e.pos.x - at.x, e.pos.y - at.y).length() - _body_r(e.type)
		if d <= hit_r and d < best_d:
			best = e
			best_d = d
	return best


func _body_r(enemy_type: int) -> float:
	return float(content.enemy_def(enemy_type).get("body_r_m", 0.0)) if content != null else 0.0


func _body_h(enemy_type: int) -> float:
	return float(content.enemy_def(enemy_type).get("body_h_m", 1.8)) if content != null else 1.8


func _impact(f: Flying, surface: String, at: Vector3, count: int) -> Dictionary:
	return {"weapon": f.weapon, "surface": surface, "at": at, "count": count}
