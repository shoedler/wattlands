class_name SiegeHudSession
extends SiegeHudCtl
## The session plate, top left: the title plaque, ENDS IN with the cool-down, the session's profile
## strip (block height as effort, the current block framed, a playhead, the rushes as ticks), and,
## in a wave, the enemies as icons with counts and the road's news in plain cream.

const RECT := Rect2i(150, 8, 260, 76)
const W := 258
const H_SHORT := 52
const H_TALL := 72
const STRIP_X := 8
const STRIP_Y := 26
const STRIP_W := W - 16
const STRIP_H := 18
const ROW_Y := 54
const PAST_ALPHA := 0.4


func build() -> Dictionary:
	return SiegeHudModel.session_face(game)


func paint() -> void:
	var enemies: Array = model["enemies"]
	var warning := str(model["warning"])
	var tall := not enemies.is_empty() or warning != ""
	D.plate(self, 0, 0, W, H_TALL if tall else H_SHORT)
	D.ansata(self, 10, 5, str(model["title"]))
	SiegeHudType.draw_r(self, str(model["ends"]), W - 8, 9, "LABEL", D.DIM)
	_strip()
	if tall:
		D.rect(self, 3, 49, W - 6, 1, D.WAX_LINE)
		_road(enemies, warning)


func _strip() -> void:
	var total := maxf(float(model["total_s"]), 1.0)
	var elapsed := float(model["elapsed_s"])
	var index := int(model["index"])
	var phases: Array = model["phases"]
	for i in phases.size():
		var p: Dictionary = phases[i]
		var from := float(p["from_s"])
		var end := from + float(p["d"])
		var bx := STRIP_X + roundi(from / total * STRIP_W)
		var bw := STRIP_X + roundi(end / total * STRIP_W) - bx
		var col := _kind_color(str(p["kind"]))
		if end <= elapsed:
			col.a = PAST_ALPHA
		_block(bx, bw, float(p["p0"]), float(p["p1"]), col)
		if i == index:
			_frame(bx, bw)
	for t: float in model["rush"]:
		var rx := STRIP_X + roundi(t / total * STRIP_W)
		D.rect(self, rx, STRIP_Y - 1, 1, 3, D.AMBER)
	var px := STRIP_X + roundi(clampf(elapsed / total, 0.0, 1.0) * STRIP_W)
	D.rect(self, px, STRIP_Y - 3, 1, STRIP_H + 6, D.TEXT)


## One phase's block, its height the effort (one column at a time on a ramp).
func _block(bx: int, bw: int, p0: float, p1: float, col: Color) -> void:
	if is_equal_approx(p0, p1):
		var h := _height(p0)
		D.rect(self, bx + 1, STRIP_Y + STRIP_H - h, bw - 1, h, col)
		return
	for c in range(1, bw):
		var h := _height(lerpf(p0, p1, float(c) / float(bw)))
		D.rect(self, bx + c, STRIP_Y + STRIP_H - h, 1, h, col)


func _height(pct: float) -> int:
	return mini(roundi(pct / 100.0 * STRIP_H), STRIP_H)


func _frame(bx: int, bw: int) -> void:
	D.rect(self, bx, STRIP_Y - 1, bw + 1, 1, D.BRONZE_HI)
	D.rect(self, bx, STRIP_Y + STRIP_H, bw + 1, 1, D.BRONZE_HI)
	D.rect(self, bx, STRIP_Y - 1, 1, STRIP_H + 2, D.BRONZE_HI)
	D.rect(self, bx + bw, STRIP_Y - 1, 1, STRIP_H + 2, D.BRONZE_HI)


static func _kind_color(kind: String) -> Color:
	match kind:
		Wl.WORK:
			return SiegeHudDraw.TERRA
		Wl.WARMUP, Wl.COOLDOWN:
			return SiegeHudDraw.WARM
	return SiegeHudDraw.VERD


## The road's news: icons with counts from the left, the warning from the right; an icon that would
## run into the warning is left out (engines come first, so they are the last to go).
func _road(enemies: Array, warning: String) -> void:
	var right := W - 8
	if warning != "":
		warning = SiegeHudType.fit(warning, "LABEL", W - 16)
		right = SiegeHudType.draw_r(self, warning, W - 8, ROW_Y + 2, "LABEL", D.TEXT) - 6
	var cx := 9
	for e: Dictionary in enemies:
		var count := str(int(e["n"]))
		var need := 14 + SiegeHudType.width(count, "LABEL")
		if cx + need > right:
			break
		D.icon(self, str(e["icon"]), cx, ROW_Y, D.TEXT if bool(e["warn"]) else D.STONE)
		cx = SiegeHudType.draw(self, count, cx + 14, ROW_Y + 2, "LABEL", D.TEXT) + 8
