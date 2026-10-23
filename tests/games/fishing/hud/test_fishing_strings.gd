extends GutTest
## Every user-facing Fishing string rendered with the args its caller passes, with strings.csv
## registered in the TranslationServer (so a mismatch between "{0}" and a Dictionary shows as a
## raw placeholder): the lane status (FishingHudModel and the module's teammate chip, which must
## read the same), the fallback phase chip, the FishingLaneHud detail, every event toast
## (FishingGame.toast_for), the rules' own toasts and tips, and the HUD's number strings. Also:
## no key in strings.csv is dead.

const FX := preload("res://tests/games/fishing/view/fishing_view_fixtures.gd")
const CSV := "res://content/fishing/strings.csv"
## Keys code builds from a prefix plus a number (FishingRules tips, FishingPlanBuilder labels).
const BUILT_PREFIXES: Array[String] = ["FISHING_TIP_", "FISHING_PHASE_"]
const SCAN_DIRS: Array[String] = ["res://src/games/fishing", "res://content/fishing"]

var _tr: Translation = null


func before_all() -> void:
	_tr = Translation.new()
	_tr.locale = TranslationServer.get_locale()
	for k: String in _csv():
		_tr.add_message(k, _csv()[k])
	TranslationServer.add_translation(_tr)


func after_all() -> void:
	TranslationServer.remove_translation(_tr)


