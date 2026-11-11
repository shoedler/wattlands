class_name TankHudTags
extends TankHudCtl
## The world tags (brief 3.6), drawn in the world rather than in panels: a Control over the middle
## of the canvas (TankHud.LAYOUT "tags", 852 x 480, which stays on screen on every canvas) that
## draws at canvas positions from TankHudGeom (the view's public API, else the state and the v3 kit)
## and may reach past its own rect to the canvas edges:
##  - the speed tag on the road behind the tank ("23 km/h");
##  - the halt line in an Advance: a striped post where the line is with its distance on a plate,
##    pinned to the near panel's edge with an arrow while the line is still beyond it. While a near threat
##    lives the road lane is the threat's: the plate lifts over the beam, the post stands behind the threat,
##    and a pinned line has no post at all, its plate and arrow say it;
##  - one SURGE TO EVADE instruction with its pips, emptying as they run out, on every peer: beside the
##    seam's range plate while an evadable shell flies (pips of its flight left), else over the shooter who
##    fires soonest (one pip per second of its telegraph), its leader running down to the muzzle; every
##    other shooter a small red tick over its muzzle;
##  - the gun's elevation as a thin arc round the barrel's pivot while the gunner aims (a target,
##    a gun line or the boss), drawn beyond the muzzle so the barrel never hides it: the reach
##    (-12 .. +30 degrees), a tick per 10 degrees, the barrel's elevation lit where the barrel
##    points, the ordered elevation marked outside, and the degrees past the upper end;
##  - the turn marker at a map end (free roam; set_turn_marker());
##  - v3: the ready rack's three shells beside the elevation arc's label, and the Secondaries' small
##    cold blue-white dial past the bow guns' muzzles while their seat is manned and a near threat
##    is alive (bow_elevation(), the guns' elevation, and their rounds a minute).
## Tags keep out of the plates (the mission plate and toasts, the hull and boss plates, the PiP), stay
## in their own panel, and never lie on the hero: every tag stays TAG_CLEAR px outside the tank's drawn
## rects (TankHudGeom.tank_rects). refresh() lays them all out (m["layout"], tested for every crew and
## travel direction) and paint() draws that.
## The two angle meters (the gun's arc, the Secondaries' dial) fade in over DIAL_IN_S and, once their
## show condition ends, hold DIAL_HOLD_S before fading out over DIAL_OUT_S (dial_fade(); tank 0.3.1:
## they no longer flash when the condition toggles).

const POST_H := 44.0
## A post's plate: its bottom this far over the road line, above the headlight's beam and the near threats' lane.
const PLATE_LIFT := 95.0
## The tick that marks a shooter with no plate of its own, its size, and the chevron it draws.
const TICK_SIZE := Vector2(9, 6)
const TICK := ["#########", ".#######.", "..#####..", "...###...", "....#....", "....#...."]
## Clear air between the seam's range plate and the instruction beside it.
const SEAM_GAP := 8.0
const PIN_MARGIN := 36.0
const TAG_LIFT := 10.0
const WARN_TRI := ["...#...", "..#.#..", "..#.#..", ".#.#.#.", ".#...#.", "#..#..#", "#######"]
const PIN_ARROW := ["#...", "##..", "###.", "####", "###.", "##..", "#..."]
const PIN_ARROW_L := ["...#", "..##", ".###", "####", ".###", "..##", "...#"]
## Every world tag keeps this far outside the tank's drawn rects (art px).
const TAG_CLEAR := 8.0
const WARN_H := 26.0
const SPEED_H := 17.0
const SPEED_LEGS := 4.0
## The seam's range plate (TankSeam, SPEC_TANK 4.6): the shell's tag stands beside it, at its height.
const SEAM_PLATE_Y := 216.0
const SEAM_PLATE_W := 46.0
const SEAM_PLATE_H := 14.0
## Free roam: the turn marker shows once the turning place ahead is this near (game metres).
const TURN_MARKER_M := 160.0
## The angle meters' fade in, fade out and hold after their condition ends (s).
const DIAL_IN_S := 0.25
const DIAL_OUT_S := 0.6
const DIAL_HOLD_S := 1.5

