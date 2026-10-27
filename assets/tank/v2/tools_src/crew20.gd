extends SceneTree
# Crewmen at 19-20 art px tall (the reference's size at 960x540). Parametric skeleton poses drawn on a
# material grid, then shaded with a warm top light (room lamps above), like the reference's lit
# silhouettes. Writes assets/tank/v2/crew20/<pose>_<i>.png, crew20.json, crew20_sheet.png (1x)
# and crew20_sheet_4x.png (the json and sheets to build/v2/; kit.gd folds the json into kit.json).

var F = load("res://build/v2/font.gd")
const CW := 30
const CH := 24
const OUT := "res://assets/tank/v2/"
const BUILD := "res://build/v2/"

enum M {
	NONE, HELMET, SKIN, JACKET, TROUSER, BOOT, BELT, WOOD, STEEL, BRASS, BRASS_D, COAL, DMETAL,
	MMETAL, LENS, LED_G, LED_R, LED_A, EMBER, STRAP, BACKJ, BACKT, BINO
}

# base, lit (top edge), shade (back edge)
var PAL := {
	M.HELMET: [Color8(62, 66, 46), Color8(140, 126, 84), Color8(40, 42, 30)],
	M.SKIN: [Color8(116, 76, 52), Color8(186, 132, 90), Color8(84, 54, 38)],
	M.JACKET: [Color8(54, 58, 40), Color8(112, 104, 68), Color8(36, 38, 27)],
	M.BACKJ: [Color8(40, 43, 30), Color8(80, 76, 52), Color8(30, 31, 22)],
	M.TROUSER: [Color8(46, 49, 35), Color8(90, 86, 58), Color8(32, 33, 24)],
	M.BACKT: [Color8(35, 37, 27), Color8(64, 62, 44), Color8(26, 27, 20)],
	M.BOOT: [Color8(26, 23, 19), Color8(70, 56, 40), Color8(18, 16, 13)],
	M.BELT: [Color8(34, 30, 22), Color8(120, 94, 54), Color8(24, 21, 16)],
	M.STRAP: [Color8(70, 52, 32), Color8(130, 98, 60), Color8(50, 38, 24)],
	M.WOOD: [Color8(112, 76, 44), Color8(170, 122, 72), Color8(80, 54, 32)],
	M.STEEL: [Color8(150, 150, 140), Color8(206, 200, 184), Color8(98, 98, 92)],
	M.BRASS: [Color8(200, 154, 70), Color8(246, 206, 120), Color8(140, 104, 44)],
	M.BRASS_D: [Color8(130, 96, 40), Color8(170, 128, 60), Color8(96, 70, 30)],
	M.COAL: [Color8(26, 26, 28), Color8(70, 66, 64), Color8(16, 16, 18)],
	M.DMETAL: [Color8(42, 40, 36), Color8(96, 88, 74), Color8(28, 27, 24)],
	M.MMETAL: [Color8(76, 72, 62), Color8(128, 118, 96), Color8(54, 51, 45)],
	M.LENS: [Color8(255, 240, 190), Color8(255, 252, 230), Color8(255, 214, 140)],
	M.LED_G: [Color8(110, 255, 140), Color8(190, 255, 200), Color8(80, 200, 100)],
	M.LED_R: [Color8(255, 86, 60), Color8(255, 150, 120), Color8(200, 60, 40)],
	M.LED_A: [Color8(255, 196, 70), Color8(255, 230, 150), Color8(210, 150, 50)],
	M.EMBER: [Color8(255, 150, 50), Color8(255, 210, 120), Color8(220, 110, 30)],
	M.BINO: [Color8(30, 30, 30), Color8(90, 86, 80), Color8(20, 20, 20)],
}
# materials that get top-light / back-shade
const SHADED := [M.HELMET, M.SKIN, M.JACKET, M.BACKJ, M.TROUSER, M.BACKT, M.BOOT, M.WOOD, M.STEEL,
	M.BRASS, M.DMETAL, M.MMETAL, M.STRAP, M.BELT]
