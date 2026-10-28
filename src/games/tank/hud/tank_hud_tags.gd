class_name TankHudTags
extends TankHudCtl
## The world tags (brief 3.6), drawn in the world rather than in panels: a Control over the middle
## of the canvas (TankHud.LAYOUT "tags", 852 x 480, which stays on screen on every canvas) that
## draws at canvas positions from TankHudGeom (the view's public API, else the state and the v3 kit)
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
##  - the turn marker at a map end (free roam; set_turn_marker());
##  - v3: the ready rack's three shells beside the elevation arc's label, and the Secondaries' small
##    cold blue-white dial past the bow guns' muzzles while their seat is manned and firing or a
##    target is in their reach (bow_elevation(), the guns' elevation, and their rounds a minute).
## Tags keep out of the plates (the mission plate and toasts, the hull and boss plates) and never lie
## on the hero: every tag stays TAG_CLEAR px outside the tank's drawn rects (TankHudGeom.tank_rects);
## a SURGE tag whose shooter is behind or under the tank moves above the hull's top (or onto the road
## below the tracks) with its pointer bent round the tank to the shooter; a pursuer that only shows a
## sliver at the screen's edge gets a small edge arrow on the road. refresh() lays them all out
## (m["layout"], tested for every variant, facing and travel direction) and paint() draws that.

const POST_H := 44.0
const PIN_MARGIN := 36.0
const TAG_LIFT := 10.0
const WARN_TRI := ["...#...", "..#.#..", "..#.#..", ".#.#.#.", ".#...#.", "#..#..#", "#######"]
const PIN_ARROW := ["#...", "##..", "###.", "####", "###.", "##..", "#..."]
const PIN_ARROW_L := ["...#", "..##", ".###", "####", ".###", "..##", "...#"]
## Every world tag keeps this far outside the tank's drawn rects (art px).
const TAG_CLEAR := 8.0
const WARN_H := 26.0
const SPEED_H := 17.0
const EDGE_ARROW := ["...#", "..##", ".###", "####", ".###", "..##", "...#"]
const EDGE_ARROW_R := ["#...", "##..", "###.", "####", "###.", "##..", "#..."]
## A pursuer showing less than this much of its sprite on the canvas gets an edge arrow (art px).
const SLIVER_PX := 48.0
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
	m["body"] = g.tank_rects()
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
	var edge: Array = []
	var cvx := float(canvas().x)
	for e in s.enemies:
		if e.mode == TankIds.EM_DEAD or e.side >= 0:
			continue
		var er := g.enemy_rect(e)
		if er.size == Vector2.ZERO:
			continue
		var shown := minf(er.end.x, cvx) - maxf(er.position.x, 0.0)
		if shown < SLIVER_PX:
			edge.append({"left": er.get_center().x < cvx * 0.5})
	m["edge"] = edge
	var laying := absf(h.elev_deg - h.elev_target_deg) > 0.5 or h.target_id != 0
	m["aim"] = laying and absf(h.elev_deg) >= 2.0 and not h.breakdown
	if bool(m["aim"]):
		var b := g.barrel()
		m["aim"] = not bool(b["turning"])
		m["barrel"] = b
		m["elev"] = h.elev_deg
		m["elev_to"] = h.elev_target_deg
	if turn_dir != 0:
		m["turn_x"] = g.world_x(turn_x)
	_feed_secondaries(s, g)
	m["layout"] = layout()


