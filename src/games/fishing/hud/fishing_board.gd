class_name FishingBoard
extends FishingHudControl
## The leaderboard at the top right: time left (or "Time is up" / overtime) and one row per
## rider, most points first: the action icon in the player colour, the name, the action word
## and the points (Free Roam competes; in workouts the rows still show who is doing what).

const ART := Rect2i(424, 2, 212, 42)
## Padding (glyph pixels) round the rows, the row pitch (glyph pixels: the line boxes' leading
## overlaps the row above), the icon's width and where the status column starts (a fraction
## of the width).
const PAD_ROWS := 3.0
const PITCH_ROWS := 10.0
const ICON_COLS := 11.0
const STATUS_AT := 0.55

var time_text: String = ""
var rows: Array[Dictionary] = []
var _t: float = 0.0


static func make(p_game: FishingGame) -> FishingBoard:
	var b := FishingBoard.new()
	b.game = p_game
	b.name = "FishingBoard"
	b.design_h = float(ART.size.y * 3)
	return b


func refresh() -> void:
	_t += get_process_delta_time()
	time_text = FishingHudModel.time_text(game)
	rows = FishingHudModel.board(game)


func _draw() -> void:
	if game == null or game.state == null:
		return
	var s := k()
	var u := float(FishingHudDraw.unit(s))
	var pad := PAD_ROWS * u
	var pitch := PITCH_ROWS * u
	var h := 2.0 * pad + pitch * float(rows.size()) + float(FishingHudDraw.LINE_ROWS) * u
	FishingHudDraw.panel(self, Rect2(Vector2.ZERO, Vector2(size.x, h)))
	FishingHudDraw.text_line(self, pad, pad, time_text, s, FishingPalette.HUD_TEXT)
	var status_x := roundf(size.x * STATUS_AT / u) * u
	var y := pad + pitch
	for row in rows:
		var col := FishingPalette.player(int(row["slot"]))
		var icon := FishingHudModel.icon_of(int(row["action"]))
		FishingHudDraw.icon(self, icon, floori(_t * 4.0), Vector2(pad, y + u), int(u), col)
		var me := bool(row["local"])
		var name_col := FishingPalette.HUD_TEXT if me else FishingPalette.HUD_DIM
		var name_x := pad + (ICON_COLS + 2.0) * u
		FishingHudDraw.text_line(self, name_x, y, str(row["name"]), s, name_col)
		var act := FishingHudModel.action_text(game, int(row["action"]))
		FishingHudDraw.text_line(self, status_x, y, act, s, FishingPalette.HUD_DIM)
		var pts := str(row["points"])
		var pw := FishingHudDraw.text_w(pts, s)
		FishingHudDraw.text_line(self, size.x - pad - pw, y, pts, s, FishingPalette.HUD_TEXT)
		y += pitch