const EMISSIVE := [M.LENS, M.LED_G, M.LED_R, M.LED_A, M.EMBER]

var g := PackedInt32Array()


func clear() -> void:
	g.resize(CW * CH)
	g.fill(0)


func px(x: int, y: int, m: int) -> void:
	if x >= 0 and y >= 0 and x < CW and y < CH:
		g[y * CW + x] = m


func at(x: int, y: int) -> int:
	if x >= 0 and y >= 0 and x < CW and y < CH:
		return g[y * CW + x]
	return 0


func rect(x: int, y: int, w: int, h: int, m: int) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			px(xx, yy, m)


func line(a: Vector2i, b: Vector2i, m: int, w: int = 1) -> void:
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	var steep := absi(b.y - a.y) >= absi(b.x - a.x)
	while true:
		px(p.x, p.y, m)
		if w >= 2:
			if steep:
				px(p.x + 1, p.y, m)
			else:
				px(p.x, p.y + 1, m)
		if p == b:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy


# A figure. f keys: sh (Vector2i front-shoulder anchor = head x), hip (Vector2i), legs [[knee, foot] back, front],
# arms [[elbow, hand] back, front], under/over: tool primitive lists, helmet_off: no.
func figure(f: Dictionary) -> void:
	var sh: Vector2i = f["sh"]
	var hip: Vector2i = f["hip"]
	prims(f.get("under", []))
	# back arm, back leg
	var arms: Array = f["arms"]
	var legs: Array = f["legs"]
	limb_leg(Vector2i(hip.x - 1, hip.y), legs[0][0], legs[0][1], M.BACKT)
	limb_arm(Vector2i(sh.x - 1, sh.y + 1), arms[0][0], arms[0][1], M.BACKJ)
	prims(f.get("mid", []))
	# torso: shoulders (sh.y) to belt (hip.y)
	var rows := hip.y - sh.y
	for i in rows + 1:
		var t := float(i) / float(maxi(rows, 1))
		var cx := roundi(lerpf(float(sh.x), float(hip.x), t))
		var half_l := 3
		var half_r := 3 if i <= 1 else 2
		var m := M.BELT if i == rows else M.JACKET
		for x in range(cx - half_l, cx + half_r + 1):
			px(x, sh.y + i, m)
	px(hip.x + 1, hip.y, M.BRASS_D)
	# strap across the chest
	if f.get("strap", true):
		px(sh.x - 1, sh.y + 1, M.STRAP)
		px(sh.x, sh.y + 2, M.STRAP)
		px(sh.x + 1, sh.y + 3, M.STRAP)
	limb_leg(Vector2i(hip.x + 1, hip.y), legs[1][0], legs[1][1], M.TROUSER)
	# head (helmet + face), anchored on the shoulders
	var hx: int = sh.x + int(f.get("head_dx", 0))
	var hy: int = sh.y - 5 + int(f.get("head_dy", 0))
	px(hx, hy + 4, M.SKIN)
	px(hx + 1, hy + 4, M.SKIN)
	px(hx - 1, hy + 4, M.JACKET)
	for x in range(hx - 1, hx + 3):
		px(x, hy + 3, M.SKIN)
	px(hx - 1, hy + 3, M.STRAP)
	if bool(f.get("chin", false)):
		px(hx + 2, hy + 4, M.SKIN)
	# a rounded steel helmet: 4, 6, 7 px rows, the rim lower at the back over the ear
	for x in range(hx - 1, hx + 3):
		px(x, hy, M.HELMET)
	for x in range(hx - 2, hx + 4):
		px(x, hy + 1, M.HELMET)
	for x in range(hx - 2, hx + 4):
		px(x, hy + 2, M.HELMET)
	px(hx - 2, hy + 3, M.HELMET)
	if bool(f.get("brim", true)):
		px(hx + 4, hy + 2, M.HELMET)
	limb_arm(Vector2i(sh.x + 1, sh.y + 1), arms[1][0], arms[1][1], M.JACKET)
	prims(f.get("over", []))


