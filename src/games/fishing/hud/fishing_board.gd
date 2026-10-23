class_name FishingBoard
extends FishingHudControl
## The leaderboard at the top right: time left (or "Time is up" / overtime) and one row per
## rider, most points first: the action icon in the slot colour, the name, the action word and
## the points (Free Roam competes; in workouts the rows still show who is doing what).

const ART := Rect2i(424, 2, 212, 42)
const ROW_H := 24.0
const HEAD_H := 34.0

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
	var h := (HEAD_H + ROW_H * float(rows.size()) + 6.0) * s
	FishingHudDraw.panel(self, Rect2(Vector2.ZERO, Vector2(size.x, h)))
	var label := px(WlTheme.LABEL_PX)
	FishingHudDraw.text(self, Vector2(12, 27) * s, time_text, label, WlTheme.TEXT, true)
	var y := HEAD_H * s
	var small := px(WlTheme.SMALL_PX)
	var tiny := px(WlTheme.MIN_TEXT_PX + 4)
	for row in rows:
		var col: Color = FishingHudModel.look(game, int(row["slot"]))["color"]
		var icon := FishingHudModel.icon_of(int(row["action"]))
		var at := Vector2(10 * s, y + s)
		FishingHudDraw.sprite(self, icon, floori(_t * 4.0), at, 2.0 * s, col)
		var me := bool(row["local"])
		var base := y + 18.0 * s
		var name_col := WlTheme.TEXT if me else WlTheme.TEXT_DIM
		FishingHudDraw.text(self, Vector2(40 * s, base), str(row["name"]), small, name_col, me)
		var act := FishingHudModel.action_text(game, int(row["action"]))
		FishingHudDraw.text(self, Vector2(250 * s, base), act, tiny, WlTheme.TEXT_DIM)
		var pts := str(row["points"])
		var pw := FishingHudDraw.text_w(pts, small, true)
		var px_at := Vector2(size.x - pw - 12.0 * s, base)
		FishingHudDraw.text(self, px_at, pts, small, WlTheme.TEXT, true)
		y += ROW_H * s
