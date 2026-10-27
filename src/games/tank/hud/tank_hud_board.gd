class_name TankHudBoard
extends TankHudCtl
## The free-roam board, top right (brief 2.10, 3.6; TankHud.LAYOUT "roam_board", 200 x 44 art px):
## the time left as a key number (OVERTIME in red past time up while a fight finishes), the crew's
## points and kills. It draws only what its setters gave it; the roam builder feeds them. Put the
## hull plate without its kills (TankHudHull.show_kills = false) at "roam_hull" under it.

## Seconds left of the ride (<= 0: time up).
var left_s: float = 0.0
## A fight runs past time up.
var overtime: bool = false
var points: int = 0
var kills: int = 0


func set_time(p_left_s: float, p_overtime: bool) -> void:
	left_s = maxf(p_left_s, 0.0)
	overtime = p_overtime


func set_score(p_points: int, p_kills: int) -> void:
	points = p_points
	kills = p_kills


## It draws from its setters, not from the state.
func has_state() -> bool:
	return true


func paint() -> void:
	var w := float(art_rect.size.x)
	var h := float(art_rect.size.y)
	D.plate(self, Rect2(0, 0, w, h))
	if overtime:
		D.tall(self, 6, 4, tx("TANK_HUD_OVERTIME"), D.OVER)
	else:
		D.tall(self, 6, 4, tx("TANK_HUD_TIME_LEFT"), D.DIM)
	D.big(self, 6, 16, D.clock(left_s), D.OVER if overtime else D.NUM)
	D.rect(self, Rect2(88, 6, 1, h - 12), D.FRAME_IN)
	D.tall(self, 94, 4, tx("TANK_HUD_POINTS"), D.DIM)
	D.text(self, 94, 21, thousands(points), D.AMBER, 2)
	D.rect(self, Rect2(150, 6, 1, h - 12), D.FRAME_IN)
	D.tall(self, 156, 4, tx("TANK_HUD_KILLS"), D.DIM)
	D.text(self, 156, 21, str(kills), D.NUM, 2)


## `n` with a thin space every three digits ("12 340").
static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
