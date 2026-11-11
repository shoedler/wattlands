extends GutTest
## The shared receipt on the HUD (docs/games/siege.md 2.4 "Shop", 3 "HUD"): the receipt plate over the
## shop (items, cost, picker, YES n / NO n, the total, when it is bought, the two rules), and the
## gold plate's "N ON RECEIPT".

const K := preload("res://tests/games/siege/hud/siege_hud_kit.gd")
const F := preload("res://tests/games/siege/siege_fakes.gd")

var _games: Array[SiegeGame] = []


func after_each() -> void:
	for g in _games:
		F.free_game(g)
	_games.clear()


## A game in the first break (phase 1) with the fixture's three riders, `elapsed_s` into it.
func _break(elapsed_s: float = 29.0) -> SiegeGame:
	var g := K.game(1, elapsed_s)
	_games.append(g)
	for r in g.state.riders:
		r.gold = 300.0
	return g


func _line(
	g: SiegeGame, item: String, at: int, cost: int, slot: int, no: Array[int] = []
) -> SiegeReceiptLine:
	var line := SiegeReceiptLine.new()
	line.item = item
	line.at = at
	line.cost = cost
	line.slot = slot
	line.no.assign(no)
	g.state.receipt.append(line)
	return line


func _panel(g: SiegeGame) -> SiegeReceiptPanel:
	var p := K.ctl(SiegeReceiptPanel.new(), g, SiegeReceiptPanel.RECT) as SiegeReceiptPanel
	add_child_autofree(p)
	p.refresh()
	return p


func test_the_face_lists_items_cost_picker_and_votes() -> void:
	var g := _break()
	_line(g, SiegeIds.ITEM_UPGRADE, SiegeIds.STATION_BALLISTA, 40, 0)
	_line(g, SiegeIds.ITEM_UPGRADE, SiegeIds.STATION_ARROWS, 40, 1, [0])
	_line(g, SiegeIds.ITEM_REPAIR, 0, 30, 2)
	var f := SiegeReceiptModel.face(g)
	var rows: Array = f["rows"]
	assert_eq(rows.size(), 3)
	assert_eq(rows[0]["cost"], 40)
	assert_true(bool(rows[0]["mine"]), "slot 0 is the local rider")
	var riders := g.state.riders.size()
	assert_eq(rows[0]["yes"], riders)
	assert_eq(rows[0]["no"], 0)
	assert_eq(rows[1]["by"], SiegeHudModel.rider_name(g, g.state.rider_at(1)))
	assert_eq(rows[1]["yes"], riders - 1)
	assert_eq(rows[1]["no"], 1)
	assert_true(bool(rows[1]["my_no"]))
	assert_false(bool(rows[2]["my_no"]))
	assert_eq(f["total"], 110)
	assert_eq(f["hidden"], 0)
	assert_eq(f["empty"], "")
	assert_eq(str(f["title"]).to_upper(), "RECEIPT  EVERYONE SEES THIS")
	assert_eq(str(f["bought"]).to_upper(), "BOUGHT WHEN THE BREAK ENDS (%s)" % _clock(g))
	assert_eq(
		str((f["rules"] as Array)[0]).to_upper(), "A MAJORITY NO (OR A TIE) TAKES IT OFF AT ONCE."
	)
	assert_eq(str((f["rules"] as Array)[1]).to_upper(), "PICK YOURS AGAIN TO TAKE IT BACK.")


func _clock(g: SiegeGame) -> String:
	return HudWidget.clock_text(SiegeHudModel.phase_remaining_s(g.state))


func test_the_clock_counts_down_the_break() -> void:
	var g := _break(29.0)
	var a := str(SiegeReceiptModel.face(g)["bought"])
	g.state.phase_elapsed_s += 10.0
	g.state.phase_remaining_s -= 10.0
	var b := str(SiegeReceiptModel.face(g)["bought"])
	assert_ne(a, b)


func test_an_empty_receipt_says_so_and_the_total_is_zero() -> void:
	var f := SiegeReceiptModel.face(_break())
	assert_eq((f["rows"] as Array).size(), 0)
	assert_ne(f["empty"], "")
	assert_eq(f["total"], 0)


func test_more_rows_than_fit_fold_into_a_count_and_the_total_still_counts_them() -> void:
	var g := _break()
	for n in 6:
		_line(g, SiegeIds.ITEM_SCORPION, 2, 40, 0)
		g.state.receipt[n].at = n + 1
	var f := SiegeReceiptModel.face(g)
	assert_eq((f["rows"] as Array).size(), SiegeReceiptModel.MAX_ROWS - 1)
	assert_eq(f["hidden"], 6 - (SiegeReceiptModel.MAX_ROWS - 1))
	assert_eq(f["total"], 240)
	assert_true(str(f["more"]).contains(str(f["hidden"])))