## Where every world tag goes this refresh (canvas art px), clear of the plates and of the tank:
## {speed: Rect2 (empty when standing), posts: [{x, plate, pinned, dir, title, value}], warn:
## [{rect, pointer (Array[Vector2i]), lx, up, w}], edge: [Vector2]}.
func layout() -> Dictionary:
	var cv := Vector2(canvas())
	var body: Array[Rect2] = []
	body.assign(m.get("body", []))
	var out := {"speed": Rect2(), "posts": [], "warn": [], "edge": []}
	var speed := Rect2()
	if float(m["speed"]) > 0.5:
		var txt := tx("TANK_HUD_SPEED", [roundi(float(m["speed"]))])
		speed = speed_rect(m["rear"], D.tall_w(txt) + 16.0, geom().mirrored(), body)
		out["speed"] = speed
	var gy := float(m["ground"])
	if float(m["halt_m"]) >= 0.0 and m.has("halt_x"):
		var title := tx("TANK_HUD_HALT_LINE")
		var value := "%d m" % ceili(float(m["halt_m"]))
		var pl := post_layout(float(m["halt_x"]), post_size(title, value), gy, cv, body)
		pl.merge({"dir": 1, "title": title, "value": value})
		out["posts"].append(pl)
	if m.has("turn_x"):
		var title2 := tx("TANK_HUD_TURN")
		var pl2 := post_layout(float(m["turn_x"]), post_size(title2, ""), gy, cv, body)
		pl2.merge({"dir": turn_dir, "title": title2, "value": ""})
		out["posts"].append(pl2)
	var keep := keep_out()
	if speed.size != Vector2.ZERO:
		keep.append(speed.grow(2))
	var wsize := Vector2(D.tall_w(tx("TANK_HUD_SURGE_TAG")) + 22.0, WARN_H)
	for w: Dictionary in m["warn"]:
		var wl := warn_layout(w["anchor"], wsize, cv, keep, body)
		wl["w"] = w
		out["warn"].append(wl)
		keep.append((wl["rect"] as Rect2).grow(2))
	var counts := {true: 0, false: 0}
	for ed: Dictionary in m.get("edge", []):
		var left := bool(ed["left"])
		var y := gy + TAG_CLEAR + 2.0 + float(counts[left]) * 9.0
		out["edge"].append(Vector2(4.0 if left else cv.x - 8.0, y))
		counts[left] = int(counts[left]) + 1
	return out


## True when `r` keeps TAG_CLEAR px clear of every rect of the tank's `body`.
static func clear_of(r: Rect2, body: Array[Rect2]) -> bool:
	for b in body:
		if r.intersects(b.grow(TAG_CLEAR)):
			return false
	return true


static func _union(body: Array[Rect2]) -> Rect2:
	var u := Rect2()
	for b in body:
		u = b if u.size == Vector2.ZERO else u.merge(b)
	return u


## The speed plate (canvas art px), `w` wide, under the hull's rear on the road, TAG_CLEAR below
## the tracks (it grows toward the tank while driving west).
static func speed_rect(rear: Vector2, w: float, mirrored: bool, body: Array[Rect2]) -> Rect2:
	var x := rear.x - 10.0
	if mirrored:
		x = rear.x + 10.0 - w
	var y := rear.y + 3.0
	var u := _union(body)
	if u.size != Vector2.ZERO:
		y = maxf(y, u.end.y + TAG_CLEAR)
	return Rect2(roundf(x), roundf(y), w, SPEED_H)


## A post's plate size for `title` and `value`.
static func post_size(title: String, value: String) -> Vector2:
	return Vector2(maxf(D.text_w(value, 2), D.tall_w(title)) + 10.0, 33.0 if value != "" else 18.0)


## The rect a striped post at canvas x `x` covers (its lamp's halo included), standing on `gy`.
static func post_rect(x: float, gy: float) -> Rect2:
	var top := gy - POST_H
	return Rect2(x - 4.0, top - 6.0, 11.0, gy + 4.0 - (top - 6.0))


## A striped post standing at canvas x `x` on the road (`gy`), its plate `size`: {x, plate, pinned}.
## Pinned to the canvas edge while beyond the screen; pushed out past the tank (TAG_CLEAR) when it
## would stand on it (the tank reaching its halt line); its plate on the post's left, else its
## right, whichever keeps clear of the tank.
static func post_layout(
	x: float, size: Vector2, gy: float, cv: Vector2, body: Array[Rect2]
) -> Dictionary:
	var pin_r := cv.x - PIN_MARGIN
	var pinned := x > pin_r or x < PIN_MARGIN
	x = roundf(clampf(x, PIN_MARGIN, pin_r))
	if not clear_of(post_rect(x, gy), body):
		var u := _union(body)
		var past := u.end.x + TAG_CLEAR + 5.0
		var before := u.position.x - TAG_CLEAR - 8.0
		# The nearer side of the tank, unless the post and its plate do not fit there.
		var near_right := x >= u.get_center().x or before - size.x - 6.0 < 4.0
		x = past if near_right and past + 9.0 + size.x <= cv.x - 4.0 else before
	var top := gy - POST_H
	var left := Rect2(x - size.x - 6.0, top - 8.0, size.x, size.y)
	var right := Rect2(x + 9.0, top - 8.0, size.x, size.y)
	var plate := left
	if left.position.x < 4.0 or not clear_of(left, body):
		plate = right
	return {"x": x, "plate": plate, "pinned": pinned}


