class_name TankHudHull
extends TankHudCtl
## The hull plate, top right (136 x 48 art px, small so it covers little of the cliff; brief 3.6):
## the hull as a key number over its maximum ("136/140") with a thin bar under it (red under a
## third), BREAKDOWN in red while the tank is broken down, and the crew's kills. Under the free-roam
## board (show_kills false) it is the hull alone. The Behemoth's bars are TankHudBoss under it.

const LOW := 0.34

## False under the roam board (which shows the kills itself).
var show_kills: bool = true
var m: Dictionary = {}


func refresh() -> void:
	var s := st()
	m = {
		"hp": s.hull.hp,
		"max": maxf(s.hull.hp_max, 1.0),
		"kills": TankHudModel.kills(s),
		"breakdown": s.hull.breakdown,
	}


func paint() -> void:
	if m.is_empty():
		return
	var w := float(art_rect.size.x)
	var h := float(art_rect.size.y)
	D.plate(self, Rect2(0, 0, w, h))
	var hp := float(m["hp"])
	var frac := clampf(hp / float(m["max"]), 0.0, 1.0)
	var low := frac < LOW
	var broken := bool(m["breakdown"])
	var label := tx("TANK_HUD_BREAKDOWN") if broken else tx("TANK_HUD_HULL").to_upper()
	D.tall(self, 6, 5, label, D.OVER if broken else D.DIM)
	var nw := D.big(self, 6, 16, str(ceili(hp)), D.OVER if low else D.NUM)
	var mw := D.tall(self, 6 + nw + 2, 31, "/%d" % roundi(float(m["max"])), D.DIM)
	var bar_w := nw + 2 + mw
	D.bar(self, Rect2(6, 42, bar_w, 2), frac, D.OVER if low else D.BRASS)
	if not show_kills:
		return
	var dx := roundf(bar_w + 14)
	D.rect(self, Rect2(dx - 6, 6, 1, h - 12), D.FRAME_IN)
	D.tall(self, dx, 5, tx("TANK_HUD_KILLS"), D.DIM)
	D.big(self, dx, 16, str(int(m["kills"])), D.AMBER)