var m: Dictionary = {}
## The turn marker (free roam): world x in rules px and the direction it turns the tank to
## (-1 left, +1 right); 0 = none.
var turn_x: float = 0.0
var turn_dir: int = 0
var _view: Object = null
var _view_tries: int = 0
## The angle meters' fades: Vector2(alpha 0..1, hold left in s) for the gun's arc and the
## Secondaries' dial, and the dial's data as last shown (drawn on through its hold and fade out).
var aim_fade: Vector2 = Vector2.ZERO
var sec_fade: Vector2 = Vector2.ZERO
var sec_shown: Dictionary = {}
var _alpha: float = 1.0


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
	return TankHudGeom.make(st(), find_view(), Vector2(canvas()))


## The angle meters' fades follow their show conditions (wall clock).
func tick(delta: float) -> void:
	aim_fade = dial_fade(aim_fade.x, aim_fade.y, bool(m.get("aim", false)), delta)
	sec_fade = dial_fade(sec_fade.x, sec_fade.y, m.has("sec"), delta)


## One step of an angle meter's fade: Vector2(alpha, hold left) after `dt` s from `alpha` (0..1)
## and `hold` (s), its condition `on` or not. On: up by dt / DIAL_IN_S, the hold refilled to
## DIAL_HOLD_S. Off: the hold runs out first, the rest of the step fades it by dt / DIAL_OUT_S.
static func dial_fade(alpha: float, hold: float, on: bool, dt: float) -> Vector2:
	if on:
		var up := alpha + dt / DIAL_IN_S
		return Vector2(1.0 if up > 0.999 else up, DIAL_HOLD_S)
	var left := hold - dt
	if left >= 0.0:
		return Vector2(alpha, left)
	var down := alpha + left / DIAL_OUT_S
	return Vector2(0.0 if down < 0.001 else down, 0.0)


## `col` at the meter being drawn's fade.
func _fa(col: Color) -> Color:
	return Color(col, col.a * _alpha)


func refresh() -> void:
	var s := st()
	_feed_turn(s)
	var g := geom()
	var h := s.hull
	m = {"speed": h.speed_mps * 3.6, "rear": g.tank_point("rear"), "ground": g.ground_y()}
	m["stand"] = TankSegments.on_stand(s)
	m["body"] = g.tank_rects()
	m["panels"] = g.panels()
	m["mirrored"] = g.mirrored()
	var halt := TankHudModel.halt_distance_m(s)
	m["halt_m"] = halt
	if halt >= 0.0:
		m["halt_x"] = g.world_x(h.x_px + float(h.hull_w) + TankConst.m_to_px(halt))
	m["threats"] = _near_rects(s, g)
	var warn: Array = []
	for t: Dictionary in TankHudModel.telegraphs(s):
		var r := Rect2()
		var anchor := Vector2.ZERO
		var far := false
		if bool(t["boss"]):
			r = g.boss_rect()
			anchor = g.boss_muzzle()
			far = s.boss.range_m > 0.0
		else:
			var e := s.enemy(int(t["id"]))
			r = g.enemy_rect(e) if e != null else Rect2()
			if r.size == Vector2.ZERO:
				continue
			far = TankHudGeom.in_far_frame(e)
			anchor = g.enemy_muzzle(e) if far else Vector2.ZERO
		if anchor == Vector2.ZERO:
			anchor = Vector2(r.position.x + r.size.x * 0.5, r.position.y)
		warn.append(
			{
				"anchor": anchor,
				"top": r.position.y,
				"boss": t["boss"],
				"far": far,
				"left": t["left"],
				"total": t["total"]
			}
		)
	warn.sort_custom(_sooner)
	m["warn"] = warn
	m["shell"] = TankHudModel.evadable_shell(s)
	var laying := absf(h.elev_deg - h.elev_target_deg) > 0.5 or h.target_id != 0
	m["aim"] = laying and absf(h.elev_deg) >= 2.0 and not h.out_of_action()
	if bool(m["aim"]) or aim_fade.x > 0.0:
		m["barrel"] = g.barrel()
		m["elev"] = h.elev_deg
		m["elev_to"] = h.elev_target_deg
	if turn_dir != 0:
		m["turn_x"] = g.world_x(turn_x)
	_feed_secondaries(s, g)
	if m.has("sec"):
		sec_shown = m["sec"]
	m["layout"] = layout()


