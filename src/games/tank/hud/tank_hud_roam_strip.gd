class_name TankHudRoamStrip
extends TankHudCtl
## The free-roam map strip across the top (brief 2.10, 3.6; TankHud.LAYOUT "roam_strip", in place
## of the mission plate): the valley road in profile on an iron plate (its zones, named from the
## content: each zone's label key in roam/valley.json, else its id; v3: forest variants and base
## clearings, tinted by zone_color(); the terrain line), the turning places at both ends hatched,
## patrols as
## red diamonds, strongpoints as squares (crossed out while down), and the tank with its travel
## direction and the bracket of what the screen shows. It draws only what its setters gave it;
## refresh() feeds them from the state (feed(): the map once its seed is known, the tank, the patrols
## and the strongpoints every frame).

const ZONE_COL := {
	"forest": Color("#2f3a26"),
	"lake": Color("#2e4a5a"),
	"village": Color("#8a6a3a"),
	"quarry": Color("#4a3f2e"),
	"meadow": Color("#4a5a2e"),
}
## v3 zones the table above does not name: a base clearing (an id with one of CLEARING_WORDS) is
## lamp-lit earth, anything else a forest variant in one of the FOREST_TONES (picked by its id).
const CLEARING_WORDS: Array[String] = ["base", "clearing", "camp", "depot", "strong"]
const CLEARING_COL := Color("#6a5232")
const FOREST_TONES: Array[Color] = [
	Color("#2f3a26"), Color("#26382e"), Color("#36402a"), Color("#2a3330")
]
const DIAMOND := ["..#..", ".###.", "#####", ".###.", "..#.."]
const SQUARE := ["#####", "#...#", "#...#", "#...#", "#####"]
const TANK_R := ["..##....", ".#####..", "########", "########", ".######."]
const TANK_L := ["....##..", "..#####.", "########", "########", ".######."]
const LABEL_W := 58.0
const END_W := 6.0
## The contacts' row: this far above the map's base line (the terrain line's row, below the names).
const MARK_LIFT := 9.0

## The map: its length (m), zones [{id, from_m, to_m, label (a string key, optional)}] and the
## terrain profile (heights 0..1 at even steps along the map).
var length_m: float = 0.0
var zones: Array = []
var profile: PackedFloat32Array = PackedFloat32Array()
## The tank: where it is (m), which way it drives (-1 / +1) and how many metres the screen shows.
var tank_m: float = 0.0
var tank_dir: int = 1
var view_m: float = 80.0
## Patrols (their positions, m) and strongpoints [{at_m, alive}].
var patrols: PackedFloat32Array = PackedFloat32Array()
var strongpoints: Array = []
## The title (e.g. "ROAM") and its second line (e.g. "30 min").
var title: String = ""
var subtitle: String = ""

## The map's seed the strip was last given (0: none).
var map_seed: int = 0


func refresh() -> void:
	if game != null and game.state != null:
		feed(game.state)


## Feeds the setters from `s` (free roam only): the map once, the tank, the contacts and the title.
func feed(s: TankState) -> void:
	if not s.roam.active or s.roam_map == null:
		return
	var map := s.roam_map
	if map.map_seed != map_seed:
		map_seed = map.map_seed
		set_map(map.length_m, map.zones, map.profile(96))
	set_tank(s.roam.map_m, s.hull.dir, float(TankConst.SCREEN_W) / TankConst.PX_PER_M)
	var pats := PackedFloat32Array()
	var aux_strong := s.roam.strong_id
	for e in s.enemies:
		if e.hp > 0.0 and not aux_strong.has(e.id) and e.mode != TankIds.EM_LEAVE:
			pats.append(TankRoam.map_of(s, e.x_px + float(e.w) * 0.5))
	var sps: Array = []
	for i in map.strongpoints.size():
		sps.append({"at_m": map.strongpoints[i], "alive": not s.roam.strong_down(i)})
	set_contacts(pats, sps)
	var mins := s.content.roam_minutes() if s.content != null else 0
	var sub := tx("TANK_HUD_ROAM_MIN", [mins])
	if s.roam.engaging:
		sub = tx("TANK_HUD_ENGAGE")
	elif s.seg.seg == TankIds.SEG_DEPOT:
		sub = tx("TANK_HUD_DRIVE_OUT")
	set_title(tx("TANK_HUD_ROAM"), sub)


func set_map(p_length_m: float, p_zones: Array, p_profile: PackedFloat32Array) -> void:
	length_m = maxf(p_length_m, 0.0)
	zones = p_zones.duplicate(true)
	profile = p_profile


func set_tank(at_m: float, dir: int, p_view_m: float) -> void:
	tank_m = at_m
	tank_dir = -1 if dir < 0 else 1
	view_m = maxf(p_view_m, 0.0)


func set_contacts(p_patrols: PackedFloat32Array, p_strongpoints: Array) -> void:
	patrols = p_patrols
	strongpoints = p_strongpoints.duplicate(true)


func set_title(p_title: String, p_subtitle: String) -> void:
	title = p_title
	subtitle = p_subtitle


## It draws from its setters, not from the state.
func has_state() -> bool:
	return true


## The map's rect in art px of the strip.
func map_rect() -> Rect2:
	return Rect2(LABEL_W + 6.0, 6, float(art_rect.size.x) - LABEL_W - 12.0, art_rect.size.y - 12)


## The top of the contacts' markers (5 px tall, on a 7 px backing from one row above).
func marker_y() -> float:
	return map_rect().end.y - 6.0 - MARK_LIFT


