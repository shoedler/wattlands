class_name TankHudTags
extends TankHudCtl
## The world tags (brief 3.6), drawn in the world rather than in panels: a Control over the middle
## of the canvas (TankHud.LAYOUT "tags", 852 x 480, which stays on screen on every canvas) that
## draws at canvas positions from TankHudGeom (the view's public API, else the state and kit.json)
## and may reach past its own rect to the canvas edges:
##  - the speed tag on the road behind the tank ("23 km/h");
##  - the halt line in an Advance: a striped post where the line is with its distance on a plate,
##    pinned to the right edge with an arrow while the line is still beyond the screen;
##  - SURGE TO EVADE over every shooter whose gun telegraphs (and over the Behemoth's main gun),
##    with one pip per second of the telegraph, emptying as it runs out; every peer shows it;
##  - the gun's elevation as a thin arc round the barrel's pivot while the gunner aims (a target,
##    a gun line or the boss), drawn beyond the muzzle so the barrel never hides it: the reach
##    (-12 .. +30 degrees), a tick per 10 degrees, the barrel's elevation lit where the barrel
##    points, the ordered elevation marked outside, and the degrees past the upper end;
##  - the turn marker at a map end (free roam; set_turn_marker()).
## Tags keep out of the plates (the mission plate and toasts, the hull and boss plates).

const POST_H := 44.0
const PIN_MARGIN := 36.0
const TAG_LIFT := 10.0
const WARN_TRI := ["...#...", "..#.#..", "..#.#..", ".#.#.#.", ".#...#.", "#..#..#", "#######"]
const PIN_ARROW := ["#...", "##..", "###.", "####", "###.", "##..", "#..."]
const PIN_ARROW_L := ["...#", "..##", ".###", "####", ".###", "..##", "...#"]
## Free roam: the turn marker shows once the turning place ahead is this near (game metres).
const TURN_MARKER_M := 160.0

var m: Dictionary = {}
## The turn marker (free roam): world x in rules px and the direction it turns the tank to
## (-1 left, +1 right); 0 = none.
var turn_x: float = 0.0
var turn_dir: int = 0
var _view: Object = null
var _view_tries: int = 0


## Shows the turn marker at world x `world_x_px` (rules px), pointing `dir` (-1 / +1).
func set_turn_marker(world_x_px: float, dir: int) -> void:
	turn_x = world_x_px
	turn_dir = signi(dir)


func clear_turn_marker() -> void:
	turn_dir = 0


## The view with the HUD API (TankHudGeom), or null.
func find_view() -> Object:
	if _view != null and is_instance_valid(_view):
		return _view
	_view = null
	if game != null and game.has_meta(TankHudGeom.VIEW_META):
		var v: Variant = game.get_meta(TankHudGeom.VIEW_META)
		if v is Object and is_instance_valid(v):
			_view = v
			return _view
	_view_tries += 1
	if _view_tries % 30 != 1 or not is_inside_tree():
		return null
	for n in get_tree().root.find_children("*", "Node2D", true, false):
		if n.has_method("hud_world_x"):
			_view = n
			break
	return _view


func geom() -> TankHudGeom:
	return TankHudGeom.make(st(), find_view())


func refresh() -> void:
	var s := st()
	_feed_turn(s)
	var g := geom()
	var h := s.hull
	m = {"speed": h.speed_mps * 3.6, "rear": g.tank_point("rear"), "ground": g.ground_y()}
	var halt := TankHudModel.halt_distance_m(s)
	m["halt_m"] = halt
	if halt >= 0.0:
		m["halt_x"] = g.world_x(h.x_px + float(h.hull_w) + TankConst.m_to_px(halt))
	var warn: Array = []
	for t: Dictionary in TankHudModel.telegraphs(s):
		var anchor := Vector2.ZERO
		if bool(t["boss"]):
			var br := g.boss_rect()
			anchor = br.position + Vector2(14, br.size.y * 0.27)
		else:
			var e := s.enemy(int(t["id"]))
			var r := g.enemy_rect(e) if e != null else Rect2()
			if r.size == Vector2.ZERO:
				continue
			anchor = Vector2(r.position.x + r.size.x * 0.5, r.position.y)
		warn.append({"anchor": anchor, "left": t["left"], "total": t["total"]})
	m["warn"] = warn
	var laying := absf(h.elev_deg - h.elev_target_deg) > 0.5 or h.target_id != 0
	m["aim"] = laying and absf(h.elev_deg) >= 2.0 and not h.breakdown
	if bool(m["aim"]):
		var b := g.barrel()
		m["aim"] = not bool(b["turning"])
		m["barrel"] = b
		m["body"] = g.tank_rects()
		m["elev"] = h.elev_deg
		m["elev_to"] = h.elev_target_deg
	if turn_dir != 0:
		m["turn_x"] = g.world_x(turn_x)