## The Behemoth first, then the shooter whose telegraph runs out soonest: who gets the one plate.
static func _sooner(a: Dictionary, b: Dictionary) -> bool:
	if bool(a["boss"]) != bool(b["boss"]):
		return bool(a["boss"])
	return float(a["left"]) < float(b["left"])


## Every live near threat's rect as drawn (canvas art px): the road lane the post keeps out of.
static func _near_rects(s: TankState, g: TankHudGeom) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for e in s.enemies:
		if e.is_near() and e.mode != TankIds.EM_DEAD and e.hp > 0.0:
			var r := g.enemy_rect(e)
			if r.size != Vector2.ZERO:
				out.append(r)
	return out


## Where every world tag goes this refresh (canvas art px), clear of the plates and of the tank:
## {speed: Rect2 (empty when standing), posts: [{x, plate, pinned, pole, dir, title, value}], warn:
## [{rect, pointer (Array[Vector2i]), lx, w, plate (the one with the words, else a tick)}], shell: Rect2 (empty
## without an evadable shell; it holds the one instruction then)}.
func layout() -> Dictionary:
	var body: Array[Rect2] = []
	body.assign(m.get("body", []))
	var panels: Dictionary = m["panels"]
	var near: Rect2 = panels["near"]
	var far: Rect2 = panels["far"]
	var out := {"speed": Rect2(), "posts": [], "warn": [], "shell": Rect2()}
	var speed := Rect2()
	if float(m["speed"]) > 0.5:
		var txt := speed_text(m)
		var under := float(TankHud.anchored(TankHud.LAYOUT["mine"], canvas()).position.y)
		speed = speed_rect(m["rear"], D.tall_w(txt) + 16.0, bool(m["mirrored"]), body, near, under)
		out["speed"] = speed
	var gy := float(m["ground"])
	var threats: Array[Rect2] = []
	threats.assign(m.get("threats", []))
	if float(m["halt_m"]) >= 0.0 and m.has("halt_x"):
		var title := tx("TANK_HUD_HALT_LINE")
		var value := "%d m" % ceili(float(m["halt_m"]))
		var pl := post_layout(float(m["halt_x"]), post_size(title, value), gy, near, body, threats)
		pl.merge({"dir": 1, "title": title, "value": value})
		out["posts"].append(pl)
	if m.has("turn_x"):
		var title2 := tx("TANK_HUD_TURN")
		var pl2 := post_layout(float(m["turn_x"]), post_size(title2, ""), gy, near, body, threats)
		pl2.merge({"dir": turn_dir, "title": title2, "value": ""})
		out["posts"].append(pl2)
	var keep := keep_out()
	keep.append((panels["pip"] as Rect2).grow(2))
	if speed.size != Vector2.ZERO:
		keep.append(speed.grow(2))
	var wsize := Vector2(D.tall_w(tx("TANK_HUD_SURGE_TAG")) + 22.0, WARN_H)
	if not (m["shell"] as Dictionary).is_empty():
		var sr := shell_rect(panels["seam"], far, wsize)
		out["shell"] = sr
		keep.append(sr.grow(2))
	var plate_due: bool = (out["shell"] as Rect2).size == Vector2.ZERO
	for w: Dictionary in m["warn"]:
		var zone := far if bool(w["far"]) else near
		var wl := {}
		if plate_due:
			var room := _off_seam_plate(zone, panels["seam"]) if bool(w["far"]) else zone
			wl = warn_layout(w["anchor"], wsize, zone, keep, body, float(w["top"]), room)
		else:
			wl = warn_layout(w["anchor"], TICK_SIZE, zone, keep, body)
		wl["plate"] = plate_due
		plate_due = false
		wl["w"] = w
		out["warn"].append(wl)
		keep.append((wl["rect"] as Rect2).grow(2))
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
## the tracks (it grows toward the tank while driving west), inside the near panel. Where the road has no room for it
## above the rider's panel (`under`, its top; a short canvas), it stands over the hull's rear deck, in the air.
static func speed_rect(
	rear: Vector2, w: float, mirrored: bool, body: Array[Rect2], near: Rect2, under: float = INF
) -> Rect2:
	var x := rear.x - 10.0
	if mirrored:
		x = rear.x + 10.0 - w
	x = clampf(x, near.position.x + 4.0, near.end.x - 4.0 - w)
	var y := rear.y + 3.0
	var u := _union(body)
	if u.size != Vector2.ZERO:
		y = maxf(y, u.end.y + TAG_CLEAR)
		if y + SPEED_H + SPEED_LEGS > under:
			y = u.position.y - TAG_CLEAR - SPEED_H
	return Rect2(roundf(x), roundf(y), w, SPEED_H)


