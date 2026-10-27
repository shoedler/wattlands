class_name TankHudBoss
extends TankHudCtl
## The Behemoth's bars under the hull plate (250 x 40 art px; brief 3.6), shown only while it is
## up: its three bogies (rear to front) and its turret as bars, a broken bogie crossed out, and
## while its main gun telegraphs a red frame, a blinking warning triangle and MAIN GUN (the world
## tag over the gun says SURGE TO EVADE). Data: TankHudModel.boss_bars().

const W := 250
const H := 40
const LOW := 0.34
const TRI := ["..#..", "..#..", ".#.#.", ".#.#.", "#...#", "#####"]

var m: Dictionary = {}


func refresh() -> void:
	m = TankHudModel.boss_bars(st())


func paint() -> void:
	if not bool(m.get("show", false)):
		return
	var tele := bool(m.get("telegraph", false))
	D.plate(self, Rect2(0, 0, W, H), D.OVER if tele else D.FRAME)
	D.tall(self, 6, 4, tx("TANK_HUD_BEHEMOTH"), D.AMBER)
	if bool(m.get("dead", false)):
		D.tall_r(self, W - 6, 4, tx("TANK_HUD_DESTROYED"), D.AMBER)
	elif tele:
		var on := bool(m.get("blink", false))
		var tw := D.tall_r(self, W - 6, 4, tx("TANK_HUD_MAIN_GUN"), D.OVER if on else D.TEXT)
		D.pixels(self, TRI, Vector2(W - 6 - tw - 9, 6), D.OVER if on else D.TEXT)
	var bogies: Array = m["bogies"]
	var bw := 40.0
	D.tall(self, 6, 16, tx("TANK_HUD_BOGIES").to_upper(), D.DIM)
	for i in bogies.size():
		var f := float(bogies[i])
		var r := Rect2(6 + i * (bw + 4), 28, bw, 6)
		D.bar(self, r, f, D.OVER if f < LOW else D.BRASS)
		if f <= 0.0:
			for k in 6:
				D.rect(self, Rect2(r.position.x + 17 + k, r.position.y + k, 1, 1), D.OVER)
				D.rect(self, Rect2(r.position.x + 22 - k, r.position.y + k, 1, 1), D.OVER)
	var tx0 := 6 + 3 * (bw + 4) + 6
	var tf := float(m["turret"])
	D.tall(self, tx0, 16, tx("TANK_HUD_TURRET").to_upper(), D.DIM)
	D.bar(self, Rect2(tx0, 28, W - 6 - tx0, 6), tf, D.OVER if tf < LOW else D.BRASS)