## The screen's bracket on the map (art px of the strip): the stretch of road on screen, from just
## under the zone names to the map's foot.
func view_box() -> Rect2:
	var map := map_rect()
	var tx0 := mx(tank_m)
	var bw := 14.0
	if length_m > 0.0:
		bw = maxf(roundf((map.size.x - 2.0 * END_W) * view_m / length_m), 14.0)
	var bx := tx0 - 3.0 if tank_dir > 0 else tx0 - bw + 3.0
	var top := label_rows().y + 1.0
	return Rect2(bx, top, bw, map.end.y - 1.0 - top)


## The zone names' rows: from their top to the tall face's full height.
func label_rows() -> Vector2:
	var top := map_rect().position.y + 2.0
	return Vector2(top, top + D.TALL_H)


## The strip x of `metres` along the map.
func mx(metres: float) -> float:
	var r := map_rect()
	var k := clampf(metres / length_m, 0.0, 1.0) if length_m > 0.0 else 0.0
	return roundf(r.position.x + END_W + (r.size.x - 2.0 * END_W) * k)


func paint() -> void:
	var w := float(art_rect.size.x)
	var h := float(art_rect.size.y)
	D.plate(self, Rect2(0, 0, w, h))
	D.tall(self, 6, 5, D.fit_tall(title, LABEL_W - 2.0), D.AMBER)
	D.tall(self, 6, 18, D.fit_tall(subtitle, LABEL_W - 2.0), D.DIM)
	var map := map_rect()
	D.rect(self, map, Color("#0e0c09"))
	if length_m <= 0.0:
		return
	var base := map.end.y - 6.0
	for z: Dictionary in zones:
		var a := mx(float(z.get("from_m", 0.0)))
		var b := mx(float(z.get("to_m", 0.0)))
		var col := zone_color(str(z.get("id", "")))
		D.rect(
			self, Rect2(a, map.position.y + 1, maxf(b - a, 1.0), map.size.y - 2), col.darkened(0.55)
		)
		var label := zone_name(z)
		if label != "" and b - a > 24.0:
			D.tall_c(self, (a + b) * 0.5, map.position.y + 2, D.fit_tall(label, b - a - 2.0), D.DIM)
	_terrain(map, base)
	for side in 2:
		var ex := map.position.x if side == 0 else map.end.x - END_W
		D.rect(self, Rect2(ex, map.position.y, END_W, map.size.y), Color("#3a1a12"))
		for y in range(int(map.position.y), int(map.end.y)):
			D.rect(self, Rect2(ex + posmod(y, int(END_W)), y, 1, 1), D.RED)
	# Contacts sit on the terrain line's row, under the zone names (never on them), each on a dark
	# backing so the line does not run through it.
	var my := marker_y()
	for sp: Dictionary in strongpoints:
		var sx := mx(float(sp.get("at_m", 0.0))) - 2.0
		var alive := bool(sp.get("alive", true))
		D.rect(self, Rect2(sx - 1.0, my - 1.0, 7, 7), Color("#0e0c09"))
		D.pixels(self, SQUARE, Vector2(sx, my), D.OVER if alive else D.DIM)
	for p in patrols:
		D.rect(self, Rect2(mx(p) - 3.0, my - 1.0, 7, 7), Color("#0e0c09"))
		D.pixels(self, DIAMOND, Vector2(mx(p) - 2.0, my), D.RED)
	var tx0 := mx(tank_m)
	# The screen's bracket: open at the top, under the zone names (never across them).
	var vb := view_box()
	var bc := Color(D.TEXT, 0.8)
	D.rect(self, Rect2(vb.position.x, vb.end.y - 1, vb.size.x, 1), bc)
	D.rect(self, Rect2(vb.position.x, vb.position.y, 1, vb.size.y), bc)
	D.rect(self, Rect2(vb.end.x - 1, vb.position.y, 1, vb.size.y), bc)
	var icon := TANK_R if tank_dir > 0 else TANK_L
	D.pixels(self, icon, Vector2(tx0 - 4.0, base - 9), D.AMBER)


## A zone's tint on the strip: ZONE_COL's for the v2 ids, a lamp-lit earth for a base clearing, a
## forest tone for any other (v3 forest variants), the same for the same id every time.
static func zone_color(id: String) -> Color:
	if ZONE_COL.has(id):
		return ZONE_COL[id]
	for w in CLEARING_WORDS:
		if id.contains(w):
			return CLEARING_COL
	return FOREST_TONES[posmod(id.hash(), FOREST_TONES.size())]


## A zone's name on the strip, from the content: its label key translated (the game's strings),
## else (no label, or a key with no string yet) its id in words.
func zone_name(z: Dictionary) -> String:
	var key := str(z.get("label", ""))
	if key != "":
		var t := tx(key)
		if t != "" and t != key:
			return t
	var id := str(z.get("id", ""))
	return id.replace("_", " ").capitalize() if id != "" else ""


func _terrain(map: Rect2, base: float) -> void:
	var n := profile.size()
	for x in range(int(map.position.x + END_W), int(map.end.x - END_W)):
		var hgt := 3.0
		if n > 1:
			var k := (x - map.position.x - END_W) / maxf(map.size.x - 2.0 * END_W, 1.0)
			var f := k * float(n - 1)
			var i := clampi(floori(f), 0, n - 2)
			hgt = 2.0 + 8.0 * lerpf(profile[i], profile[i + 1], f - float(i))
		var gy := roundf(base - hgt)
		D.rect(self, Rect2(x, gy, 1, 1), D.FRAME)
		D.rect(self, Rect2(x, gy + 1, 1, map.end.y - gy - 1), Color("#1d1912"))
