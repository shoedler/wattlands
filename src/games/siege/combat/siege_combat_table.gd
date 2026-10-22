class_name SiegeCombatTable
extends RefCounted
## One combat step's read-only numbers, cached once per step so the hot loops index packed
## arrays instead of walking JSON dictionaries (brief 4: a rules step <= 1 ms with 150 enemies).
## Indexed by SiegeIds.ENEMY_* codes (index 0 unused) and road ids. Pure.

var hp := PackedFloat32Array()
var armor := PackedFloat32Array()
var speed := PackedFloat32Array()
var gate_hp := PackedFloat32Array()
var bounty := PackedFloat32Array()
var threat := PackedFloat32Array()
## The ram's battering rate in gate HP per second.
var ram_dps: float = 0.0
## Road lengths in metres.
var road_len := PackedFloat32Array()
var lateral_m: float = 1.5
var cap: int = 150
var retreat_s: float = 3.0
## Tower definitions by tower code (index 0 unused).
var tower: Array[Dictionary] = []
## Tower output numbers: reference watts, cap, the upgrade-1 factor, perks.
var ref_w: float = 250.0
var m_cap: float = 4.0
var out_mult: float = 1.4
var reserve: bool = false
var hold_s: float = 10.0
var aqueduct: bool = false
var aq_m: float = 0.25
## Enemies removed or killed this step (the compaction pass runs when > 0).
var removed: int = 0


## The table of `c` (content must be valid and have a map).
static func of(c: SiegeContent, state: SiegeState = null) -> SiegeCombatTable:
	var t := SiegeCombatTable.new()
	var n := SiegeIds.ENEMY_NAMES.size()
	t.hp.resize(n)
	t.armor.resize(n)
	t.speed.resize(n)
	t.gate_hp.resize(n)
	t.bounty.resize(n)
	t.threat.resize(n)
	for code in range(1, n):
		var d := c.enemy_def(code)
		t.hp[code] = float(d.get("hp", 1.0))
		t.armor[code] = float(d.get("armor", 0.0))
		t.speed[code] = float(d.get("speed_mps", 1.0))
		t.gate_hp[code] = float(d.get("gate_hp", 0.0))
		t.bounty[code] = float(d.get("bounty", 0.0))
		t.threat[code] = float(d.get("threat", 1.0))
	t.ram_dps = float(c.enemy_def(SiegeIds.ENEMY_RAM).get("gate_hp_per_s", 3.0))
	for road in c.map.road_count():
		t.road_len.append(c.map.road_length(road))
	t.lateral_m = float(c.enemies.get("lateral_m", 1.5))
	t.cap = int(c.enemies.get("cap", 150))
	t.retreat_s = float(c.enemies.get("retreat_s", 3.0))
	t.tower.append({})
	for code in range(1, SiegeIds.TOWER_NAMES.size()):
		t.tower.append(c.tower_def(code))
	t.ref_w = c.num("tower_ref_w", 250.0)
	t.m_cap = c.num("m_cap", 4.0)
	for u: Variant in c.towers.get("upgrades", []):
		if int(u.get("level", 0)) == 1:
			t.out_mult = float(u.get("mult", 1.4))
	t.hold_s = c.num("perks.reserve_hold_s", 10.0)
	t.aq_m = c.num("perks.aqueduct_m", 0.25)
	if state != null:
		t.reserve = state.perks.has(SiegeIds.PERK_RESERVE)
		t.aqueduct = state.perks.has(SiegeIds.PERK_AQUEDUCT)
	return t