## A post's plate size for `title` and `value`.
static func post_size(title: String, value: String) -> Vector2:
	return Vector2(maxf(D.text_w(value, 2), D.tall_w(title)) + 10.0, 33.0 if value != "" else 18.0)


## The rect a striped post at canvas x `x` covers (its lamp's halo included), standing on `gy`.
static func post_rect(x: float, gy: float) -> Rect2:
	var top := gy - POST_H
	return Rect2(x - 4.0, top - 6.0, 11.0, gy + 4.0 - (top - 6.0))


## A striped post standing at canvas x `x` on the road (`gy`), its plate `size`: {x, plate, pinned, pole}.
## Pinned to the near panel's edge while beyond it; pushed out past the tank (TAG_CLEAR) when it would
## stand on it (the tank reaching its halt line); its plate on the post's left, else its right,
## whichever keeps clear of the tank, the post stepping back from the seam so the plate fits when the
## tank leaves room for that; it goes over the beam against the seam, always, so it never jumps when a threat comes, and
## only where a tank on a narrow canvas would not leave it room does it keep the post's side. With near threats alive
## (`threats`, their rects) the road lane is theirs: a pinned line stands no post (pole false).
static func post_layout(
	x: float, size: Vector2, gy: float, near: Rect2, body: Array[Rect2], threats: Array[Rect2] = []
) -> Dictionary:
	var pin_l := near.position.x + PIN_MARGIN
	var pin_r := near.end.x - PIN_MARGIN
	var pinned := x > pin_r or x < pin_l
	x = roundf(clampf(x, pin_l, pin_r))
	var u := _union(body)
	if not clear_of(post_rect(x, gy), body):
		var past := u.end.x + TAG_CLEAR + 5.0
		var before := u.position.x - TAG_CLEAR - 8.0
		# The nearer side of the tank, unless the post and its plate do not fit there.
		var near_right := x >= u.get_center().x or before - size.x - 6.0 < near.position.x + 4.0
		x = past if near_right and past + 9.0 <= near.end.x else before
	var top := gy - POST_H
	var left := Rect2(x - size.x - 6.0, top - 8.0, size.x, size.y)
	var right := Rect2(x + 9.0, top - 8.0, size.x, size.y)
	var plate := left
	if left.position.x < near.position.x + 4.0 or not clear_of(left, body):
		plate = right
		if plate.end.x > near.end.x:
			# Step back toward the tank; a narrow panel may still not leave it room (clamped below).
			var back := minf(x, maxf(near.end.x - size.x - 9.0, u.end.x + TAG_CLEAR + 5.0))
			if clear_of(post_rect(back, gy), body):
				x = back
				plate.position.x = x + 9.0
	var lift_y := maxf(gy - PLATE_LIFT - size.y, SEAM_PLATE_Y + SEAM_PLATE_H + 2.0)
	var lifted := Rect2(near.end.x - 12.0 - size.x, lift_y, size.x, size.y)
	if near.get_center().x < u.get_center().x:
		lifted.position.x = near.position.x + 12.0
	lifted.position = lifted.position.round()
	if clear_of(lifted, body):
		plate = lifted
	# Whatever else gives: every near plate stays in the near panel, none crosses the seam.
	plate.position.x = clampf(plate.position.x, near.position.x + 4.0, near.end.x - 4.0 - size.x)
	return {"x": x, "plate": plate, "pinned": pinned, "pole": threats.is_empty() or not pinned}