func limb_leg(h: Vector2i, knee: Vector2i, foot: Vector2i, m: int) -> void:
	line(h, knee, m, 2)
	line(knee, Vector2i(foot.x, foot.y - 1), m, 2)
	# boot: 3 px toe forward, plus the boot top
	px(foot.x, foot.y - 1, M.BOOT)
	px(foot.x + 1, foot.y - 1, M.BOOT)
	for x in range(foot.x, foot.x + 3):
		px(x, foot.y, M.BOOT)


func limb_arm(s: Vector2i, elbow: Vector2i, hand: Vector2i, m: int) -> void:
	line(s, elbow, m, 2)
	line(elbow, hand, m, 1)
	px(hand.x, hand.y, M.SKIN)


func prims(list: Array) -> void:
	for p: Array in list:
		match str(p[0]):
			"px":
				px(p[1], p[2], p[3])
			"rect":
				rect(p[1], p[2], p[3], p[4], p[5])
			"line":
				line(p[1], p[2], p[3], int(p[4]) if p.size() > 4 else 1)
			"wheel":
				wheel(p[1], p[2], p[3])


# a handwheel of radius 3 at c with a spoke angle a (deg)
func wheel(c: Vector2i, a: float, m: int) -> void:
	for i in 16:
		var t := TAU * float(i) / 16.0
		px(c.x + roundi(3.0 * cos(t)), c.y + roundi(3.0 * sin(t)), m)
	for k in 2:
		var t := deg_to_rad(a) + PI * 0.5 * k
		line(c + Vector2i(roundi(-2.0 * cos(t)), roundi(-2.0 * sin(t))), c + Vector2i(roundi(2.0 * cos(t)), roundi(2.0 * sin(t))), m)
	px(c.x, c.y, M.BRASS)


