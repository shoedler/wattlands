extends SceneTree
## Preview sheets of the enemies at real game scale, drawn by the real TankEnemyDraw on the night
## background next to the real tank (assets/tank/v3/tank_base.png with its live running gear). Windowed:
##   tools/godot.sh --timeout=180 --path . --resolution 1280x720 -s assets/tank/v4/tools_src/preview.gd
## Writes build/tank/v4_art/*.png: lineup_960 (a 960 x 540 stage: our tank, the near threats ahead of its
## nose, the far kinds as they stand on the far panel), kinds_3x, wrecks_3x, motion_3x (track and wheels over
## one shoe pitch, turret traverse, gun recoil, a bump), far_852 (three enemies on the 286 px panel).

const OUTDIR := "res://build/tank/v4_art/"
const NIGHT := Color("#090c13")

var _kit: TankEnemyKit
var _sheets: Array = []


class Stage:
	extends Node2D
	var calls: Array = []
	var bg: Array = []
	var text: Array = []
	var kit: TankEnemyKit
	var timed: Array = []

	func _draw() -> void:
		var t0 := Time.get_ticks_usec()
		for c0: Array in timed:
			TankEnemyDraw.draw(self, kit, str(c0[0]), c0[1], c0[2])
		if not timed.is_empty():
			print("draw of %d enemies: %d us" % [timed.size(), Time.get_ticks_usec() - t0])
		for b: Array in bg:
			if b[0] is Texture2D:
				var t: Texture2D = b[0]
				if b.size() == 4:
					draw_texture_rect_region(t, Rect2(b[2], b[3], b[1].size.x, b[1].size.y), b[1])
				elif b.size() > 2:
					draw_texture_rect(t, b[1], true)
				else:
					draw_texture(t, b[1])
			else:
				draw_rect(b[1], b[0])
		for c: Array in calls:
			TankEnemyDraw.draw(self, kit, str(c[0]), c[1], c[2])
		for c2: Array in calls:
			TankEnemyDraw.draw_light(self, kit, str(c2[0]), c2[1], c2[2])
		for t2: Array in text:
			draw_string(ThemeDB.fallback_font, t2[0], str(t2[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.75, 0.72))


func _init() -> void:
	_kit = TankEnemyKit.shared()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTDIR))
	_run()