## Free roam: the turn marker at the turning place ahead while it is within TURN_MARKER_M of the
## hull (pointing back the way the tank will drive after its turn), cleared otherwise.
func _feed_turn(s: TankState) -> void:
	if not s.roam.active:
		return
	if s.roam_map == null or s.roam.turn_s > 0.0:
		clear_turn_marker()
		return
	var ahead := TankRoam.road_ahead_m(s)
	if ahead > TURN_MARKER_M:
		clear_turn_marker()
		return
	var end_m := s.roam_map.length_m if s.hull.dir > 0 else 0.0
	var at := end_m - float(s.hull.dir) * TankWorldDraw.TURN_BARRIER_M
	set_turn_marker(TankRoam.travel_x(s, at), 1 if geom().mirrored() else -1)


## The canvas-to-local offset (this Control's rect on the canvas).
func origin() -> Vector2:
	return Vector2(canvas_rect().position)


func paint() -> void:
	if m.is_empty():
		return
	var o := origin()
	draw_set_transform(-o * u(), 0.0, Vector2(u(), u()))
	if float(m["speed"]) > 0.5:
		_speed_tag()
	if float(m["halt_m"]) >= 0.0 and m.has("halt_x"):
		_post(float(m["halt_x"]), tx("TANK_HUD_HALT_LINE"), "%d m" % ceili(float(m["halt_m"])), 1)
	if m.has("turn_x"):
		_post(float(m["turn_x"]), tx("TANK_HUD_TURN"), "", turn_dir)
	for w: Dictionary in m["warn"]:
		_warn_tag(w)
	if bool(m["aim"]):
		_elev_arc()


## A small riveted plate standing on the road behind the rear track, the HUD's plate style with room
## round the text: the speed in the tall face, a drop shadow on the gravel and two iron legs.
func _speed_tag() -> void:
	var p: Vector2 = m["rear"]
	var txt := tx("TANK_HUD_SPEED", [roundi(float(m["speed"]))])
	var w := D.tall_w(txt) + 16.0
	var x := p.x - 10.0
	if geom().mirrored():
		# Driving west the hull's rear is on the right: the plate grows toward the tank.
		x = p.x + 10.0 - w
	var r := Rect2(roundf(x), roundf(p.y + 3), w, 17)
	D.rect(self, Rect2(r.position + Vector2(2, r.size.y), Vector2(r.size.x - 2, 1)), D.SHADOW)
	for lx: float in [r.position.x + 5.0, r.end.x - 7.0]:
		D.rect(self, Rect2(lx, r.end.y, 2, 4), D.RIVET_LO)
		D.rect(self, Rect2(lx, r.end.y, 1, 4), D.FRAME_IN)
	D.plate(self, r, D.FRAME, 0)
	D.tall(self, r.position.x + 8, r.position.y + 4, txt, D.TEXT)


## A striped post at canvas x `x` with a lamp and a plate (`title`, `value` in the 2x face); pinned
## to the canvas edge with an arrow while it is beyond the screen (`dir` the arrow's side).
func _post(x: float, title: String, value: String, dir: int) -> void:
	var cv := canvas()
	var gy := float(m["ground"])
	var pin_r := float(cv.x) - PIN_MARGIN
	var pinned := x > pin_r or x < PIN_MARGIN
	x = roundf(clampf(x, PIN_MARGIN, pin_r))
	var top := gy - POST_H
	for y in range(int(top), int(gy + 2)):
		var band := posmod(int((y - top) / 4.0), 2) == 0
		D.rect(self, Rect2(x, y, 3, 1), D.AMBER if band else Color("#2a1f14"))
	D.rect(self, Rect2(x - 1, gy + 2, 5, 2), Color("#2a1f14"))
	D.rect(self, Rect2(x - 3, top - 3, 9, 3), D.FRAME)
	D.rect(self, Rect2(x - 4, top - 6, 11, 11), Color(D.AMBER, 0.12))
	D.rect(self, Rect2(x, top - 2, 3, 1), Color("#fff2c8"))
	var tw := maxf(D.text_w(value, 2), D.tall_w(title)) + 10.0
	var th := 33.0 if value != "" else 18.0
	var on_left := x - tw - 6.0 >= 4.0
	var px := x - tw - 6.0 if on_left else x + 9.0
	var tr := Rect2(px, top - 8, tw, th)
	D.plate(self, tr, D.FRAME, 0)
	D.tall(self, tr.position.x + 5, tr.position.y + 4, title, D.DIM)
	if value != "":
		D.text(self, tr.position.x + 5, tr.position.y + 16, value, D.NUM, 2)
	if pinned or dir < 0:
		var arrow := PIN_ARROW if dir >= 0 else PIN_ARROW_L
		var ax := x + 8.0 if dir >= 0 else x - 8.0
		D.pixels(self, arrow, Vector2(ax, top + 6), D.AMBER)