## The SURGE tag for a shooter at `anchor` (canvas art px), `size` art px: {rect, pointer, lx, up}.
## Over the shooter by default, out of the plates `keep`; when that would touch the tank (`body`
## grown TAG_CLEAR), above the tank's top, else on the road below its tracks (`up`: its tip on top).
## The pointer runs from the tag's tip (at lx) to the shooter, bent round the tank (along a column
## clear of it, then across) and is never painted on the tank.
static func warn_layout(
	anchor: Vector2, size: Vector2, cv: Vector2, keep: Array[Rect2], body: Array[Rect2]
) -> Dictionary:
	var tw := size.x
	var th := size.y
	var tr := Rect2(roundf(anchor.x - tw * 0.5), roundf(anchor.y - th - TAG_LIFT), tw, th)
	tr.position.x = clampf(tr.position.x, 4.0, cv.x - 4.0 - tw)
	tr.position.y = maxf(tr.position.y, 4.0)
	tr = _out_of(tr, keep, cv)
	var up := false
	var u := _union(body)
	if not clear_of(tr, body):
		var above := Rect2(tr.position.x, u.position.y - TAG_CLEAR - th, tw, th)
		above = _out_of(above, keep, cv)
		if above.position.y >= 4.0 and clear_of(above, body):
			tr = above
		else:
			tr = Rect2(tr.position.x, u.end.y + TAG_CLEAR, tw, th)
			for k in keep:
				if tr.intersects(k):
					tr.position.x = minf(k.end.x + 2.0, cv.x - 4.0 - tw)
			up = true
	var lx := roundf(clampf(anchor.x, tr.position.x + 6.0, tr.end.x - 6.0))
	var from := Vector2(lx, tr.position.y - 4.0 if up else tr.end.y + 4.0)
	var to := anchor + Vector2(0, -3)
	var pts: Array[Vector2] = [from, to]
	if not _segment_clear(from, to, body):
		# Bend round the tank: across to a column clear of it, along it, then across to the shooter.
		var cx0 := u.position.x - TAG_CLEAR
		var cx1 := u.end.x + TAG_CLEAR
		var col := cx0 if absf(anchor.x - cx0) <= absf(anchor.x - cx1) else cx1
		if col < 1.0 or col > cv.x - 2.0:
			col = cx1 if col == cx0 else cx0
		col = clampf(col, 1.0, cv.x - 2.0)
		pts = [from, Vector2(col, from.y), Vector2(col, to.y), to]
	var pointer: Array[Vector2i] = []
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
		for j in range(0, steps + 1, 2):
			var p := a.lerp(b, float(j) / maxf(float(steps), 1.0)).round()
			if not _on_body(p, body):
				pointer.append(Vector2i(p))
	return {"rect": tr, "pointer": pointer, "lx": lx, "up": up}


## `tr` moved out of the plates `keep` (left of a plate on the right half, else under it).
static func _out_of(tr: Rect2, keep: Array[Rect2], cv: Vector2) -> Rect2:
	for k in keep:
		if tr.intersects(k):
			if k.get_center().x > cv.x * 0.5:
				tr.position.x = k.position.x - tr.size.x - 4.0
			else:
				tr.position.y = k.end.y + 2.0
	return tr


static func _on_body(p: Vector2, body: Array[Rect2]) -> bool:
	for b in body:
		if b.has_point(p + Vector2(0.5, 0.5)):
			return true
	return false


