class_name SiegeV2Shots
extends SiegeDepthBatch
## Projectiles in flight and their impacts, replayed from `shot` events (SiegeV2ShotReplay) and
## drawn from the bake's `px` palette in one depth-tested batch, as the mock draws them: bolts
## as short dark streaks with a light trail, stones as a dark ball with a dust trail, arrows as
## 1-2 px lines with a fletch point, each with a drop shadow; impacts from the fx_* frames
## (dust for stones, splinters for bolts, a splash in the moat) and arrows left in the ground.
## Drive it with add_event() and set_time(t) on sim time (seconds = tick * 0.05). A Scorpion bolt
## stops in the first body of `bodies` (the drawn enemies' feet) it passes, as on the host.

const MAX_SHOTS := 64
const STUCK_S := 3.0
const MOAT_Z := -0.8
## A Scorpion bolt hits a body within this of its path (stations.json hit_r_m plus a body).
const BODY_HIT_M := 1.0
const BODY_H_M := 2.2

var path: SiegePath = null
## The spread, drag and landing numbers (stations.json) come from here.
var content: SiegeContent = null
var time_s: float = 0.0
## The enemies' feet now, for the Scorpion bolts (set every frame by the view).
var bodies := PackedVector3Array()
## Shots replaying now.
var shots: Array[SiegeV2ShotReplay] = []

var _px: Dictionary = {}


func _ready() -> void:
	super._ready()
	var names: Array = bank.layout("px").get("names", [])
	for i in names.size():
		_px[str(names[i])] = i


## Starts replaying a shot event; returns the replay (null when the event is malformed).
func add_event(ev: Dictionary) -> SiegeV2ShotReplay:
	if not (ev.get("o") is Array) or not (ev.get("v") is Array):
		return null
	var r := SiegeV2ShotReplay.from_event(ev, path, content)
	shots.append(r)
	if shots.size() > MAX_SHOTS:
		shots.pop_front()
	return r


## Projectiles still in the air at the current time.
func in_flight() -> int:
	var c := 0
	for s in shots:
		var t := time_s - s.tick * SiegeBallistics.DT
		for j in s.n:
			if t >= 0.0 and not s.landed(j, t):
				c += 1
	return c


func set_time(t: float) -> void:
	time_s = t
	rebuild()


func rebuild() -> void:
	begin()
	var keep: Array[SiegeV2ShotReplay] = []
	for s in shots:
		var t := time_s - s.tick * SiegeBallistics.DT
		if t < 0.0:
			keep.append(s)
			continue
		var live := false
		for j in s.n:
			if not s.landed(j, t) and s.kind == SiegeV2ShotReplay.KIND_SCORPION:
				_stop_in_body(s, j, t)
			if not s.landed(j, t):
				_projectile(s, j, t)
				live = true
			else:
				var since := t - s.end_t(j)
				if _impact(s, j, since):
					live = true
		if live or t < s.duration() + STUCK_S:
			keep.append(s)
	shots = keep
	commit()


func _stop_in_body(s: SiegeV2ShotReplay, j: int, t: float) -> void:
	var p := s.position(j, t)
	for b in bodies:
		if absf(b.x - p.x) > BODY_HIT_M or absf(b.y - p.y) > BODY_HIT_M:
			continue
		if p.z >= b.z - 0.2 and p.z <= b.z + BODY_H_M:
			s.stop_t[j] = t
			return


func _p(name: String) -> int:
	return int(_px.get(name, 0))


func _dot(
	name: String, p: Vector3, alpha: float = 1.0, size: int = 1, dx: int = 0, dy: int = 0
) -> void:
	var a := bank.to_art(p)
	var h := size / 2
	add_px(
		_p(name),
		Vector2i(floori(a.x) - h + dx, floori(a.y) - h + dy),
		SiegeBakeBank.depth_of(p),
		alpha,
		Vector2i(size, size)
	)


func _line(name: String, a: Vector3, b: Vector3, alpha: float = 1.0) -> void:
	var sa := bank.to_art(a)
	var sb := bank.to_art(b)
	var steps := maxi(ceili(maxf(absf(sb.x - sa.x), absf(sb.y - sa.y))), 1)
	for i in steps + 1:
		_dot(name, a.lerp(b, float(i) / steps), alpha)


func _shadow(p: Vector3, size: int) -> void:
	var g := Vector3(p.x, p.y, path.ground_z(p.x, p.y) if path != null else 0.0)
	_dot("shadow", g + Vector3(0, 0, 0.4), 0.4, size)


func _projectile(s: SiegeV2ShotReplay, j: int, t: float) -> void:
	var p := s.position(j, t)
	var d := s.direction(j, t)
	match s.kind:
		SiegeV2ShotReplay.KIND_STONE:
			for q in range(16, 0, -2):
				var tq := t - q * SiegeBallistics.DT
				if tq > 0.0:
					var f := 1.0 - float(q) / 16.0
					_dot("stone_trail", s.position(j, tq), 0.15 + 0.45 * f)
					if q < 12:
						_dot("dust", s.position(j, tq), 0.3 * f, 2)
			_dot("stone", p, 1.0, 4)
			_dot("stone_lit", p + Vector3(-0.15, 0.15, 0.3), 1.0, 2)
			_shadow(p, 3)
		SiegeV2ShotReplay.KIND_ARROW:
			for q in range(1, 4):
				_dot("arrow_trail", p - d * (1.3 + q * 0.8), 0.25 / q)
			_line("arrow", p - d * 1.3, p)
			_dot("fletch", p - d * 1.3)
			if j % 3 == 0:
				_shadow(p, 1)
		_:
			# bolts (ballista, scorpion): a light trail, the dark shaft and its iron point
			var big := s.kind == SiegeV2ShotReplay.KIND_BOLT
			var trail := 18 if big else 8
			for q in trail:
				_dot("bolt_trail", p - d * (2.4 + q * 0.5), 1.0 - float(q) / (trail + 4))
			for q in 14 if big else 5:
				_dot(
					"bolt_dark" if q < 2 else "bolt_shaft", p - d * (q * 0.4), 1.0, 2 if big else 1
				)
			_dot("bolt_tip", p)
			_shadow(p, 2 if big else 1)


## Draws what is left of projectile j `since` seconds after it landed; false once it is gone.
func _impact(s: SiegeV2ShotReplay, j: int, since: float) -> bool:
	var at := s.landing(j)
	var wet := at.z < MOAT_Z
	var part := (
		"fx_splash"
		if wet
		else ("fx_dust" if s.kind == SiegeV2ShotReplay.KIND_STONE else "fx_splinters")
	)
	if s.kind == SiegeV2ShotReplay.KIND_ARROW and not wet:
		if since < STUCK_S:
			var d := s.direction(j, s.end_t(j))
			_line("arrow", at, at - d * 0.7)
			return true
		return false
	if s.kind == SiegeV2ShotReplay.KIND_ARROW and j % 4 != 0:
		return false
	var times: Array = bank.layout(part).get("times_s", [])
	if times.is_empty() or since > float(times[times.size() - 1]) + 0.2:
		return false
	var k := 0
	for i in times.size():
		if since >= float(times[i]) - 0.06:
			k = i
	add(part, k, at)
	return true
