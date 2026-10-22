class_name SiegeEffectsView
extends Node3D
## Shots and Caltrop zones (brief 3 "Towers"): bolts are thin boxes with trails flying from a
## tower to what it hit (hits resolve on the fire tick in the rules; this is only a picture), a
## Caltrop throw is a lob; a landed zone is iron spikes inside a faint ring. Bolts come from
## state.shots (kept 0.1 s by the rules), each drawn once. Two bolt MultiMeshes, a ring and a
## spike MultiMesh; no per-shot nodes.

const MAX_BOLTS := 96
const MAX_ZONES := 16
const SPIKES_PER_ZONE := 12
const BOLT_SPEED_MPS := 90.0
const BOLT_MIN_S := 0.1
const BOLT_MAX_S := 0.45
const LOB_S := 0.9
const LOB_HEIGHT_M := 7.0
const TRAIL_M := 3.2
const SPIKE_FADE_S := 0.5

var terrain: SiegeTerrain = null
var towers: SiegeTowersView = null
var bolts_mm: MultiMeshScatter = null
var trails_mm: MultiMeshScatter = null
var rings_mm: MultiMeshScatter = null
var spikes_mm: MultiMeshScatter = null
## Live bolts: {"from": Vector3, "to": Vector3, "t": float (0..1), "dur": float, "lob": bool}.
var bolts: Array[Dictionary] = []
var _tick: int = -1
var _seen: Dictionary = {}
var _last_pos: Dictionary = {}


func setup(p_terrain: SiegeTerrain, p_towers: SiegeTowersView) -> void:
	terrain = p_terrain
	towers = p_towers
	name = "Effects"
	var bolt := SiegeUnitMeshes.bolt()
	bolts_mm = _layer("Bolts", bolt.build(), MAX_BOLTS, false)
	var tm := LowPolyMesh.new()
	var mat := LowPolyMesh.unshaded_material()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.use_surface(&"trail", mat)
	tm.add_box(Vector3(0.07, 0.07, 1.0), Color.WHITE)
	trails_mm = _layer("Trails", tm.build(), MAX_BOLTS, true)
	var rm := LowPolyMesh.new()
	var rmat := LowPolyMesh.unshaded_material()
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.use_surface(&"ring", rmat)
	rm.add_ring(
		1.0, 0.1, 0.05, 28, Color.WHITE, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	)
	rings_mm = _layer("ZoneRings", rm.build(), MAX_ZONES, true)
	spikes_mm = _layer(
		"ZoneSpikes", SiegeUnitMeshes.spike().build(), MAX_ZONES * SPIKES_PER_ZONE, false
	)


func _layer(layer_name: String, mesh: Mesh, capacity: int, colors: bool) -> MultiMeshScatter:
	var mm := MultiMeshScatter.new()
	mm.name = layer_name
	mm.setup(mesh, capacity, colors, false)
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mm)
	return mm


## Spawns a bolt visual for every shot not seen yet, moves the live ones and redraws zones.
## `drawn` maps enemy id -> drawn ground position (the enemy view's).
func update(state: SiegeState, dt: float, drawn: Dictionary) -> void:
	for id: int in drawn:
		_last_pos[id] = drawn[id]
	if _last_pos.size() > 600:
		_last_pos.clear()
	if state.tick != _tick:
		_tick = state.tick
		for shot in state.shots:
			var fired := state.tick - roundi(shot.age_s / Wl.SIM_DT)
			var key := shot.pad * 1000003 + fired
			if _seen.has(key):
				continue
			_seen[key] = fired
			_spawn(state, shot, drawn)
		if _seen.size() > 48:
			for k: int in _seen.keys():
				if int(_seen[k]) < state.tick - 6:
					_seen.erase(k)
	_advance(dt)
	_draw_zones(state)


