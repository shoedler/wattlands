class_name SiegeV2Crowd
extends SiegeDepthBatch
## The attackers from plain arrays, in one depth-tested batch: up to MAX_ENEMIES bodies, each a
## ground shadow and a baked frame chosen by type, facing and walk phase, lit by the sun at its
## feet, and an hp bar over the siege engines. Types as SiegeIds: 1 spearman, 2 shield bearer,
## 3 chariot, 4 battering ram, 5 siege tower; and the view's own 6 worker and 7 hauler (the fort's
## people marching home). Enemy state 3 (EN_DOCKED) shows a docked tower.

const MAX_ENEMIES := 150
const TYPE_SPEAR := 1
const TYPE_SHIELD := 2
const TYPE_CHARIOT := 3
const TYPE_RAM := 4
const TYPE_TOWER := 5
const TYPE_WORKER := 6
const TYPE_HAULER := 7
const ST_DOCKED := 3
const PARTS := ["", "spear", "shield", "chariot", "ram", "tower", "walker", "hauler"]
const SHADOWS := [
	"",
	"shadow_person",
	"shadow_person",
	"shadow_chariot",
	"shadow_ram",
	"shadow_tower",
	"shadow_person",
	"shadow_person",
]
const HP_BAR_W := 9
## Height of an engine's hp bar over its feet (m).
const HP_BAR_Z := [0.0, 0.0, 0.0, 0.0, 5.5, 17.5, 0.0, 0.0]

## Bodies drawn by the last set_enemies (at most MAX_ENEMIES).
var drawn: int = 0

var _px_hp_back: int = -1
var _px_hp_fill: int = -1
var _px_hp_low: int = -1


func _ready() -> void:
	super._ready()
	var names: Array = bank.layout("px").get("names", [])
	_px_hp_back = names.find("hp_back")
	_px_hp_fill = names.find("hp_fill")
	_px_hp_low = names.find("hp_low")


## Rebuilds the batch. Arrays are parallel, one entry per enemy: type, world position (feet),
## travel yaw in degrees (atan2(dy, dx)), walk phase 0..1 (any real; frames repeat every 1),
## hp fraction 0..1, and optionally the SiegeIds.EN_* state.
func set_enemies(
	types: PackedInt32Array,
	positions: PackedVector3Array,
	facing_deg: PackedFloat32Array,
	walk: PackedFloat32Array,
	hp: PackedFloat32Array,
	states: PackedInt32Array = PackedInt32Array()
) -> void:
	begin()
	drawn = 0
	var n := mini(mini(types.size(), positions.size()), MAX_ENEMIES)
	for i in n:
		var t := types[i]
		if t < TYPE_SPEAR or t > TYPE_HAULER:
			continue
		var p := positions[i]
		var yaw := deg_to_rad(facing_deg[i]) if i < facing_deg.size() else 0.0
		var ph := walk[i] if i < walk.size() else 0.0
		var st := states[i] if i < states.size() else 0
		var shade := bank.sun_at(bank.art_pixel(p))
		add(SHADOWS[t], 0, p, 0, 1.0, 1.0, SiegeBakeBank.depth_of(p) - 0.5)
		var part: String = PARTS[t]
		if t == TYPE_TOWER and st == ST_DOCKED:
			part = "tower_dock"
		add(part, frame_for(t, yaw, ph), p, 0, shade)
		if (t == TYPE_RAM or t == TYPE_TOWER) and i < hp.size() and hp[i] < 0.999:
			_hp_bar(p + Vector3(0, 0, HP_BAR_Z[t]), clampf(hp[i], 0.0, 1.0))
		drawn += 1
	commit()


## The frame index of an enemy type facing world yaw `yaw` (radians) at walk phase `ph`.
static func frame_for(t: int, yaw: float, ph: float) -> int:
	var walk := posmod(floori(ph * 4.0), 4)
	var dx := cos(yaw)
	var dy := sin(yaw)
	# the travel direction on screen: x right, y down
	var sx := dx - dy
	var sy := (dx + dy) * 0.5
	match t:
		TYPE_SPEAR, TYPE_SHIELD, TYPE_WORKER, TYPE_HAULER:
			return (0 if sx >= 0.0 else 4) + walk
		TYPE_CHARIOT:
			var face := 0 if sx >= 0.0 else 1
			if absf(sy) > absf(sx) * 1.2:
				face = 2 if sy > 0.0 else 3
			return face * 4 + walk
		_:
			return posmod(roundi(yaw / (PI / 4.0)), 8)


func _hp_bar(at: Vector3, f: float) -> void:
	var px := bank.art_pixel(at)
	var d := SiegeBakeBank.depth_of(at) + 40.0
	var x0 := px.x - HP_BAR_W / 2
	add_px(_px_hp_back, Vector2i(x0 - 1, px.y - 1), d, 1.0, Vector2i(HP_BAR_W + 2, 3))
	var w := maxi(roundi(f * HP_BAR_W), 1)
	add_px(_px_hp_fill if f > 0.35 else _px_hp_low, Vector2i(x0, px.y), d, 1.0, Vector2i(w, 1))