func render() -> Image:
	var img := Image.create(CW, CH, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in CH:
		for x in CW:
			var m := at(x, y)
			if m == 0:
				continue
			var pal: Array = PAL[m]
			var c: Color = pal[0]
			if m in SHADED:
				var up := at(x, y - 1)
				var left := at(x - 1, y)
				if up == 0 or (up in EMISSIVE):
					c = pal[1]
				elif left == 0 and at(x + 1, y) != 0:
					c = pal[2]
				# a warm bounce on the front edge (lamp light from the room)
				elif at(x + 1, y) == 0 and m in [M.JACKET, M.TROUSER, M.HELMET]:
					c = c.lerp(pal[1], 0.35)
			img.set_pixel(x, y, c)
	return img


# ---- poses ---------------------------------------------------------------------------------------

func std(dx: int = 0, dy: int = 0) -> Dictionary:
	return {
		"sh": Vector2i(10 + dx, 9 + dy), "hip": Vector2i(10 + dx, 15 + dy),
		"legs": [[Vector2i(9 + dx, 19 + dy), Vector2i(9 + dx, 23)], [Vector2i(11 + dx, 19 + dy), Vector2i(11 + dx, 23)]],
		"arms": [[Vector2i(9 + dx, 13 + dy), Vector2i(9 + dx, 15 + dy)], [Vector2i(12 + dx, 13 + dy), Vector2i(12 + dx, 15 + dy)]],
	}


func poses() -> Dictionary:
	var P := {}
	# STOKER: shovel coal into a firebox to the right
	P["stoker"] = [
		{  # scoop, bent low
			"sh": Vector2i(13, 12), "hip": Vector2i(10, 16), "head_dx": 1,
			"legs": [[Vector2i(8, 19), Vector2i(7, 23)], [Vector2i(13, 19), Vector2i(13, 23)]],
			"arms": [[Vector2i(14, 15), Vector2i(16, 17)], [Vector2i(15, 14), Vector2i(18, 16)]],
			"mid": [["line", Vector2i(13, 13), Vector2i(20, 19), M.WOOD]],
			"over": [["rect", 20, 19, 4, 2, M.STEEL], ["px", 24, 20, M.STEEL], ["rect", 21, 18, 2, 1, M.COAL]],
		},
		{  # lift
			"sh": Vector2i(12, 10), "hip": Vector2i(10, 15),
			"legs": [[Vector2i(8, 19), Vector2i(7, 23)], [Vector2i(12, 19), Vector2i(13, 23)]],
			"arms": [[Vector2i(13, 13), Vector2i(15, 14)], [Vector2i(14, 12), Vector2i(17, 13)]],
			"mid": [["line", Vector2i(12, 12), Vector2i(20, 15), M.WOOD]],
			"over": [["rect", 21, 15, 4, 2, M.STEEL], ["rect", 21, 14, 3, 1, M.COAL], ["px", 22, 13, M.COAL]],
		},
		{  # throw, arms up and forward
			"sh": Vector2i(11, 9), "hip": Vector2i(10, 15),
			"legs": [[Vector2i(8, 19), Vector2i(7, 23)], [Vector2i(12, 19), Vector2i(13, 23)]],
			"arms": [[Vector2i(13, 10), Vector2i(15, 9)], [Vector2i(14, 9), Vector2i(17, 8)]],
			"mid": [["line", Vector2i(12, 11), Vector2i(20, 7), M.WOOD]],
			"over": [["rect", 21, 5, 3, 3, M.STEEL], ["px", 24, 4, M.COAL], ["px", 25, 6, M.COAL], ["px", 26, 3, M.COAL],
				["px", 26, 7, M.EMBER]],
		},
		{  # recover
			"sh": Vector2i(12, 10), "hip": Vector2i(10, 15),
			"legs": [[Vector2i(8, 19), Vector2i(7, 23)], [Vector2i(12, 19), Vector2i(13, 23)]],
			"arms": [[Vector2i(12, 13), Vector2i(14, 15)], [Vector2i(13, 13), Vector2i(16, 15)]],
			"mid": [["line", Vector2i(11, 13), Vector2i(19, 18), M.WOOD]],
			"over": [["rect", 20, 18, 4, 2, M.STEEL]],
		},
	]
	# LOADER walking with a shell held at the chest
	var shell := [["rect", 12, 12, 8, 2, M.BRASS], ["rect", 20, 12, 2, 2, M.MMETAL], ["px", 22, 12, M.MMETAL],
		["rect", 11, 12, 1, 2, M.BRASS_D]]
	var shell_up := [["rect", 12, 11, 8, 2, M.BRASS], ["rect", 20, 11, 2, 2, M.MMETAL], ["px", 22, 11, M.MMETAL],
		["rect", 11, 11, 1, 2, M.BRASS_D]]
	P["loader"] = [
		{
			"sh": Vector2i(11, 9), "hip": Vector2i(10, 15),
			"legs": [[Vector2i(8, 19), Vector2i(6, 23)], [Vector2i(12, 19), Vector2i(13, 23)]],
			"arms": [[Vector2i(12, 13), Vector2i(14, 14)], [Vector2i(13, 13), Vector2i(16, 14)]], "over": shell,
		},
		{
			"sh": Vector2i(11, 8), "hip": Vector2i(10, 14),
			"legs": [[Vector2i(10, 18), Vector2i(9, 23)], [Vector2i(11, 18), Vector2i(10, 22)]],
			"arms": [[Vector2i(12, 12), Vector2i(14, 13)], [Vector2i(13, 12), Vector2i(16, 13)]], "over": shell_up,
		},
		{
			"sh": Vector2i(11, 9), "hip": Vector2i(10, 15),
			"legs": [[Vector2i(11, 19), Vector2i(13, 23)], [Vector2i(9, 19), Vector2i(7, 23)]],
			"arms": [[Vector2i(12, 13), Vector2i(14, 14)], [Vector2i(13, 13), Vector2i(16, 14)]], "over": shell,
		},
		{
			"sh": Vector2i(11, 8), "hip": Vector2i(10, 14),
			"legs": [[Vector2i(11, 18), Vector2i(10, 22)], [Vector2i(10, 18), Vector2i(9, 23)]],
			"arms": [[Vector2i(12, 12), Vector2i(14, 13)], [Vector2i(13, 12), Vector2i(16, 13)]], "over": shell_up,
		},
	]
	# LOADER climbing (a ladder at x 14-17 in the hull art; the shell rides on his back)
	P["loader_climb"] = [
		{
			"sh": Vector2i(11, 8), "hip": Vector2i(11, 14),
			"legs": [[Vector2i(11, 18), Vector2i(12, 23)], [Vector2i(14, 16), Vector2i(14, 20)]],
			"arms": [[Vector2i(13, 10), Vector2i(15, 12)], [Vector2i(13, 6), Vector2i(15, 4)]],
			"under": [["rect", 7, 8, 2, 8, M.BRASS], ["rect", 7, 6, 2, 2, M.MMETAL], ["rect", 7, 16, 2, 1, M.BRASS_D]],
		},
		{
			"sh": Vector2i(11, 7), "hip": Vector2i(11, 13),
			"legs": [[Vector2i(14, 15), Vector2i(14, 19)], [Vector2i(11, 17), Vector2i(12, 22)]],
			"arms": [[Vector2i(13, 5), Vector2i(15, 3)], [Vector2i(13, 10), Vector2i(15, 11)]],
			"under": [["rect", 7, 7, 2, 8, M.BRASS], ["rect", 7, 5, 2, 2, M.MMETAL], ["rect", 7, 15, 2, 1, M.BRASS_D]],
		},
	]
	# ENGINEER with a big wrench on a bolt to the right
	P["engineer"] = [
		{
			"sh": Vector2i(11, 9), "hip": Vector2i(10, 15),
			"legs": [[Vector2i(9, 19), Vector2i(8, 23)], [Vector2i(12, 19), Vector2i(13, 23)]],
			"arms": [[Vector2i(12, 12), Vector2i(14, 12)], [Vector2i(14, 10), Vector2i(16, 8)]],
			"over": [["line", Vector2i(16, 9), Vector2i(17, 4), M.STEEL], ["rect", 16, 3, 3, 1, M.STEEL], ["px", 16, 2, M.STEEL],
				["px", 18, 2, M.STEEL]],
		},
		{
			"sh": Vector2i(11, 9), "hip": Vector2i(10, 15),
			"legs": [[Vector2i(9, 19), Vector2i(8, 23)], [Vector2i(12, 19), Vector2i(13, 23)]],
			"arms": [[Vector2i(12, 12), Vector2i(14, 12)], [Vector2i(14, 11), Vector2i(16, 11)]],
			"over": [["line", Vector2i(16, 11), Vector2i(21, 11), M.STEEL], ["rect", 21, 10, 1, 3, M.STEEL], ["px", 22, 10, M.STEEL],
				["px", 22, 12, M.STEEL], ["px", 23, 9, M.EMBER]],
		},
		{
			"sh": Vector2i(11, 10), "hip": Vector2i(10, 16), "head_dy": 0,
			"legs": [[Vector2i(8, 19), Vector2i(8, 23)], [Vector2i(13, 19), Vector2i(13, 23)]],
			"arms": [[Vector2i(12, 13), Vector2i(14, 14)], [Vector2i(14, 13), Vector2i(16, 14)]],
			"over": [["line", Vector2i(16, 14), Vector2i(19, 18), M.STEEL], ["rect", 19, 18, 3, 1, M.STEEL], ["px", 19, 19, M.STEEL],
				["px", 21, 19, M.STEEL]],
		},
	]
	# GUNNER on the elevation handwheel at the breech
	var post := [["rect", 18, 13, 2, 10, M.DMETAL], ["rect", 16, 23, 6, 1, M.DMETAL], ["rect", 20, 6, 8, 5, M.DMETAL],
		["rect", 21, 7, 4, 1, M.BRASS_D], ["rect", 26, 11, 1, 2, M.DMETAL]]
	P["gunner"] = [
		{
			"sh": Vector2i(11, 9), "hip": Vector2i(10, 15),
			"legs": [[Vector2i(9, 19), Vector2i(8, 23)], [Vector2i(12, 19), Vector2i(12, 23)]],
			"arms": [[Vector2i(13, 12), Vector2i(15, 13)], [Vector2i(14, 10), Vector2i(16, 10)]],
			"under": post, "over": [["wheel", Vector2i(18, 12), 0.0, M.MMETAL]],
		},
		{
			"sh": Vector2i(11, 9), "hip": Vector2i(10, 15),
			"legs": [[Vector2i(9, 19), Vector2i(8, 23)], [Vector2i(12, 19), Vector2i(12, 23)]],
			"arms": [[Vector2i(13, 12), Vector2i(15, 11)], [Vector2i(14, 11), Vector2i(16, 14)]],
			"under": post, "over": [["wheel", Vector2i(18, 12), 30.0, M.MMETAL]],
		},
		{
			"sh": Vector2i(11, 9), "hip": Vector2i(10, 15),
			"legs": [[Vector2i(9, 19), Vector2i(8, 23)], [Vector2i(12, 19), Vector2i(12, 23)]],
			"arms": [[Vector2i(13, 11), Vector2i(15, 15)], [Vector2i(14, 10), Vector2i(16, 12)]],
			"under": post, "over": [["wheel", Vector2i(18, 12), 60.0, M.MMETAL]],
		},
	]
	# COMMANDER on the turret roof working a searchlight on a pedestal to the right
	P["commander"] = [
		{
			"sh": Vector2i(11, 9), "hip": Vector2i(10, 15),
			"legs": [[Vector2i(9, 19), Vector2i(8, 23)], [Vector2i(12, 19), Vector2i(12, 23)]],
			"arms": [[Vector2i(13, 12), Vector2i(15, 11)], [Vector2i(14, 10), Vector2i(16, 9)]],
			"under": [["rect", 18, 12, 2, 11, M.DMETAL], ["rect", 16, 23, 6, 1, M.DMETAL]],
			"over": [["rect", 16, 7, 6, 5, M.MMETAL], ["rect", 22, 7, 1, 5, M.LENS], ["rect", 17, 6, 3, 1, M.DMETAL],
				["px", 23, 8, M.LENS], ["px", 23, 10, M.LENS]],
		},
		{
			"sh": Vector2i(11, 9), "hip": Vector2i(10, 15),
			"legs": [[Vector2i(9, 19), Vector2i(8, 23)], [Vector2i(12, 19), Vector2i(12, 23)]],
			"arms": [[Vector2i(13, 12), Vector2i(15, 12)], [Vector2i(14, 11), Vector2i(16, 11)]],
			"under": [["rect", 18, 12, 2, 11, M.DMETAL], ["rect", 16, 23, 6, 1, M.DMETAL]],
			"over": [["line", Vector2i(16, 10), Vector2i(20, 6), M.MMETAL, 2], ["line", Vector2i(17, 11), Vector2i(21, 7), M.MMETAL, 2],
				["line", Vector2i(16, 9), Vector2i(19, 6), M.MMETAL], ["line", Vector2i(21, 5), Vector2i(23, 7), M.LENS, 2]],
		},
		{
			"sh": Vector2i(11, 9), "hip": Vector2i(10, 15),
			"legs": [[Vector2i(9, 19), Vector2i(8, 23)], [Vector2i(12, 19), Vector2i(12, 23)]],
			"arms": [[Vector2i(13, 11), Vector2i(15, 10)], [Vector2i(14, 9), Vector2i(16, 8)]],
			"under": [["rect", 18, 12, 2, 11, M.DMETAL], ["rect", 16, 23, 6, 1, M.DMETAL]],
			"over": [["line", Vector2i(16, 8), Vector2i(20, 11), M.MMETAL, 2], ["line", Vector2i(16, 9), Vector2i(19, 12), M.MMETAL, 2],
				["line", Vector2i(17, 7), Vector2i(20, 10), M.MMETAL], ["line", Vector2i(21, 11), Vector2i(22, 13), M.LENS, 2],
				["px", 21, 10, M.LENS]],
		},
	]
	# TECH at a dynamo panel to the right (lamps blink per frame)
	var cab := [["rect", 16, 5, 8, 14, M.MMETAL], ["rect", 17, 6, 6, 12, M.DMETAL], ["rect", 18, 19, 2, 4, M.DMETAL],
		["rect", 21, 19, 2, 4, M.DMETAL], ["rect", 16, 23, 8, 1, M.DMETAL], ["rect", 18, 12, 4, 2, M.STEEL],
		["rect", 18, 15, 1, 2, M.STEEL], ["rect", 21, 15, 1, 2, M.STEEL]]
	P["tech"] = [
		{
			"sh": Vector2i(11, 9), "hip": Vector2i(10, 15),
			"legs": [[Vector2i(9, 19), Vector2i(8, 23)], [Vector2i(12, 19), Vector2i(12, 23)]],
			"arms": [[Vector2i(12, 13), Vector2i(13, 15)], [Vector2i(14, 11), Vector2i(17, 10)]],
			"under": cab + [["px", 18, 8, M.LED_G], ["px", 20, 8, M.LED_A], ["px", 22, 8, M.LED_G], ["px", 19, 10, M.LED_R]],
		},
		{
			"sh": Vector2i(11, 9), "hip": Vector2i(10, 15),
			"legs": [[Vector2i(9, 19), Vector2i(8, 23)], [Vector2i(12, 19), Vector2i(12, 23)]],
			"arms": [[Vector2i(12, 13), Vector2i(13, 15)], [Vector2i(14, 12), Vector2i(17, 13)]],
			"under": cab + [["px", 18, 8, M.LED_A], ["px", 20, 8, M.LED_G], ["px", 22, 8, M.LED_G], ["px", 21, 10, M.LED_G]],
		},
		{
			"sh": Vector2i(11, 9), "hip": Vector2i(10, 15),
			"legs": [[Vector2i(9, 19), Vector2i(8, 23)], [Vector2i(12, 19), Vector2i(12, 23)]],
			"arms": [[Vector2i(13, 11), Vector2i(16, 8)], [Vector2i(14, 12), Vector2i(17, 15)]],
			"under": cab + [["px", 18, 8, M.LED_G], ["px", 20, 8, M.LED_G], ["px", 22, 8, M.LED_R], ["px", 19, 10, M.LED_A]],
		},
	]
	# IDLE crew in the quarters (stand, then a smoke)
	var idle0 := std()
	var idle1 := std()
	idle1["arms"] = [[Vector2i(9, 13), Vector2i(9, 15)], [Vector2i(13, 12), Vector2i(13, 9)]]
	idle1["over"] = [["px", 14, 8, M.EMBER]]
	var idle2 := std(0, 0)
	idle2["arms"] = [[Vector2i(9, 13), Vector2i(10, 15)], [Vector2i(13, 12), Vector2i(14, 13)]]
	idle2["over"] = [["px", 15, 13, M.EMBER]]
	P["idle"] = [idle0, idle1, idle2]
	# SPOTTER with binoculars (turret roof)
	var sp0 := std()
	sp0["arms"] = [[Vector2i(12, 11), Vector2i(13, 8)], [Vector2i(13, 11), Vector2i(14, 8)]]
	sp0["over"] = [["rect", 13, 7, 3, 2, M.BINO]]
	var sp1 := std()
	sp1["arms"] = [[Vector2i(12, 11), Vector2i(13, 9)], [Vector2i(13, 11), Vector2i(14, 9)]]
	sp1["over"] = [["rect", 13, 7, 3, 2, M.BINO]]
	sp1["head_dx"] = 0
	var sp2 := std()
	sp2["arms"] = [[Vector2i(9, 13), Vector2i(9, 15)], [Vector2i(13, 12), Vector2i(14, 11)]]
	sp2["over"] = [["rect", 14, 11, 2, 2, M.BINO]]
	P["spotter"] = [sp0, sp1, sp2]
	return P


func _init() -> void:
	var dir := OUT + "crew20/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var P := poses()
	var names: Array = P.keys()
	var meta := {"cell": [CW, CH], "feet_row": 23, "facing": "right", "figure_height_px": "19-20", "frames": {},
		"commander_lens_px": {"0": [22, 9], "1": [22, 6], "2": [22, 12]},
		"commander_beam_angle_deg": {"0": 0, "1": -32, "2": 28},
		"note": "anchor a frame at its feet: cell x 10 (hips), row 23 on the floor. Face right; mirror for left."}
	# 1x sheet: one row per pose
	var sheet := Image.create(10 + 4 * (CW + 4) + 70, 10 + names.size() * (CH + 4), false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(18, 16, 14))
	var sc := 4
	var big := Image.create(130 + 4 * (CW * sc + 8), 30 + names.size() * (CH * sc + 14), false, Image.FORMAT_RGBA8)
	big.fill(Color8(18, 16, 14))
	F.draw(big, 6, 6, "CREW20: 30X24 CELLS, FIGURES 19-20 PX TALL AT 960X540 (THE REFERENCE SIZE), FEET ROW 23, FACING RIGHT. 4X", Color8(200, 190, 170))
	var wall := Color8(132, 96, 58)
	for pi in names.size():
		var nm: String = names[pi]
		var frames: Array = P[nm]
		var paths: Array = []
		F.draw(sheet, 2, 4 + pi * (CH + 4) + 8, nm.substr(0, 7), Color8(200, 180, 140))
		F.draw(big, 6, 30 + pi * (CH * sc + 14) + 10, nm.replace("_", " "), Color8(230, 210, 160), 2)
		F.draw(big, 6, 30 + pi * (CH * sc + 14) + 26, "%d FRAMES" % frames.size(), Color8(150, 140, 120))
		for fi in frames.size():
			clear()
			figure(frames[fi])
			var img := render()
			var p := dir + "%s_%d.png" % [nm, fi]
			img.save_png(p)
			paths.append("crew20/%s_%d.png" % [nm, fi])
			var sx := 40 + fi * (CW + 4)
			var sy := 4 + pi * (CH + 4)
			sheet.fill_rect(Rect2i(sx, sy, CW, CH), wall.darkened(0.15 * float(fi % 2)))
			sheet.blend_rect(img, Rect2i(0, 0, CW, CH), Vector2i(sx, sy))
			var b := img.duplicate()
			b.resize(CW * sc, CH * sc, Image.INTERPOLATE_NEAREST)
			var bx := 130 + fi * (CW * sc + 8)
			var by := 30 + pi * (CH * sc + 14)
			big.fill_rect(Rect2i(bx, by, CW * sc, CH * sc), wall)
			big.blend_rect(b, Rect2i(0, 0, CW * sc, CH * sc), Vector2i(bx, by))
		meta["frames"][nm] = paths
	sheet.save_png(BUILD + "crew20_sheet.png")
	big.save_png(BUILD + "crew20_sheet_4x.png")
	var fa := FileAccess.open(BUILD + "crew20.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(meta, "  ", false))
	fa.close()
	print("crew20: ", names)
	quit()