func _csv() -> Dictionary:
	var out := {}
	var f := FileAccess.open(CSV, FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 2 and row[0] != "":
			out[row[0]] = row[1]
	return out


func _clean(text: String, what: String) -> void:
	assert_false(text.contains("{"), "%s: '%s' has a raw placeholder" % [what, text])
	assert_false(text.contains("}"), "%s: '%s' has a raw placeholder" % [what, text])
	assert_false(text.begins_with("FISHING_"), "%s: '%s' is an untranslated key" % [what, text])


func _game(n: int = 2) -> FishingGame:
	var g: FishingGame = autofree(FX.make_game(n, 0))
	return g


## Lane 1 of `game` in `st` with species `sp` (-1 none), the fish 47.4 m out, the lure at 61.6 m.
func _lane(game: FishingGame, st: int, sp: int) -> FishingLaneState:
	var l := game.state.lane(1)
	l.state = st
	l.fish.sp = sp
	l.fish.d = 47.4
	l.fish.off_line = false
	l.lure_d = 61.6
	l.rescue = false
	l.afk = false
	l.stale = false
	return l


func test_every_lane_status_renders_without_raw_placeholders() -> void:
	var game := _game()
	var h := FishingLaneHud.make(game, 1)
	for st in range(FishingConst.ST_RIDE_OUT, FishingConst.ST_HOME + 1):
		for sp in range(-1, FishingConst.SPECIES.size()):
			for flag in ["", "rescue", "afk", "stale"]:
				var l := _lane(game, st, sp)
				if flag != "":
					l.set(flag, true)
				var what := "state %d sp %d %s" % [st, sp, flag]
				_clean(FishingHudModel.status_text(game, l), "lane status " + what)
				_clean(game.status_text(l), "teammate chip " + what)
				var chip := FishingHudModel.phase_chip(game, l, null, 0.0)
				_clean(str(chip["label"]), "fallback chip label " + what)
				_clean(str(chip["next"]), "fallback chip next " + what)
				h.refresh()
				_clean(h.detail, "FishingLaneHud detail " + what)
	h.free()


func test_lane_hud_status_reads_like_the_modules_teammate_chip() -> void:
	var game := _game()
	for st in range(FishingConst.ST_RIDE_OUT, FishingConst.ST_HOME + 1):
		for sp in FishingConst.SPECIES.size():
			var l := _lane(game, st, sp)
			assert_eq(
				FishingHudModel.status_text(game, l),
				game.status_text(l),
				"state %d sp %d" % [st, sp]
			)
	var reel := _lane(game, FishingConst.ST_REEL, -1)
	assert_eq(FishingHudModel.status_text(game, reel), "Reeling in at 62 m")
	var fight := _lane(game, FishingConst.ST_FIGHT, 2)
	assert_eq(FishingHudModel.status_text(game, fight), "Yellowfin tuna at 47 m")


func test_every_event_toast_renders_without_raw_placeholders() -> void:
	var game := _game(3)
	var events: Array[Dictionary] = [
		FishingEvents.landed(1, 2, FishingConst.GRADE_LANDED, 12.3, 40, 1.0),
		FishingEvents.landed(2, 3, FishingConst.GRADE_TROPHY, 154.0, 220, 1.5),
		FishingEvents.double_hookup([0, 1], 2),
		FishingEvents.double_hookup([0, 1, 2], 3),
		FishingEvents.frenzy(1),
		FishingEvents.hookup(0, 1, 1, false),
		FishingEvents.strike_miss(0, 0),
		FishingEvents.snap(0),
		FishingEvents.thrown(0),
		FishingEvents.replacement(0, 2),
	]
	var seen := 0
	for e in events:
		var tt := game.toast_for(e)
		assert_eq(tt.size(), 2, "%s has a toast" % e["type"])
		if tt.size() != 2:
			continue
		seen += 1
		_clean(game.ctx.strings.t(str(tt[0]), tt[1]), "toast %s" % e["type"])
	assert_eq(seen, events.size())
	var landed := game.toast_for(events[0])
	var text := game.ctx.strings.t(str(landed[0]), landed[1])
	assert_true(text.contains("Yellowfin tuna") and text.contains("12.3 kg"), text)


func test_rules_toasts_and_tips_render_without_raw_placeholders() -> void:
	var tx := GameStrings.new()
	_clean(tx.t(FishingRules.TOAST_STRIKE, []), "strike toast")
	for i in FishingRules.TIP_KEYS:
		_clean(tx.t(FishingRules.TIP_PREFIX + str(i + 1), []), "tip %d" % (i + 1))


func test_hud_number_strings_render_with_their_callers_args() -> void:
	var game := _game()
	var tx := FishingHudModel.strings_of(game)
	game.state.t = 75.0
	game.state.fishing_end_t = 600.0
	game.state.team_points = 345
	game.state.team_fish = 6
	game.state.hookup_level = 2
	var bar := FishingDeckBar.make(game)
	bar.refresh()
	_clean(bar.fishing_left_text, "deck bar fishing left")
	var board := FishingCatchBoard.make(game)
	board.refresh()
	_clean(board.points_text, "catch board points")
	_clean(board.fish_text, "catch board fish")
	# The calls FishingDeckBar._draw, FishingCatchBoard._draw and FishingLaneHud make.
	var calls: Array = [
		[FishingHudModel.KEY_LEFT, [FishingHudModel.clock(25.0)]],
		[FishingHudModel.KEY_NEXT, ["Landing"]],
		[FishingHudModel.KEY_DISTANCE, [str(47)]],
		[FishingHudModel.KEY_HOOKUP, [FishingHudModel.hookup_text(2)]],
		[FishingHudModel.KEY_WATTS, []],
		[FishingHudModel.KEY_RPM, []],
		[FishingHudModel.KEY_SPRINT, []],
		[FishingHudModel.KEY_SPIN, []],
		[FishingHudModel.KEY_TROPHY, []],
		[FishingHudModel.KEY_COOLDOWN, []],
		[FishingHudModel.KEY_YOU, []],
	]
	for c: Array in calls:
		_clean(tx.t(str(c[0]), c[1]), str(c[0]))
	bar.free()
	board.free()


## A key nothing reads is a dead string: each must appear in Fishing's code or content, or be
## one that code builds from a prefix and a number.
func test_no_key_in_strings_csv_is_dead() -> void:
	var text := ""
	for dir in SCAN_DIRS:
		text += _read_tree(dir)
	for k: String in _csv():
		var built := false
		for p in BUILT_PREFIXES:
			built = built or (k.begins_with(p) and text.contains('"%s' % p))
		assert_true(built or text.contains(k), "%s is used somewhere" % k)


func _read_tree(dir: String) -> String:
	var out := ""
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() in ["gd", "json"]:
			out += FileAccess.get_file_as_string(dir.path_join(f)) + "\n"
	for d in DirAccess.get_directories_at(dir):
		out += _read_tree(dir.path_join(d))
	return out


## The local lane's tag is FISHING_HUD_YOU from ctx.strings, drawn in the tag's pixel font.
func test_the_local_tag_reads_fishing_hud_you() -> void:
	var game := _game(2)
	assert_eq(FishingView.tag_text(game), _csv()[FishingHudModel.KEY_YOU])
	var v := FX.make_view(game, self)
	autofree(v)
	assert_eq(v.lane_view(0).tag_text, _csv()[FishingHudModel.KEY_YOU])
	assert_eq(FishingLaneView.tag_glyphs("YOU").size(), 3)
	assert_eq(FishingLaneView.tag_glyphs("Du").size(), 2, "any A-Z word fits the tag")
	assert_eq(FishingLaneView.tag_glyphs("??").size(), 3, "no glyph at all falls back to YOU")
	var lv := v.lane_view(0)
	assert_lte(lv.tag_rect(3).end.x, float(FishingLaneView.TAG_MAX_GLYPHS * 4 + 8))
	assert_true(Rect2(0, 0, FishingConst.PIXEL_W, lv.lane_h).encloses(lv.tag_rect(8)))