## The SURGE tag for a shooter at `anchor` (canvas art px; its muzzle in the far panel), `size` art px: {rect,
## pointer, lx}. Over the shooter (over its sprite's `top` when given, so it covers neither gun nor turret), inside its
## panel `zone`, under the plates `keep`; when that would touch the tank (`body` grown TAG_CLEAR), above the
## tank's top. The pointer runs from the tag's tip (at lx) to the shooter and is never painted on the tank. `room`, when
## given, is a narrower part of `zone` the tag itself keeps to.
static func warn_layout(
	anchor: Vector2,
	size: Vector2,
	zone: Rect2,
	keep: Array[Rect2],
	body: Array[Rect2],
	top: float = NAN,
	room: Rect2 = Rect2()
) -> Dictionary:
	var tw := size.x
	var th := size.y
	# a sprite can reach past its panel (the Behemoth at close range): the pointer stays inside
	anchor.x = clampf(anchor.x, zone.position.x + 2.0, zone.end.x - 2.0)
	var over := anchor.y if is_nan(top) else minf(top, anchor.y)
	var tr := Rect2(roundf(anchor.x - tw * 0.5), roundf(over - th - TAG_LIFT), tw, th)
	var box := zone if room.size == Vector2.ZERO else room
	tr.position.x = clampf(tr.position.x, box.position.x + 4.0, box.end.x - 4.0 - tw)
	tr.position.y = maxf(tr.position.y, zone.position.y + 4.0)
	tr = _under(tr, keep)
	if not clear_of(tr, body):
		tr.position.y = _union(body).position.y - TAG_CLEAR - th
		tr = _under(tr, keep)
	var lx := roundf(clampf(anchor.x, tr.position.x + 6.0, tr.end.x - 6.0))
	var from := Vector2(lx, tr.end.y + 4.0)
	var to := anchor + Vector2(0, -3)
	var pointer: Array[Vector2i] = []
	var steps := int(maxf(absf(to.x - from.x), absf(to.y - from.y)))
	for j in range(0, steps + 1, 2):
		var p := from.lerp(to, float(j) / maxf(float(steps), 1.0)).round()
		if not _on_body(p, body):
			pointer.append(Vector2i(p))
	return {"rect": tr, "pointer": pointer, "lx": lx}


## The evadable shell's SURGE tag: in the far panel, beside the seam's range plate and at its height.
static func shell_rect(seam: Rect2, far: Rect2, size: Vector2) -> Rect2:
	var cx := seam.get_center().x
	var x := cx + SEAM_PLATE_W * 0.5 + SEAM_GAP
	if far.get_center().x < cx:
		x = cx - SEAM_PLATE_W * 0.5 - SEAM_GAP - size.x
	return Rect2(roundf(x), SEAM_PLATE_Y, size.x, size.y)