func test_the_panel_shows_only_while_the_shop_is_open() -> void:
	var g := _break()
	var p := _panel(g)
	assert_true(p.visible)
	assert_false(p.model.is_empty())
	K.stand(g, 4, 10.0)
	p.refresh()
	assert_false(p.visible, "closed in waves")
	assert_eq(p.model, {})


func test_the_plate_grows_with_its_rows_and_never_passes_its_largest_height() -> void:
	var g := _break()
	var p := _panel(g)
	var empty_h := p.plate_h
	for n in 3:
		_line(g, SiegeIds.ITEM_SCORPION, n + 1, 40, 0)
	p.refresh()
	assert_eq(p.plate_h, empty_h - SiegeReceiptPanel.NOTE_H + 3 * SiegeReceiptPanel.ROW_STEP)
	for n in 6:
		_line(g, SiegeIds.ITEM_UPGRADE, 1, 40, 1)
	p.refresh()
	assert_lte(p.plate_h, SiegeReceiptPanel.MAX_H)
	for rows in SiegeReceiptModel.MAX_ROWS + 1:
		var face := {"rows": range(rows), "empty": "", "hidden": 0}
		assert_lte(SiegeReceiptPanel.plate_height(face), SiegeReceiptPanel.MAX_H)
	var folded := {"rows": [1, 2], "empty": "", "hidden": 5}
	assert_lte(SiegeReceiptPanel.plate_height(folded), SiegeReceiptPanel.MAX_H)


func test_the_tallest_plate_sits_on_the_shop_and_clears_the_session_plate_on_every_canvas() -> void:
	var base := Vector2i(960, 540)
	for art: Vector2i in [
		Vector2i(852, 480), Vector2i(1146, 480), base, Vector2i(1280, 720), Vector2i(1703, 1079)
	]:
		var r := PixelViewport.anchor_rect(SiegeReceiptPanel.RECT, base, art)
		var shop := PixelViewport.anchor_rect(SiegeShopPanel.RECT, base, art)
		var session := PixelViewport.anchor_rect(SiegeHudSession.RECT, base, art)
		assert_eq(shop.position.y - r.end.y, 4, "side by side with the shop on %s" % art)
		var top := r.end.y - 2 - SiegeReceiptPanel.MAX_H
		assert_gt(top, session.end.y + 4, "under the session plate on %s" % art)


func test_the_plate_draws_every_state_without_error() -> void:
	var g := _break()
	_line(g, SiegeIds.ITEM_UPGRADE, SiegeIds.STATION_BALLISTA, 40, 0)
	_line(g, SiegeIds.ITEM_MINE, 0, 60, 1, [0])
	var p := _panel(g)
	await wait_physics_frames(2)
	assert_gt(p.draws, 0)
	g.state.receipt.clear()
	p.refresh()
	await wait_physics_frames(2)
	assert_gt(p.draws, 1)


func test_every_row_name_fits_beside_its_coin() -> void:
	var g := _break()
	var tx := SiegeHudModel.strings_of(g)
	var room := SiegeReceiptPanel.COIN_X - 6 - SiegeReceiptPanel.TEXT_X
	for item: String in SiegeIds.ITEMS:
		for at in [0, 1, 2, 3, 4]:
			var name := SiegeShopModel.text_of(g.state, tx, item, at)
			assert_lte(SiegeHudType.width(name, "BODY"), room, "%s %d: %s" % [item, at, name])


func test_the_gold_plate_shows_free_gold_and_the_held_sum() -> void:
	var g := _break()
	g.state.rider_at(0).gold = 103.7
	var f := SiegeHudModel.fort_face(g.state, g.state.rider_at(0))
	assert_eq(f["gold"], 103)
	assert_eq(f["held"], 0)
	_line(g, SiegeIds.ITEM_UPGRADE, SiegeIds.STATION_BALLISTA, 40, 0)
	_line(g, SiegeIds.ITEM_MINE, 0, 60, 1)
	f = SiegeHudModel.fort_face(g.state, g.state.rider_at(0))
	assert_eq(f["gold"], 63, "103 less the 40 on the receipt, as the mock shows")
	assert_eq(f["held"], 40, "only the rider's own items hold their gold")
	var col := K.ctl(SiegeHudColumn.new(), g, SiegeHudColumn.RECT) as SiegeHudColumn
	add_child_autofree(col)
	col.refresh()
	assert_eq(col.model["held"], 40)
	await wait_physics_frames(2)
	assert_gt(col.draws, 0)
	assert_eq(
		SiegeHudModel.strings_of(g).t("SIEGE_HUD_ON_RECEIPT", [40]).to_upper(), "40 YOURS HELD"
	)


func test_a_rider_with_nothing_held_sees_no_receipt_line() -> void:
	var g := _break()
	var f := SiegeHudModel.fort_face(g.state, g.state.rider_at(0))
	assert_eq(f["held"], 0)
