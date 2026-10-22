class_name SiegeRushStrip
extends Control
## The rush-marker strip under the timeline (brief 3 HUD): in a wave with endurance rushes, a bar
## that fills with the wave's clock and a diamond at each rush (hollow and dim once past, solid
## for the next, the whole bar lit while a rush is on). Hidden in shifts and phases without
## rushes. Shape plus position, not color alone, tells the markers apart.

const BAR_H := 18.0
const HEIGHT := 56.0
const WIDTH := 440.0

var game: SiegeGame = null
## Marker fractions and the wave's progress (0..1) as of the last refresh (tests read these).
var fractions: Array[float] = []
var progress: float = 0.0
var rush_on: bool = false
var next_index: int = -1


func _init() -> void:
	name = "SiegeRushStrip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	visible = false


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	var s := game.state if game != null else null
	fractions = SiegeHudModel.rush_fractions(game) if s != null else ([] as Array[float])
	visible = not fractions.is_empty() and s != null and s.in_wave()
	if not visible:
		return
	var d := SiegeHudModel.phase_duration_s(game)
	progress = clampf(s.phase_elapsed_s / d, 0.0, 1.0) if d > 0.0 else 0.0
	rush_on = s.rush_on()
	next_index = -1
	for i in fractions.size():
		if fractions[i] > progress:
			next_index = i
			break
	queue_redraw()


func _draw() -> void:
	if fractions.is_empty():
		return
	var font := WlTheme.font()
	var tx := SiegeHudModel.strings_of(game)
	var caption := tx.t("SIEGE_HUD_RUSH_ON") if rush_on else tx.t("SIEGE_HUD_RUSHES")
	var cap_col := WlTheme.WARN if rush_on else WlTheme.TEXT_DIM
	draw_string(
		font, Vector2(2, 22), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, WlTheme.LABEL_PX, cap_col
	)
	var y := 32.0
	var w := size.x - 8.0
	draw_rect(Rect2(4, y, w, BAR_H), WlTheme.BAR_BG)
	draw_rect(Rect2(4, y, w * progress, BAR_H), WlTheme.WARN if rush_on else WlTheme.BAR_FILL)
	for i in fractions.size():
		var x := 4.0 + w * fractions[i]
		var c := Vector2(x, y + BAR_H * 0.5)
		var r := 11.0 if i == next_index else 8.0
		var pts := PackedVector2Array(
			[c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]
		)
		var past := fractions[i] <= progress
		var col := WlTheme.TEXT_DIM if past else WlTheme.WARN
		if past:
			pts.append(pts[0])
			draw_polyline(pts, col, 2.5)
		else:
			draw_colored_polygon(pts, col)
			pts.append(pts[0])
			draw_polyline(pts, WlTheme.OUTLINE, 2.0)