## The far panel `far` without the strip the seam's range plate reaches into.
static func _off_seam_plate(far: Rect2, seam: Rect2) -> Rect2:
	var reach := SEAM_PLATE_W * 0.5 - seam.size.x * 0.5
	if far.position.x >= seam.position.x:
		return far.grow_individual(-reach, 0.0, 0.0, 0.0)
	return far.grow_individual(0.0, 0.0, -reach, 0.0)


## `tr` moved under the plates `keep` it would lie on.
static func _under(tr: Rect2, keep: Array[Rect2]) -> Rect2:
	for k in keep:
		if tr.intersects(k):
			tr.position.y = k.end.y + 2.0
	return tr


static func _on_body(p: Vector2, body: Array[Rect2]) -> bool:
	for b in body:
		if b.has_point(p + Vector2(0.5, 0.5)):
			return true
	return false


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
	var sr2: Rect2 = lay["shell"]
	if sr2.size != Vector2.ZERO:
		var sh: Dictionary = m["shell"]
		_surge_plate(sr2, float(sh["left"]), float(sh["total"]))
	if aim_fade.x > 0.0 and m.has("barrel"):
		_alpha = aim_fade.x
		_elev_arc()
	if sec_fade.x > 0.0 and not sec_shown.is_empty():
		_alpha = sec_fade.x
		_sec_arc(sec_shown)
	_alpha = 1.0


## The speed tag's text: km/h on the road, "tracks 31" while the hull sits on its stand (the tracks turn in the air,
## nothing goes by).
func speed_text(model: Dictionary) -> String:
	var key := "TANK_HUD_SPEED_STAND" if bool(model.get("stand", false)) else "TANK_HUD_SPEED"
	return tx(key, [roundi(float(model["speed"]))])


## A small riveted plate standing on the road behind the rear track, the HUD's plate style with room
## round the text: the speed in the tall face, a drop shadow on the gravel and two iron legs; below
## the tracks, clear of the tank (speed_rect).
func _speed_tag(r: Rect2) -> void:
	var txt := speed_text(m)
	D.rect(self, Rect2(r.position + Vector2(2, r.size.y), Vector2(r.size.x - 2, 1)), D.SHADOW)
	# on the road it stands on its legs; over the deck (a short canvas) it has none
	if r.position.y >= float(m["ground"]) - SPEED_H:
		for lx: float in [r.position.x + 5.0, r.end.x - 7.0]:
			D.rect(self, Rect2(lx, r.end.y, 2, SPEED_LEGS), D.RIVET_LO)
			D.rect(self, Rect2(lx, r.end.y, 1, SPEED_LEGS), D.FRAME_IN)
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
	var threats: Array[Rect2] = []
	threats.assign(m.get("threats", []))
	if bool(pl.get("pole", true)):
		_pole(x, top, gy, threats)
	var tr: Rect2 = pl["plate"]
	D.plate(self, tr, D.FRAME, 0)
	D.tall(self, tr.position.x + 5, tr.position.y + 4, title, D.DIM)
	if value != "":
		D.text(self, tr.position.x + 5, tr.position.y + 16, value, D.NUM, 2)
	if pinned or dir < 0:
		var arrow := PIN_ARROW if dir >= 0 else PIN_ARROW_L
		var ax := x + 8.0 if dir >= 0 else x - 8.0
		var ay := top + 6.0
		if not threats.is_empty():
			# outside the plate's own edge, over the beam: the road lane is the threat's
			ax = tr.end.x + 2.0 if dir >= 0 else tr.position.x - 6.0
			ay = tr.position.y + 13.0
		D.pixels(self, arrow, Vector2(ax, ay), D.AMBER)


## The striped post and its lamp, every pixel of it behind the near threats: the signage never stands on a threat.
func _pole(x: float, top: float, gy: float, threats: Array[Rect2]) -> void:
	for y in range(int(top), int(gy + 2)):
		var band := posmod(int((y - top) / 4.0), 2) == 0
		_post_rect(Rect2(x, y, 3, 1), D.AMBER if band else Color("#2a1f14"), threats)
	_post_rect(Rect2(x - 1, gy + 2, 5, 2), Color("#2a1f14"), threats)
	_post_rect(Rect2(x - 3, top - 3, 9, 3), D.FRAME, threats)
	_post_rect(Rect2(x - 4, top - 6, 11, 11), Color(D.AMBER, 0.12), threats)
	_post_rect(Rect2(x, top - 2, 3, 1), Color("#fff2c8"), threats)


