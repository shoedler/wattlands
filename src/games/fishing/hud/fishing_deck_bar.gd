class_name FishingDeckBar
extends FishingHudControl
## The deck bar's left part (brief 3.5; G0 decision "HUD layout"): the trip clock with the
## fishing time left, the local rider's phase chip (label, time left or elapsed, next phase) and
## the fish row (species icon, distance in m, stamina) or, during a Landing, the gaff meter. The
## kit's gear and W' widgets sit right of it in their own rects; the catch board is
## FishingCatchBoard.

## The model of the last refresh (tests read it).
var clock_text: String = ""
var fishing_left_text: String = ""
var chip: Dictionary = {}
var fish: Dictionary = {}
var gaff: Dictionary = {}
## Game time the local rider's current phase started (tracked on phase index changes).
var phase_start_t: float = 0.0

var _plan: EffortPlan = null
var _plan_built: bool = false
var _phase_seen: int = -1


static func make(p_game: FishingGame) -> FishingDeckBar:
	var d := FishingDeckBar.new()
	d.game = p_game
	d.name = "FishingDeckBar"
	d.design_h = float(FishingConst.DECK_H * 3)
	return d


func refresh() -> void:
	var st := game.state if game != null else null
	if st == null:
		return
	if not _plan_built:
		_plan_built = true
		_plan = FishingHudModel.local_plan(game)
	var l := FishingHudModel.local_lane(game)
	if l != null and l.phase_index != _phase_seen:
		phase_start_t = st.t - (l.state_t if _phase_seen < 0 else 0.0)
		_phase_seen = l.phase_index
	var tx := FishingHudModel.strings_of(game)
	clock_text = FishingHudModel.clock(st.t)
	var left := maxf(st.fishing_end_t - st.t, 0.0)
	fishing_left_text = tx.t(FishingHudModel.KEY_ENDS_IN, [FishingHudModel.clock(left)])
	chip = FishingHudModel.phase_chip(game, l, _plan, phase_start_t)
	fish = FishingHudModel.fish_row(game, l)
	gaff = FishingHudModel.gaff(l)


func _draw() -> void:
	if chip.is_empty():
		return
	var s := k()
	var tx := FishingHudModel.strings_of(game)
	var big := px(WlTheme.LABEL_PX + 4)
	var small := px(WlTheme.SMALL_PX)
	var y1 := 31.0 * s
	var y2 := 64.0 * s
	FishingHudDraw.text(self, Vector2(10 * s, y1), clock_text, big, WlTheme.TEXT, true)
	FishingHudDraw.text(self, Vector2(10 * s, y2), fishing_left_text, small, WlTheme.TEXT_DIM)
	var x := 290.0 * s
	FishingHudDraw.text(self, Vector2(x, y1), str(chip.get("label", "")), big, WlTheme.TEXT, true)
	var left := float(chip.get("left_s", -1.0))
	var when := (
		tx.t(FishingHudModel.KEY_LEFT, [FishingHudModel.clock(left)])
		if left >= 0.0
		else FishingHudModel.clock(float(chip.get("elapsed_s", 0.0)))
	)
	var next := tx.t(FishingHudModel.KEY_NEXT, [str(chip.get("next", ""))])
	FishingHudDraw.text(self, Vector2(x, y2), "%s  %s" % [when, next], small, WlTheme.TEXT_DIM)
	var fx := 640.0 * s
	if bool(gaff.get("visible", false)):
		FishingHudDraw.text(
			self, Vector2(fx, y1), tx.t(str(gaff["phase"])), big, FishingHudDraw.GAFF, true
		)
		var bar := Rect2(fx, 42.0 * s, size.x - fx - 12.0 * s, 22.0 * s)
		FishingHudDraw.bar(self, bar, float(gaff["fill"]), FishingHudDraw.GAFF)
		FishingHudDraw.star(
			self, Vector2(bar.end.x - 12.0 * s, bar.get_center().y), 10.0 * s, FishingPalette.YELLOW
		)
	elif bool(fish.get("visible", false)):
		var col: Color = FishingHudModel.look(game, FishingHudModel.local_slot(game))["color"]
		FishingHudDraw.fish_icon(self, Vector2(fx + 26.0 * s, 20.0 * s), 48.0 * s, col)
		var dist := tx.t(FishingHudModel.KEY_DISTANCE, [str(fish["d_m"])])
		FishingHudDraw.text(
			self,
			Vector2(fx + 60.0 * s, y1),
			"%s  %s" % [str(fish["name"]), dist],
			small,
			WlTheme.TEXT
		)
		var bar2 := Rect2(fx, 42.0 * s, size.x - fx - 12.0 * s, 18.0 * s)
		FishingHudDraw.bar(self, bar2, float(fish["stamina"]), FishingHudDraw.STAMINA)