func _spawn(state: SiegeState, shot: SiegeShot, drawn: Dictionary) -> void:
	var tw := state.pad(shot.pad)
	var lob := tw.type == SiegeIds.TOWER_CALTROP
	var from := towers.muzzle(shot.pad)
	for id in shot.targets:
		if bolts.size() >= MAX_BOLTS:
			return
		var at: Variant = drawn.get(id, _last_pos.get(id))
		if not (at is Vector2):
			continue
		var p: Vector2 = at
		var to := Vector3(p.x, terrain.height_at(p.x, p.y) + 1.1, p.y)
		var dur := (
			LOB_S if lob else clampf(from.distance_to(to) / BOLT_SPEED_MPS, BOLT_MIN_S, BOLT_MAX_S)
		)
		bolts.append({"from": from, "to": to, "t": 0.0, "dur": dur, "lob": lob})


func _advance(dt: float) -> void:
	var xf: Array[Transform3D] = []
	var trail_xf: Array[Transform3D] = []
	var trail_col := PackedColorArray()
	var keep: Array[Dictionary] = []
	for b in bolts:
		b["t"] = float(b["t"]) + dt / float(b["dur"])
		var t: float = b["t"]
		if t >= 1.0:
			continue
		keep.append(b)
		var from: Vector3 = b["from"]
		var to: Vector3 = b["to"]
		var lift := LOB_HEIGHT_M if bool(b["lob"]) else 0.7
		var pos := from.lerp(to, t) + Vector3.UP * (lift * 4.0 * t * (1.0 - t))
		var ahead := (
			from.lerp(to, minf(t + 0.03, 1.0))
			+ Vector3.UP * (lift * 4.0 * minf(t + 0.03, 1.0) * (1.0 - minf(t + 0.03, 1.0)))
		)
		var dir := (ahead - pos).normalized()
		if dir.length() < 0.01:
			dir = (to - from).normalized()
		var basis := Basis.looking_at(dir, Vector3.UP)
		xf.append(Transform3D(basis, pos))
		var tb := basis.scaled(Vector3(1.0, 1.0, TRAIL_M))
		trail_xf.append(Transform3D(tb, pos - dir * (TRAIL_M * 0.5 + 0.6)))
		trail_col.append(Color(0.95, 0.9, 0.78, 0.55 * (1.0 - t * 0.5)))
	bolts = keep
	bolts_mm.set_instances(xf)
	trails_mm.set_instances(trail_xf, trail_col)


func _draw_zones(state: SiegeState) -> void:
	var ring_xf: Array[Transform3D] = []
	var ring_col := PackedColorArray()
	var spike_xf: Array[Transform3D] = []
	for zi in mini(state.zones.size(), MAX_ZONES):
		var z := state.zones[zi]
		var p := z.pos
		var y := terrain.height_at(p.x, p.y) + 0.14
		if not z.landed():
			# In the air: a small reticle where it will land.
			var s := maxf(z.radius_m * 0.35, 0.5)
			ring_xf.append(Transform3D(Basis().scaled(Vector3(s, 1.0, s)), Vector3(p.x, y, p.y)))
			ring_col.append(Color(0.29, 0.29, 0.31, 0.35))
			continue
		ring_xf.append(
			Transform3D(Basis().scaled(Vector3(z.radius_m, 1.0, z.radius_m)), Vector3(p.x, y, p.y))
		)
		ring_col.append(Color(0.29, 0.29, 0.31, 0.42))
		var fade := clampf(z.ttl_s / SPIKE_FADE_S, 0.0, 1.0)
		for k in SPIKES_PER_ZONE:
			var a := float(k) * 2.399963 + float(zi)
			var r := z.radius_m * 0.82 * sqrt((float(k) + 0.5) / float(SPIKES_PER_ZONE))
			var sx := p.x + cos(a) * r
			var sz := p.y + sin(a) * r
			var sc := (0.8 + 0.4 * fposmod(float(k) * 0.37, 1.0)) * fade
			var b := Basis(Vector3.UP, a).scaled(Vector3(sc, sc, sc))
			spike_xf.append(Transform3D(b, Vector3(sx, terrain.height_at(sx, sz) + 0.05, sz)))
	rings_mm.set_instances(ring_xf, ring_col)
	spikes_mm.set_instances(spike_xf)


## Live bolt visuals (tests).
func bolt_count() -> int:
	return bolts.size()


func zone_count() -> int:
	return rings_mm.visible_count()
