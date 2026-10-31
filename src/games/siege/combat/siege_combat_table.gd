class_name SiegeCombatTable
extends RefCounted
## One combat step's read-only numbers, cached once per step so the hot loops index packed
## arrays instead of walking JSON dictionaries (brief 4: a rules step <= 1 ms at the cap), plus
## a lazily built spatial grid of the live enemies for impact checks. Indexed by SiegeIds.ENEMY_*
## codes (index 0 unused). Pure.

## Grid cell edge (m).
const CELL_M := 4.0

var hp := PackedFloat32Array()
var armour := PackedFloat32Array()
var speed := PackedFloat32Array()
var gate_hp := PackedFloat32Array()
var bounty := PackedFloat32Array()
var threat := PackedFloat32Array()
var body_r := PackedFloat32Array()
var body_h := PackedFloat32Array()
## The ram's battering rate in gate HP per second.
var ram_dps: float = 3.0
var lateral_m: float = 1.8
var cap: int = 150
var retreat_s: float = 3.0
## The path.
var length_m: float = 391.0
var moat_edge_m: float = 375.0
var bridge_from_m: float = 375.0
var bridge_to_m: float = 391.0
## Output numbers: reference watts, cap, the upgrade-1 factor, perks.
var ref_w: float = 250.0
var m_cap: float = 4.0
var out_mult: float = 1.4
var reserve: bool = false
var hold_s: float = 10.0
var aqueduct: bool = false
var aq_m: float = 0.25
## The bridge's speed factor this step (1 - slow x coat).
var bridge_f: float = 1.0
## The stations are live this step (a wave, no Breach, not the cool-down).
var live: bool = false
## Enemies removed or killed this step (the compaction pass runs when > 0).
var removed: int = 0
## The biggest body radius (impact searches widen by it).
var max_body_r: float = 3.0

var _grid: Dictionary = {}
var _grid_built: bool = false


## The table of `c` for `state` (content must be valid and have a path).
static func of(c: SiegeContent, state: SiegeState = null) -> SiegeCombatTable:
	var t := SiegeCombatTable.new()
	var n := SiegeIds.ENEMY_NAMES.size()
	t.hp.resize(n)
	t.armour.resize(n)
	t.speed.resize(n)
	t.gate_hp.resize(n)
	t.bounty.resize(n)
	t.threat.resize(n)
	t.body_r.resize(n)
	t.body_h.resize(n)
	t.max_body_r = 0.0
	for code in range(1, n):
		var d := c.enemy_def(code)
		t.hp[code] = float(d.get("hp", 1.0))
		t.armour[code] = float(d.get("armour", 0.0))
		t.speed[code] = float(d.get("speed_mps", 1.0))
		t.gate_hp[code] = float(d.get("gate_hp", 0.0))
		t.bounty[code] = float(d.get("bounty", 0.0))
		t.threat[code] = float(d.get("threat", 1.0))
		t.body_r[code] = float(d.get("body_r_m", 0.0))
		t.body_h[code] = float(d.get("body_h_m", 1.8))
		t.max_body_r = maxf(t.max_body_r, t.body_r[code])
	t.ram_dps = float(c.enemy_def(SiegeIds.ENEMY_RAM).get("gate_hp_per_s", 3.0))
	t.lateral_m = float(c.enemies.get("lateral_m", 1.8))
	t.cap = int(c.enemies.get("cap", 150))
	t.retreat_s = float(c.enemies.get("retreat_s", 3.0))
	t.length_m = c.path.length_m
	t.moat_edge_m = c.path.moat_edge_m
	t.bridge_from_m = c.path.bridge_from_m
	t.bridge_to_m = c.path.bridge_to_m
	t.ref_w = c.num("ref_w", 250.0)
	t.m_cap = c.num("m_cap", 4.0)
	t.out_mult = c.st_num("upgrade_out_mult", 1.4)
	t.hold_s = c.num("perks.reserve_hold_s", 10.0)
	t.aq_m = c.num("perks.aqueduct_m", 0.25)
	if state != null:
		t.reserve = state.perks.has(SiegeIds.PERK_RESERVE)
		t.aqueduct = state.perks.has(SiegeIds.PERK_AQUEDUCT)
		t.live = state.in_wave() and state.phase_kind != Wl.COOLDOWN and state.breach_s <= 0.0
		var slow := c.st_num("stations.tar.coat_slow", 0.5)
		if state.station(SiegeIds.STATION_TAR).level >= 3:
			slow = c.st_num("stations.tar.special_coat_slow", 0.65)
		t.bridge_f = 1.0 - slow * state.tar.coat
	return t


## Forgets the grid (enemies moved, spawned or died).
func invalidate() -> void:
	_grid_built = false


## Live enemies whose centre lies within `r` m of (x, y) on the ground, in spawn order. The grid
## is built on first use in a step (after movement) from `enemies`.
func near(enemies: Array[SiegeEnemyState], x: float, y: float, r: float) -> Array[SiegeEnemyState]:
	if not _grid_built:
		_build(enemies)
	var out: Array[SiegeEnemyState] = []
	var x0 := floori((x - r) / CELL_M)
	var x1 := floori((x + r) / CELL_M)
	var y0 := floori((y - r) / CELL_M)
	var y1 := floori((y + r) / CELL_M)
	var r2 := r * r
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			var cell: Variant = _grid.get(_key(cx, cy))
			if cell == null:
				continue
			for e: SiegeEnemyState in cell:
				if e.hp <= 0.0:
					continue
				var dx := e.pos.x - x
				var dy := e.pos.y - y
				if dx * dx + dy * dy <= r2:
					out.append(e)
	if out.size() > 1:
		out.sort_custom(_by_id)
	return out


## The hit points of the live enemies within `r` m of (x, y), or at least `cap` as soon as they
## reach it. Reads the grid like near() without building a list.
func hp_near(enemies: Array[SiegeEnemyState], x: float, y: float, r: float, cap: float) -> float:
	if not _grid_built:
		_build(enemies)
	var x0 := floori((x - r) / CELL_M)
	var x1 := floori((x + r) / CELL_M)
	var y0 := floori((y - r) / CELL_M)
	var y1 := floori((y + r) / CELL_M)
	var r2 := r * r
	var sum := 0.0
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			var cell: Variant = _grid.get(_key(cx, cy))
			if cell == null:
				continue
			for e: SiegeEnemyState in cell:
				if e.hp <= 0.0:
					continue
				var dx := e.pos.x - x
				var dy := e.pos.y - y
				if dx * dx + dy * dy <= r2:
					sum += e.hp
					if sum >= cap:
						return sum
	return sum


func _build(enemies: Array[SiegeEnemyState]) -> void:
	_grid.clear()
	for e in enemies:
		if not e.alive():
			continue
		var k := _key(floori(e.pos.x / CELL_M), floori(e.pos.y / CELL_M))
		var cell: Variant = _grid.get(k)
		if cell == null:
			_grid[k] = [e]
		else:
			(cell as Array).append(e)
	_grid_built = true


static func _key(cx: int, cy: int) -> int:
	return (cx + 4096) * 8192 + (cy + 4096)


static func _by_id(a: SiegeEnemyState, b: SiegeEnemyState) -> bool:
	return a.id < b.id
