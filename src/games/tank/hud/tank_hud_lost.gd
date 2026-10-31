class_name TankHudLost
extends TankHudCtl
## TANK LOST (v4; TankHud.LAYOUT "lost", over the sky above the banners, clear of the rescue banner):
## a red-iron plate while the tank is towed back (hull.tow_s) and HOLD_S after it: TANK_HUD_LOST in the
## tall face, the tow's countdown (TANK_HUD_TOW) with a thin bar of what is left, and one pip per tank
## lost this ride. The plan runs on underneath: my numbers say KEEP RIDING, the crew pedals on.

## How long the plate stays once the tow is over (wall clock, s).
const HOLD_S := 1.5
## The tow when the content has no length (tanks.json hull.tow_s).
const TOW_S := 8.0
const PIPS_MAX := 12
const IRON := Color("#3a1410")
const IRON_LIP := Color("#55201a")
const IRON_RIM := Color("#c4553c")
const PIP_W := 5.0

## What is left of the hold after the tow (s), run down by tick().
var hold_s: float = 0.0
var m: Dictionary = {}


func tick(delta: float) -> void:
	if has_state():
		hold_s = next_hold(hold_s, st().hull.tow_s, delta)


## The hold after `dt` s from `hold`, the tow's `tow_s` left: full while towed, then running out.
static func next_hold(hold: float, tow_s: float, dt: float) -> float:
	return HOLD_S if tow_s > 0.0 else maxf(hold - dt, 0.0)


## True while the plate shows.
func showing() -> bool:
	return has_state() and (st().hull.tow_s > 0.0 or hold_s > 0.0)


func refresh() -> void:
	if not showing():
		m = {}
		return
	var s := st()
	var total := s.content.num("tanks", "hull.tow_s", TOW_S) if s.content != null else TOW_S
	m = {
		"tow": s.hull.tow_s,
		"frac": clampf(s.hull.tow_s / maxf(total, 0.1), 0.0, 1.0),
		"losses": s.score.losses,
	}


func paint() -> void:
	if m.is_empty():
		return
	var w := float(art_rect.size.x)
	var h := float(art_rect.size.y)
	var r := Rect2(0, 0, w, h)
	D.rect(self, r, IRON)
	D.rect(self, Rect2(2, 2, w - 4, 1), IRON_LIP)
	D.frame(self, r, IRON_RIM)
	D.frame(self, r.grow(-1), D.PANEL)
	for p: Vector2 in [Vector2(3, 3), Vector2(w - 5, 3), Vector2(3, h - 5), Vector2(w - 5, h - 5)]:
		D.rivet(self, p)
	D.tall_c(self, w * 0.5, 6, tx("TANK_HUD_LOST"), D.TEXT)
	var tow := float(m["tow"])
	if tow > 0.0:
		D.tall(self, 10, 20, tx("TANK_HUD_TOW", [ceili(tow - 1e-6)]), D.AMBER)
		D.bar(self, Rect2(10, h - 5, w - 20, 1), float(m["frac"]), D.AMBER, D.PANEL)
	_pips(Vector2(w - 10.0, 21.0))


## One pip per tank lost, right to left from `end`.
func _pips(end: Vector2) -> void:
	var n := mini(int(m["losses"]), PIPS_MAX)
	for i in n:
		D.rect(self, Rect2(end.x - (i + 1) * (PIP_W + 2.0) + 2.0, end.y, PIP_W, 5), D.OVER)