func _post_rect(r: Rect2, col: Color, threats: Array[Rect2]) -> void:
	for t in threats:
		if r.intersects(t):
			return
	D.rect(self, r, col)


## The plates a world tag keeps out of, on the canvas.
func keep_out() -> Array[Rect2]:
	var cv := canvas()
	var out: Array[Rect2] = []
	for key: String in ["mission", "toasts", "hull", "boss"]:
		out.append(Rect2(TankHud.anchored(TankHud.LAYOUT[key], cv)).grow(2))
	return out


## A SURGE tag laid out by warn_layout: the plate, its tip and the dotted pointer to the shooter; a shooter with no
## plate of its own has a small blinking tick and the same pointer.
func _warn_tag(wl: Dictionary) -> void:
	var w: Dictionary = wl["w"]
	var tr: Rect2 = wl["rect"]
	var lx := float(wl["lx"])
	for p: Vector2i in wl["pointer"]:
		D.rect(self, Rect2(Vector2(p), Vector2(1, 1)), Color(D.RED, 0.8))
	if not bool(wl.get("plate", true)):
		var lit := int(floorf(st().t * 4.0)) % 2 == 0
		D.pixels(self, TICK, tr.position, D.RED if lit else D.FRAME_HI)
		return
	var edge := _surge_plate(tr, float(w["left"]), float(w["total"]))
	for k in 4:
		D.rect(self, Rect2(lx - 3 + k, tr.end.y + k, 7 - 2 * k, 1), edge)


## The SURGE plate: its blinking edge (returned), the warning sign, the label, one pip per second of
## `total`, emptying as `left` runs out.
func _surge_plate(tr: Rect2, left: float, total: float) -> Color:
	var blink := int(floorf(st().t * 4.0)) % 2 == 0
	var edge := D.RED if blink else D.FRAME_HI
	D.plate(self, tr, edge, 0)
	D.pixels(self, WARN_TRI, tr.position + Vector2(5, 4), D.RED)
	D.tall(self, tr.position.x + 15, tr.position.y + 4, tx("TANK_HUD_SURGE_TAG"), D.TEXT)
	var n := maxi(ceili(total), 1)
	var lit := clampi(ceili(left), 0, n)
	var pw := 5.0
	var px := roundf(tr.position.x + (tr.size.x - n * (pw + 2) + 2) * 0.5)
	for i in n:
		var col := D.RED if i < lit else D.TRACK
		D.rect(self, Rect2(px + i * (pw + 2), tr.position.y + 17, pw, 4), col)
	return edge


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
		D.tall(self, lr.position.x + 1, lr.position.y + 1, lab, _fa(D.SHADOW))
		D.tall(self, lr.position.x, lr.position.y, lab, _fa(D.AMBER))
		_rack_pips(lr, left)


## One arc pixel, only outside the tank's body (TankHudGeom.arc_px_ok).
func _arc_px(keep: Array, p: Vector2i, col: Color) -> void:
	if TankHudGeom.arc_px_ok(p, keep):
		D.rect(self, Rect2(Vector2(p), Vector2(1, 1)), _fa(col))


# --- v3: the ready rack by the gun's arc, the Secondaries' dial ----------------------------------------

const SEC_MIN := -10.0
const SEC_MAX := 35.0
const SEC_R := 19.0
const SEC_GAP := 7.0
const SEC_COL := Color("#d6ecff")
const SEC_DIM := Color(0.62, 0.78, 0.92, 0.5)
## The plate under the dial's two lines (its alpha).
const SEC_PLATE_A := 0.8
## The bow guns' reach ahead of their muzzles in rules px (tanks.json bow.min_px, max_px).
const SEC_REACH_PX := Vector2(4.0, 200.0)
const SHELL_PIP := [".#.", "###", "###", "###", "###", "###", "###"]