## The plates a world tag keeps out of, on the canvas.
func keep_out() -> Array[Rect2]:
	var cv := canvas()
	var out: Array[Rect2] = []
	for key: String in ["mission", "toasts", "hull", "boss"]:
		out.append(Rect2(TankHud.anchored(TankHud.LAYOUT[key], cv)).grow(2))
	return out


func _warn_tag(w: Dictionary) -> void:
	var cv := canvas()
	var anchor: Vector2 = w["anchor"]
	var label := tx("TANK_HUD_SURGE_TAG")
	var tw := D.tall_w(label) + 22.0
	var th := 26.0
	var tr := Rect2(roundf(anchor.x - tw * 0.5), roundf(anchor.y - th - TAG_LIFT), tw, th)
	tr.position.x = clampf(tr.position.x, 4.0, float(cv.x) - 4.0 - tw)
	tr.position.y = maxf(tr.position.y, 4.0)
	for k in keep_out():
		if tr.intersects(k):
			if k.get_center().x > float(cv.x) * 0.5:
				tr.position.x = k.position.x - tw - 4.0
			else:
				tr.position.y = k.end.y + 2.0
	var blink := int(floorf(st().t * 4.0)) % 2 == 0
	var edge := D.RED if blink else D.FRAME_HI
	var lx := roundf(clampf(anchor.x, tr.position.x + 6.0, tr.end.x - 6.0))
	var from := Vector2(lx, tr.end.y + 3.0)
	var to := anchor + Vector2(0, -3)
	var steps := int(maxf(absf(to.x - from.x), absf(to.y - from.y)))
	for i in range(0, steps, 2):
		var p := from.lerp(to, float(i) / maxf(float(steps), 1.0)).round()
		D.rect(self, Rect2(p, Vector2(1, 1)), Color(D.RED, 0.8))
	D.plate(self, tr, edge, 0)
	D.pixels(self, WARN_TRI, tr.position + Vector2(5, 4), D.RED)
	D.tall(self, tr.position.x + 15, tr.position.y + 4, label, D.TEXT)
	var n := maxi(ceili(float(w["total"])), 1)
	var lit := clampi(ceili(float(w["left"])), 0, n)
	var pw := 5.0
	var px := roundf(tr.position.x + (tr.size.x - n * (pw + 2) + 2) * 0.5)
	for i in n:
		var col := D.RED if i < lit else D.TRACK
		D.rect(self, Rect2(px + i * (pw + 2), tr.position.y + 17, pw, 4), col)
	for k in 4:
		D.rect(self, Rect2(lx - 3 + k, tr.end.y + k, 7 - 2 * k, 1), edge)


## The elevation arc beyond the muzzle of the barrel as drawn (TankHudGeom's pure geometry, tested
## clear of the barrel and of the tank's body for every variant, facing and elevation).
func _elev_arc() -> void:
	var b: Dictionary = m["barrel"]
	var piv: Vector2 = b["pivot"]
	var left := bool(b["left"])
	var ev := float(m["elev"])
	var e := roundi(ev)
	var lab := ("+" if e > 0 else "") + str(e) + "°"
	var body: Array[Rect2] = []
	body.assign(m.get("body", []))
	var lay := TankHudGeom.arc_layout(b, Vector2(D.tall_w(lab), D.TALL_CAP), body)
	var radius := float(lay["radius"])
	var keep: Array = lay["keep_out"]
	var col := Color(D.AMBER, 0.6)
	for p in TankHudGeom.arc_pixels(piv, radius, left):
		_arc_px(keep, p, col)
	var deg := TankHudGeom.ELEV_MIN + 2.0
	while deg <= TankHudGeom.ELEV_MAX:
		for p in TankHudGeom.tick_pixels(piv, deg, left, radius + 1.0, radius + 2.0):
			_arc_px(keep, p, col)
		deg += 10.0
	var to := float(m["elev_to"])
	for p in TankHudGeom.tick_pixels(piv, to, left, radius + 3.0, radius + 6.0):
		_arc_px(keep, p, D.COOL)
	for p in TankHudGeom.tick_pixels(piv, ev, left, radius - 2.0, radius + 3.0):
		_arc_px(keep, p, D.AMBER)
	var lr: Rect2 = lay["label"]
	if lr.size != Vector2.ZERO:
		D.tall_shadow(self, lr.position.x, lr.position.y, lab, D.AMBER)


## One arc pixel, only outside the tank's body (TankHudGeom.arc_px_ok).
func _arc_px(keep: Array, p: Vector2i, col: Color) -> void:
	if TankHudGeom.arc_px_ok(p, keep):
		D.rect(self, Rect2(Vector2(p), Vector2(1, 1)), col)
