class_name FishingCatchBoard
extends FishingHudControl
## The deck bar's right part (brief 3.5): the team's points and fish count, the hookup level
## (fights on now and their multiplier) and the last 5 catches as fish icons in the catching
## lane's colour with its slot shape beside each (a star for a Trophy), newest on the right.

var points_text: String = ""
var fish_text: String = ""
var hookup_level: int = 0
var catches: Array = []


static func make(p_game: FishingGame) -> FishingCatchBoard:
	var b := FishingCatchBoard.new()
	b.game = p_game
	b.name = "FishingCatchBoard"
	b.design_h = float(FishingConst.DECK_H * 3)
	return b


func refresh() -> void:
	var st := game.state if game != null else null
	if st == null:
		return
	var tx := FishingHudModel.strings_of(game)
	points_text = tx.t(FishingHudModel.KEY_POINTS, [st.team_points])
	fish_text = tx.t(FishingHudModel.KEY_FISH, [st.team_fish])
	hookup_level = st.hookup_level
	catches = FishingHudModel.board(st)


func _draw() -> void:
	if game == null or game.state == null:
		return
	var s := k()
	var tx := FishingHudModel.strings_of(game)
	var big := px(WlTheme.LABEL_PX + 4)
	var small := px(WlTheme.SMALL_PX)
	var x := 8.0 * s
	x += FishingHudDraw.text(self, Vector2(x, 31.0 * s), points_text, big, WlTheme.TEXT, true)
	x += 18.0 * s
	FishingHudDraw.text(self, Vector2(x, 31.0 * s), fish_text, small, WlTheme.TEXT)
	if hookup_level >= 2:
		var t := tx.t(FishingHudModel.KEY_HOOKUP, [FishingHudModel.hookup_text(hookup_level)])
		FishingHudDraw.text(
			self, Vector2(size.x - 200.0 * s, 31.0 * s), t, small, FishingHudDraw.GAFF, true
		)
	var cx := 30.0 * s
	for c: Array in catches:
		var lane := int(c[0])
		var look := FishingHudModel.look(game, lane)
		var col: Color = look["color"]
		FishingHudDraw.fish_icon(self, Vector2(cx, 54.0 * s), 40.0 * s, col)
		FishingHudDraw.shape(
			self, str(look["shape"]), Vector2(cx + 28.0 * s, 54.0 * s), 7.0 * s, col
		)
		if int(c[2]) == FishingConst.GRADE_TROPHY:
			FishingHudDraw.star(
				self, Vector2(cx - 14.0 * s, 44.0 * s), 8.0 * s, FishingPalette.YELLOW
			)
		cx += 70.0 * s