static func _segment_clear(a: Vector2, b: Vector2, body: Array[Rect2]) -> bool:
	var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
	for j in steps + 1:
		if _on_body(a.lerp(b, float(j) / maxf(float(steps), 1.0)).round(), body):
			return false
	return true


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
	var lay: Dictionary = m.get("layout", {})
	if lay.is_empty():
		return
	var sr: Rect2 = lay["speed"]
	if sr.size != Vector2.ZERO:
		_speed_tag(sr)
	for pl: Dictionary in lay["posts"]:
		_post(pl)
	for wl: Dictionary in lay["warn"]:
		_warn_tag(wl)
	for p: Vector2 in lay["edge"]:
		var left := p.x < float(canvas().x) * 0.5
		D.rect(self, Rect2(p + Vector2(-1, -1), Vector2(6, 9)), Color(D.PANEL, 0.8))
		D.pixels(self, EDGE_ARROW if left else EDGE_ARROW_R, p, Color(D.RED, 0.9))
	if bool(m["aim"]):
		_elev_arc()
	if m.has("sec"):
		_sec_arc()


## A small riveted plate standing on the road behind the rear track, the HUD's plate style with room
## round the text: the speed in the tall face, a drop shadow on the gravel and two iron legs; below
## the tracks, clear of the tank (speed_rect).
func _speed_tag(r: Rect2) -> void:
	var txt := tx("TANK_HUD_SPEED", [roundi(float(m["speed"]))])
	D.rect(self, Rect2(r.position + Vector2(2, r.size.y), Vector2(r.size.x - 2, 1)), D.SHADOW)
	for lx: float in [r.position.x + 5.0, r.end.x - 7.0]:
		D.rect(self, Rect2(lx, r.end.y, 2, 4), D.RIVET_LO)
		D.rect(self, Rect2(lx, r.end.y, 1, 4), D.FRAME_IN)
	D.plate(self, r, D.FRAME, 0)
	D.tall(self, r.position.x + 8, r.position.y + 4, txt, D.TEXT)


## A striped post (post_layout) with a lamp and its plate (`title`, `value` in the 2x face); an
## arrow while it is pinned to the canvas edge beyond the screen (`dir` the arrow's side).
func _post(pl: Dictionary) -> void:
	var x := float(pl["x"])
	var title := str(pl["title"])
	var value := str(pl["value"])
	var dir := int(pl["dir"])
	var pinned := bool(pl["pinned"])
	var gy := float(m["ground"])
	var top := gy - POST_H
	for y in range(int(top), int(gy + 2)):
		var band := posmod(int((y - top) / 4.0), 2) == 0
		D.rect(self, Rect2(x, y, 3, 1), D.AMBER if band else Color("#2a1f14"))
	D.rect(self, Rect2(x - 1, gy + 2, 5, 2), Color("#2a1f14"))
	D.rect(self, Rect2(x - 3, top - 3, 9, 3), D.FRAME)
	D.rect(self, Rect2(x - 4, top - 6, 11, 11), Color(D.AMBER, 0.12))
	D.rect(self, Rect2(x, top - 2, 3, 1), Color("#fff2c8"))
	var tr: Rect2 = pl["plate"]
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


## A SURGE tag laid out by warn_layout: the plate (blinking edge), the warning sign, the label, one
## pip per second of the telegraph, its tip and the dotted pointer to the shooter.
func _warn_tag(wl: Dictionary) -> void:
	var w: Dictionary = wl["w"]
	var tr: Rect2 = wl["rect"]
	var label := tx("TANK_HUD_SURGE_TAG")
	var blink := int(floorf(st().t * 4.0)) % 2 == 0
	var edge := D.RED if blink else D.FRAME_HI
	var lx := float(wl["lx"])
	for p: Vector2i in wl["pointer"]:
		D.rect(self, Rect2(Vector2(p), Vector2(1, 1)), Color(D.RED, 0.8))
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
		var y := tr.position.y - 1 - k if bool(wl["up"]) else tr.end.y + k
		D.rect(self, Rect2(lx - 3 + k, y, 7 - 2 * k, 1), edge)


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
		_rack_pips(lr, left)


## One arc pixel, only outside the tank's body (TankHudGeom.arc_px_ok).
func _arc_px(keep: Array, p: Vector2i, col: Color) -> void:
	if TankHudGeom.arc_px_ok(p, keep):
		D.rect(self, Rect2(Vector2(p), Vector2(1, 1)), col)


