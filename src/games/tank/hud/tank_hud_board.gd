class_name TankHudBoard
extends TankHudCtl
## The free-roam board, top right (brief 2.10, 3.6; TankHud.LAYOUT "roam_board", 200 x 44 art px):
## the time left as a key number (OVERTIME in red past time up while a fight finishes), the crew's
## points and kills. It draws only what its setters gave it; refresh() feeds them from the state
## (feed()). The hull plate without its kills (TankHudHull.show_kills = false) sits at "roam_hull"
## under it.

## Seconds left of the ride (<= 0: time up).
var left_s: float = 0.0
## A fight runs past time up.
var overtime: bool = false
var points: int = 0
var kills: int = 0


func refresh() -> void:
	if game != null and game.state != null:
		feed(game.state)


## Feeds the setters from `s` (free roam only): the ride's time left (the drive-out's rest plus the
## roam's min_s, 0 past time up; OVERTIME while a fight finishes), the points and the kills.
func feed(s: TankState) -> void:
	if not s.roam.active:
		return
	set_time(time_left_s(s), s.roam.overtime)
	set_score(s.roam.points, TankHudModel.kills(s))


## Seconds of the ride left before time up (the drive-out counts toward it).
static func time_left_s(s: TankState) -> float:
	if s.content == null or s.roam.time_up or s.in_cooldown():
		return 0.0
	var segs := s.content.segments()
	if segs.size() < 2:
		return 0.0
	var roam_min := float((segs[1] as Dictionary).get("min_s", 0.0))
	if s.seg.seg == TankIds.SEG_DEPOT:
		var out_s := float((segs[0] as Dictionary).get("duration_s", 0.0))
		return maxf(out_s - s.seg.elapsed_s, 0.0) + roam_min
	return maxf(roam_min - s.seg.elapsed_s, 0.0)


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
