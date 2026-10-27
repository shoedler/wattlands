class_name TankHudMission
extends TankHudCtl
## The mission plate, top left (200 x 72 art px; brief 3.6): the segment's name, the time left in
## the stage as a key number (to its nominal end, or to the latest end of an open-ended one), the
## objective where no other element shows it (the gun line's guns, Regroup; the halt distance is on
## the world post, the Behemoth on its bars), a compact stage strip of the whole mission (one block
## per segment by its nominal length, coloured by type, past ones dark, the current one outlined
## with its progress) and the next segment. Data: TankHudModel.mission().

const W := 200
const H := 72
const TYPE_COL := {
	"depot": Color("#4a3f2e"),
	"advance": Color("#9c7a42"),
	"gun_line": Color("#8c3b2a"),
	"checkpoint": Color("#5c5446"),
	"boss": Color("#c4553c"),
	"skirmish": Color("#8c3b2a"),
}

var m: Dictionary = {}


func refresh() -> void:
	m = TankHudModel.mission(st())


func paint() -> void:
	if m.is_empty():
		return
	D.plate(self, Rect2(0, 0, W, H))
	var title := D.fit_tall(tx(str(m["title"])).to_upper(), W - 12.0)
	D.tall(self, 6, 5, title, D.AMBER)
	D.big(self, 6, 18, D.clock(float(m["left_s"])), D.NUM)
	if str(m["obj_key"]) != "":
		var warn := bool(m["warn"])
		D.tall_r(self, W - 6, 18, tx(str(m["obj_key"])).to_upper(), D.OVER if warn else D.DIM)
		if str(m["obj_value"]) != "":
			D.text_r(self, W - 6, 29, str(m["obj_value"]), D.NUM, 2)
	_strip(Rect2(6, 47, W - 12, 6))
	if str(m["next"]) != "":
		var nw := D.tall(self, 6, 58, tx("TANK_HUD_NEXT"), D.AMBER)
		D.tall(self, 6 + nw + 6, 58, D.fit_tall(tx(str(m["next"])), W - 18.0 - nw), D.DIM)


func _strip(sr: Rect2) -> void:
	var blocks: Array = m["blocks"]
	var total := 0.0
	for b: Dictionary in blocks:
		total += float(b["len"])
	var x := sr.position.x
	var idx := int(m["index"])
	var cur_r := Rect2()
	for k in blocks.size():
		var b: Dictionary = blocks[k]
		var bw := roundf(sr.size.x * float(b["len"]) / maxf(total, 1.0))
		if k == blocks.size() - 1:
			bw = sr.end.x - x
		var col: Color = TYPE_COL.get(str(b["type"]), D.TRACK)
		if k < idx:
			col = col.darkened(0.55)
		elif k > idx:
			col = col.darkened(0.15)
		var br := Rect2(x, sr.position.y, maxf(bw - 1, 1), sr.size.y)
		D.rect(self, br, col)
		if k == idx:
			cur_r = br
		x += bw
	if cur_r.size.x > 0:
		var px := cur_r.position.x + roundf(cur_r.size.x * float(m["progress"]))
		var done := Rect2(cur_r.position, Vector2(px - cur_r.position.x, cur_r.size.y))
		D.rect(self, done, D.AMBER)
		D.frame(self, cur_r.grow(1), D.TEXT)
		D.rect(self, Rect2(px, cur_r.position.y - 2, 1, cur_r.size.y + 4), D.TEXT)