# --- v3: the ready rack by the gun's arc, the Secondaries' dial ----------------------------------------

const SEC_MIN := -10.0
const SEC_MAX := 35.0
const SEC_R := 19.0
const SEC_GAP := 7.0
const SEC_COL := Color("#d6ecff")
const SEC_DIM := Color(0.62, 0.78, 0.92, 0.5)
## The bow guns' reach ahead of their muzzles in rules px (TankFeedState: they fire at the nearest
## enemy 40-220 px ahead).
const SEC_REACH_PX := Vector2(40.0, 220.0)
const SHELL_PIP := [".#.", "###", "###", "###", "###", "###", "###"]


## The ready rack's three shells beside the elevation label (lit while in the rack).
func _rack_pips(lr: Rect2, left: bool) -> void:
	var rack := TankHudModel.rack(st())
	var x := lr.end.x + 4.0 if not left else lr.position.x - 19.0
	var p := Vector2(roundf(x), lr.position.y + 1.0)
	D.rect(self, Rect2(p - Vector2(2, 1), Vector2(19, 9)), Color(D.PANEL, 0.7))
	for i in TankConst.RACK_MAX:
		var col := D.BRASS.lightened(0.2) if i < rack else Color("#4a3e30")
		D.pixels(self, SHELL_PIP, p + Vector2(i * 5, 0), col)
		if i < rack:
			D.rect(self, Rect2(p + Vector2(i * 5 + 1, 0), Vector2(1, 1)), Color("#e07a3c"))


## The bow guns' elevation as the dial shows it: {deg (+ up, SEC_MIN..SEC_MAX), target (an enemy in
## their reach)}. SWITCH POINT for the lead: until the rules expose the bow guns' elevation, deg
## is the upper gun's bore as the view draws it (pivot to muzzle, which the view tilts toward the
## nearest enemy ahead), else (no view) the bore line from its pivot to the nearest live enemy
## SEC_REACH_PX ahead of the muzzles, level (0) with none. Once the state carries the elevation,
## return that instead and keep the signature.
static func bow_elevation(s: TankState, g: TankHudGeom) -> Dictionary:
	var piv := g.tank_point("bow_gun_upper_pivot")
	var mz := g.tank_point("bow_gun_upper_muzzle")
	var fwd := -1.0 if mz.x < piv.x else 1.0
	var px := absf(g.world_x(1000.0) - g.world_x(0.0)) / 1000.0
	var best := Rect2()
	var best_d := INF
	for e in s.enemies:
		if e.mode == TankIds.EM_DEAD or e.hp <= 0.0:
			continue
		var r := g.enemy_rect(e)
		if r.size == Vector2.ZERO:
			continue
		var near_x := r.position.x if fwd > 0.0 else r.end.x
		var ahead := (near_x - mz.x) * fwd
		if ahead < SEC_REACH_PX.x * px or ahead > SEC_REACH_PX.y * px or ahead >= best_d:
			continue
		best_d = ahead
		best = r
	var has := best.size != Vector2.ZERO
	var d := mz - piv
	if g.view == null:
		if not has:
			return {"deg": 0.0, "target": false}
		d = best.get_center() - piv
	return {"deg": clampf(rad_to_deg(atan2(-d.y, absf(d.x))), SEC_MIN, SEC_MAX), "target": has}


## The Secondaries' dial data while their seat is manned and the guns fire or have a target: the bow
## guns' pivot and length as drawn, their side, their elevation (bow_elevation()) and the rounds a
## minute (TankFeedState.rpm).
func _feed_secondaries(s: TankState, g: TankHudGeom) -> void:
	m.erase("sec")
	var fd := s.station(TankIds.ENGINE_FEED)
	if fd == null or fd.is_empty():
		return
	var be := bow_elevation(s, g)
	var rpm := TankHudModel.feed_rpm(s)
	if not bool(be["target"]) and rpm <= 0.0:
		return
	var piv := g.tank_point("bow_gun_upper_pivot")
	var mz := g.tank_point("bow_gun_upper_muzzle")
	m["sec"] = {
		"pivot": piv,
		"length": maxf(absf(mz.x - piv.x), 6.0),
		"left": mz.x < piv.x,
		"deg": float(be["deg"]),
		"rpm": rpm,
	}