func _viewport(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(vp)
	return vp


func _shot(vp: SubViewport, name: String, scale: int = 1) -> void:
	var img := vp.get_texture().get_image()
	if scale > 1:
		img.resize(img.get_width() * scale, img.get_height() * scale, Image.INTERPOLATE_NEAREST)
	img.save_png(ProjectSettings.globalize_path(OUTDIR + name + ".png"))
	print("saved ", name)


func _sheet(name: String, size: Vector2i, scale: int, fill: Callable) -> void:
	var vp := _viewport(size)
	var bg := ColorRect.new()
	bg.color = NIGHT
	bg.size = Vector2(size)
	vp.add_child(bg)
	var st := Stage.new()
	st.kit = _kit
	fill.call(st, vp)
	vp.add_child(st)
	_sheets.append([vp, name, scale])


func _run() -> void:
	_sheet("lineup_960", Vector2i(960, 540), 1, _lineup)
	_sheet("kinds_3x", Vector2i(470, 330), 3, _kinds)
	_sheet("sil_1x", Vector2i(700, 260), 2, _sil)
	_sheet("wrecks_3x", Vector2i(470, 330), 3, _wrecks)
	_sheet("motion_3x", Vector2i(760, 340), 2, _motion)
	_sheet("far_852", Vector2i(286, 480), 2, _far852)
	_sheet("bushes_3x", Vector2i(330, 80), 3, _bushes)
	_sheet("cap_cost", Vector2i(960, 540), 1, _cap)
	_repair_strip()
	for i in 6:
		await process_frame
	for s: Array in _sheets:
		_shot(s[0], s[1], s[2])
	quit()


## The Repairs seat, four frames of one crank revolution at 60 and at 90 rpm: the card at 112 x 64 and the room
## (with what is round it) from TankInterior; plus the six machines side by side at the card's size.
func _repair_strip() -> void:
	var rig := TankRig.shared()
	var interior := TankInterior.new(rig)
	var room := Rect2i(rig.rooms["turret_drive"]).grow(10)
	var sheet := Image.create_empty(4 * 118 + 6, 2 * 70 + 2 * (room.size.y + 6) + 76, false, Image.FORMAT_RGBA8)
	sheet.fill(NIGHT)
	var y := 3
	for rpm: float in [60.0, 90.0]:
		for k in 4:
			var phase := 3.0 + float(k) * 0.24
			var card := Image.create_empty(TankMech.W, TankMech.H, false, Image.FORMAT_RGBA8)
			TankMech.paint_ex(card, "repair", phase, 1.0, 1.0 + k * 0.2, Color("#D55E00"), rpm)
			sheet.blit_rect(card, Rect2i(0, 0, TankMech.W, TankMech.H), Vector2i(3 + k * 118, y))
		y += 70
	for rpm2: float in [60.0, 90.0]:
		for k2 in 4:
			var rp := {"slot": 2, "revs": 7.0 + float(k2) * 0.24, "on": true, "press_t": 0.2 + k2 * 0.25, "patches": 3 + k2}
			interior._paint_unit("repair", {"t": k2 * 0.1, "repair": rp})
			sheet.blit_rect(interior.img, room, Vector2i(3 + k2 * 118, y))
		y += room.size.y + 6
	var x := 3
	for m: String in ["diesel", "dynamo", "steam", "arc", "feed", "repair"]:
		var c2 := Image.create_empty(TankMech.W, TankMech.H, false, Image.FORMAT_RGBA8)
		TankMech.paint_ex(c2, m, 1.3, 1.0, 1.0, Color("#0072B2"), 90.0)
		c2.resize(72, 41, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(c2, Rect2i(0, 0, 72, 41), Vector2i(x, y + 2))
		x += 78
	sheet.resize(sheet.get_width() * 3, sheet.get_height() * 3, Image.INTERPOLATE_NEAREST)
	sheet.save_png(ProjectSettings.globalize_path(OUTDIR + "repair_3x.png"))
	var whole := interior.img.duplicate() as Image
	whole.save_png(ProjectSettings.globalize_path(OUTDIR + "repair_hero.png"))


func _ground(st: Stage, y: float, w: float) -> void:
	st.bg.append([Color("#0e1214"), Rect2(0, y, w, 8)])
	st.bg.append([Color("#0a0d0e"), Rect2(0, y + 8, w, 600)])


## The hero at its place with the gear drawn as TankBody does.
func _hero(vp: SubViewport, st: Stage, at: Vector2) -> void:
	var rig := TankRig.shared()
	var body := TankBody.new(rig)
	vp.add_child(body)
	body.refresh()
	var spr := Sprite2D.new()
	spr.centered = false
	spr.texture = body.get_texture()
	spr.position = at - Vector2(TankBody.PAD, TankBody.PAD)
	vp.add_child(spr)
	var _s := st


func _lineup(st: Stage, vp: SubViewport) -> void:
	var g := 396.0
	_ground(st, g, 960.0)
	var fg := _kit.far_ground()
	if fg != null:
		st.bg.append([fg, Rect2(630, 320, 330, 170), true])
	_hero(vp, st, Vector2(18, g - 209.0))
	st.calls.append(["recon", Vector2(572, g), {"travel": 3.0, "turret_sx": -1.0}])
	st.calls.append(["tankette", Vector2(508, g - 14.0), {"travel": 1.0, "turret_sx": -1.0}])
	st.bg.append([Color(0.2, 0.2, 0.2), Rect2(622, 0, 8, 540)])
	# the far panel as the view stands them, back to front, on the ground band; the haze is the field's
	st.calls.append(["behemoth", Vector2(800, 356), {"haze": 0.16, "travel": 1.0, "bogies_wrecked": [false, true, false]}])
	st.calls.append(["destroyer", Vector2(880, 378), {"haze": 0.46, "travel": 2.0}])
	st.calls.append(["heavy", Vector2(780, 396), {"haze": 0.3, "travel": 2.0, "elev_deg": 6.0}])
	st.calls.append(["medium", Vector2(880, 420), {"haze": 0.22, "travel": 1.0, "elev_deg": 5.0}])
	st.calls.append(["light", Vector2(690, 430), {"haze": 0.14, "travel": 1.0}])


## Every kind as a filled shape at 1x, front to the left: what must tell them apart at 0.2 s.
func _sil(st: Stage, _vp: SubViewport) -> void:
	var white := {"flash": 1.0}
	var rows := [
		["light", Vector2(60, 60)], ["medium", Vector2(190, 70)], ["heavy", Vector2(370, 84)], ["destroyer", Vector2(570, 66)],
		["tankette", Vector2(50, 200)], ["recon", Vector2(140, 210)], ["behemoth", Vector2(400, 250)],
	]
	for r: Array in rows:
		st.calls.append([r[0], r[1], white])


func _kinds(st: Stage, _vp: SubViewport) -> void:
	_ground(st, 800.0, 470.0)
	var rows := [
		["tankette", Vector2(40, 40), 1.0], ["recon", Vector2(130, 50), 1.0], ["light", Vector2(250, 56), -1.0],
		["medium", Vector2(380, 70), -1.0], ["heavy", Vector2(90, 140), -1.0], ["destroyer", Vector2(280, 130), -1.0],
		["behemoth", Vector2(160, 310), -1.0],
	]
	for r: Array in rows:
		st.calls.append([r[0], r[1], {"travel": 2.0, "turret_sx": 1.0, "elev_deg": 2.0}])
	st.calls.append(["recon", Vector2(400, 150), {"travel": 2.0, "turret_sx": -1.0}])
	st.calls.append(["tankette", Vector2(400, 200), {"travel": 2.0, "turret_sx": -1.0}])


func _wrecks(st: Stage, _vp: SubViewport) -> void:
	var rows := [
		["tankette", Vector2(40, 40)], ["recon", Vector2(130, 50)], ["light", Vector2(250, 56)],
		["medium", Vector2(380, 70)], ["heavy", Vector2(90, 140)], ["destroyer", Vector2(280, 130)],
		["behemoth", Vector2(160, 310)],
	]
	for r: Array in rows:
		st.calls.append([r[0], r[1], {"wrecked": true, "time": 0.3}])


func _motion(st: Stage, _vp: SubViewport) -> void:
	var bump := func(x: float) -> float: return 60.0 + 3.0 * sin(x * 0.2)
	for i in 4:
		st.calls.append(["medium", Vector2(80 + i * 170, 60), {"travel": float(i) * 1.0}])
	for i2 in 4:
		st.calls.append(["light", Vector2(70 + i2 * 170, 110), {"turret_sx": 1.0 - i2 * 0.66, "elev_deg": i2 * 4.0}])
	for i3 in 4:
		st.calls.append(["medium", Vector2(80 + i3 * 170, 180), {"recoil": float(i3) * 2.0, "flash": 0.25 * i3, "elev_deg": 8.0}])
	for i4 in 4:
		var shifted := func(x: float) -> float: return float(bump.call(x + i4 * 12.0)) + 190.0
		st.calls.append(["heavy", Vector2(95 + i4 * 180, 250), {"ground": shifted, "travel": i4 * 2.0}])
	st.calls.append(["recon", Vector2(60, 320), {"ground": func(x: float) -> float: return 320.0 + 3.0 * sin(x * 0.3), "turret_sx": -1.0}])
	st.calls.append(["tankette", Vector2(180, 320), {"ground": func(x: float) -> float: return 320.0 + 3.0 * sin(x * 0.3), "turret_sx": -1.0}])


func _bushes(st: Stage, _vp: SubViewport) -> void:
	_ground(st, 70.0, 330.0)
	var x := 8.0
	for r: Rect2 in _kit.bush_rects():
		st.bg.append([_kit.bushes(), r, x, 72.0 - r.size.y])
		x += r.size.x + 8.0


## SPEC_TANK 4.2's cap: 8 far and 8 near, moving, on a bumpy road: what TankEnemyDraw costs a frame.
func _cap(st: Stage, _vp: SubViewport) -> void:
	var g := func(x: float) -> float: return 400.0 + 2.0 * sin(x * 0.07)
	var far: Array[String] = ["light", "medium", "heavy", "destroyer", "light", "medium", "heavy", "destroyer"]
	for i in far.size():
		st.timed.append([far[i], Vector2(100 + i * 100, 300), {"travel": 9.0 + i, "haze": 0.3, "elev_deg": 7.0}])
	for i2 in 8:
		var k := "recon" if i2 % 2 == 0 else "tankette"
		st.timed.append([k, Vector2(100 + i2 * 90, 400), {"travel": 3.0 + i2, "ground": g, "turret_sx": -1.0}])


## Three enemies on the 852 canvas's 286 px panel, each at its range's place and foot (TankFarMap) and the
## haze the far panel gives that range.
func _far852(st: Stage, _vp: SubViewport) -> void:
	var fg := _kit.far_ground()
	if fg != null:
		st.bg.append([fg, Rect2(0, 300, 286, 170), true])
	st.calls.append(["destroyer", _far_foot("destroyer", 2200.0, 1), {"haze": 0.46, "travel": 1.0}])
	st.calls.append(["heavy", _far_foot("heavy", 1640.0, 0), {"haze": 0.31, "travel": 1.0, "elev_deg": 6.0}])
	st.calls.append(["medium", _far_foot("medium", 1100.0, 0), {"haze": 0.2, "travel": 1.0}])


func _far_foot(kind: String, range_m: float, lane: int) -> Vector2:
	var half := float(_kit.kind(kind)["size"].x) * 0.5
	var x := clampf(TankFarMap.range_x(range_m, 286.0), half + 1.0, 286.0 - half - 1.0)
	return Vector2(roundf(x), TankFarMap.foot_y(range_m, lane))