## The ready rack's three shells beside the elevation label (lit while in the rack).
func _rack_pips(lr: Rect2, left: bool) -> void:
	var rack := TankHudModel.rack(st())
	var x := lr.end.x + 4.0 if not left else lr.position.x - 19.0
	var p := Vector2(roundf(x), lr.position.y + 1.0)
	D.rect(self, Rect2(p - Vector2(2, 1), Vector2(19, 9)), _fa(Color(D.PANEL, 0.7)))
	for i in TankConst.RACK_MAX:
		var col := D.BRASS.lightened(0.2) if i < rack else Color("#4a3e30")
		D.pixels(self, SHELL_PIP, p + Vector2(i * 5, 0), _fa(col))
		if i < rack:
			D.rect(self, Rect2(p + Vector2(i * 5 + 1, 0), Vector2(1, 1)), _fa(Color("#e07a3c")))


## True while a near threat (recon, tankette) is alive: the Secondaries' dial shows only then.
static func near_threat(s: TankState) -> bool:
	for e in s.enemies:
		if e.is_near() and e.mode != TankIds.EM_DEAD and e.hp > 0.0:
			return true
	return false


## The bow guns' elevation as the dial shows it: {deg (+ up, SEC_MIN..SEC_MAX), target (a near threat
## in their reach)}. SWITCH POINT for the lead: until the rules expose the bow guns' elevation, deg
## is the upper gun's bore as the view draws it (pivot to muzzle, which the view tilts toward the
## nearest enemy ahead), else (no view) the bore line from its pivot to the nearest near threat
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
		if not e.is_near() or e.mode == TankIds.EM_DEAD or e.hp <= 0.0:
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


## The Secondaries' dial data while their seat is manned, a near threat lives and the guns fire or have
## it in reach: the bow guns' pivot and length as drawn, their side, their elevation (bow_elevation()) and the rounds a
## minute (TankFeedState.rpm).
func _feed_secondaries(s: TankState, g: TankHudGeom) -> void:
	m.erase("sec")
	var fd := s.station(TankIds.ENGINE_FEED)
	if fd == null or fd.is_empty() or not near_threat(s):
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
func _sec_arc(sd: Dictionary) -> void:
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
	D.rect(self, Rect2(tip.round() - Vector2(1, 1), Vector2(3, 3)), _fa(SEC_COL))
	D.rect(self, Rect2(c - Vector2(1, 1), Vector2(3, 3)), _fa(SEC_COL))
	var e := roundi(deg)
	var lab := ("+" if e > 0 else "") + str(e) + "°"
	var mid := c + TankHudGeom.dir(SEC_MIN, left) * (SEC_R + 4.0)
	var x := mid.x + 2.0 if not left else mid.x - 2.0 - D.text_w(lab)
	var rpm := tx("TANK_HUD_PER_MIN", [roundi(float(sd["rpm"]))])
	# a dark plate under the two lines: the bow rounds' tracers pass behind, never through the text
	var pw := maxf(D.text_w(lab), D.text_w(rpm)) + 4.0
	var plate := Rect2(roundf(x - 2.0), roundf(mid.y - 3.0), pw, 21.0)
	D.rect(self, plate, _fa(Color(D.PANEL, SEC_PLATE_A)))
	for ln: Array in [[lab, -1.0, SEC_COL], [rpm, 8.0, SEC_DIM]]:
		var ty := roundf(mid.y + float(ln[1]))
		D.text(self, roundf(x) + 1.0, ty + 1.0, str(ln[0]), _fa(D.SHADOW))
		D.text(self, roundf(x), ty, str(ln[0]), _fa(ln[2]))


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