## The secondaries' angle widget: a small cold blue-white dial (radius SEC_R, about a fifth of the
## main arc) standing just past the bow guns' muzzles and clear of the hull, its centre on their
## bore line: the reach (-10 .. +35 degrees) with a tick every 15 degrees, a faint level line, the
## needle at the guns' elevation, the degrees and the rounds a minute under it.
func _sec_arc() -> void:
	var sd: Dictionary = m["sec"]
	var left := bool(sd["left"])
	# the hull only: the turret's rect reaches over the barrel, which stands well above the dial
	var body: Array[Rect2] = []
	var rects: Array = m.get("body", [])
	if rects.size() > 1:
		body.append((rects[1] as Rect2).grow(2.0))
	var mz: Vector2 = sd["pivot"] + TankHudGeom.dir(0.0, left) * float(sd["length"])
	var c := Vector2(roundf(mz.x + (SEC_GAP if not left else -SEC_GAP)), roundf(mz.y))
	var tries := 0
	while tries < 30 and not _sec_clear(c, SEC_R + 2.0, left, body):
		c.x += -2.0 if left else 2.0
		tries += 1
	# the sector's faint fill and its two edges
	var a := SEC_MIN
	while a <= SEC_MAX + 0.001:
		for pf in TankHudGeom.tick_pixels(c, a, left, 1.0, SEC_R - 1.0):
			_arc_px(body, pf, Color(0.1, 0.16, 0.22, 0.35))
		a += 1.5
	for edge: float in [SEC_MIN, SEC_MAX]:
		for pe in TankHudGeom.tick_pixels(c, edge, left, 1.0, SEC_R):
			_arc_px(body, pe, Color(SEC_DIM, 0.35))
	a = SEC_MIN
	while a <= SEC_MAX + 0.001:
		var p := Vector2i((c + TankHudGeom.dir(a, left) * SEC_R).round())
		_arc_px(body, p, SEC_DIM)
		a += 0.75
	var t := SEC_MIN
	while t <= SEC_MAX + 0.001:
		for p2 in TankHudGeom.tick_pixels(c, t, left, SEC_R + 1.0, SEC_R + 2.0):
			_arc_px(body, p2, SEC_DIM)
		t += 15.0
	for p4 in TankHudGeom.tick_pixels(c, 0.0, left, SEC_R + 1.0, SEC_R + 3.0):
		_arc_px(body, p4, SEC_COL)
	var deg := float(sd["deg"])
	for p3 in TankHudGeom.tick_pixels(c, deg, left, 0.0, SEC_R + 4.0):
		_arc_px(body, p3, SEC_COL)
	var tip := c + TankHudGeom.dir(deg, left) * (SEC_R + 4.0)
	D.rect(self, Rect2(tip.round() - Vector2(1, 1), Vector2(3, 3)), SEC_COL)
	D.rect(self, Rect2(c - Vector2(1, 1), Vector2(3, 3)), SEC_COL)
	var e := roundi(deg)
	var lab := ("+" if e > 0 else "") + str(e) + "°"
	var mid := c + TankHudGeom.dir(SEC_MIN, left) * (SEC_R + 4.0)
	var x := mid.x + 2.0 if not left else mid.x - 2.0 - D.text_w(lab)
	D.text_shadow(self, roundf(x), roundf(mid.y - 1.0), lab, SEC_COL)
	var rpm := tx("TANK_HUD_PER_MIN", [roundi(float(sd["rpm"]))])
	D.text_shadow(self, roundf(x), roundf(mid.y + 8.0), rpm, SEC_DIM)


func _sec_clear(piv: Vector2, radius: float, left: bool, body: Array[Rect2]) -> bool:
	if not TankHudGeom.arc_px_ok(Vector2i(piv), body):
		return false
	var a := SEC_MIN
	while a <= SEC_MAX + 0.001:
		var p := Vector2i((piv + TankHudGeom.dir(a, left) * radius).round())
		if not TankHudGeom.arc_px_ok(p, body):
			return false
		a += 2.0
	return true
