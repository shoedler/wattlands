extends GutTest
## The Tank Controls as Controls: they read TankGame.state, recompute their model each frame, redraw
## only when it changed, draw headless without errors, and the Bulwark's lever cell sends intents.

const F := preload("res://tests/games/tank/tank_fakes.gd")


func _make(state: TankState, peer: int = 1) -> Dictionary:
	var ctx := F.make_ctx(state.crew, 0, "ashfall_road", Wl.SOLO, peer)
	var g := F.make_game(ctx)
	autofree(g)
	g.state = state
	var spec := TankHud.spec(g)
	var by_name := {}
	for c: Dictionary in spec.controls:
		var control := c["control"] as Control
		var rect: Rect2i = c["at"]
		control.size = Vector2(rect.size * 3)
		add_child_autofree(control)
		by_name[str((control.get_script() as Script).get_global_name())] = control
	return {"game": g, "controls": by_name, "ctx": ctx}


func _card(m: Dictionary) -> TankStationCard:
	return m["controls"]["TankStationCard"]


func test_the_card_follows_the_local_riders_engine() -> void:
	var s := TankFixtures.state(3)
	for pair: Array in [
		[1, TankIds.ENGINE_DYNAMO], [2, TankIds.ENGINE_STEAM], [3, TankIds.ENGINE_DIESEL]
	]:
		var m := _make(s, pair[0])
		_card(m).refresh()
		assert_eq(_card(m).model["kind"], pair[1], "peer %d" % pair[0])


func test_a_card_redraws_only_when_the_model_changes() -> void:
	var s := TankFixtures.state(2)
	var m := _make(s, 2)
	var card := _card(m)
	card.refresh()
	var n := card.model_changes
	assert_eq(n, 1)
	card.refresh()
	card.refresh()
	assert_eq(card.model_changes, n, "nothing moved: no redraw")
	s.hull.speed_mps += 1.0
	card.refresh()
	assert_eq(card.model_changes, n + 1)


func test_controls_draw_headless_for_every_engine_and_fixture() -> void:
	for crew in [1, 2, 3]:
		for kind in ["state", "gun_line", "boss"]:
			var s: TankState
			match kind:
				"gun_line":
					s = TankFixtures.gun_line(crew)
				"boss":
					s = TankFixtures.boss(crew)
				_:
					s = TankFixtures.state(crew)
			for peer in range(1, crew + 1):
				var m := _make(s, peer)
				for c: TankHudPanel in m["controls"].values():
					c.refresh()
					c.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(true, "no errors while drawing every card")


## A station card that records what the Ram cell draws instead of drawing it.
class SpyCard:
	extends TankStationCard
	var labels: Array[String] = []
	var lines: int = 0

	func text(
		_at: Vector2,
		s: String,
		_px: float,
		_color: Color = WlTheme.TEXT,
		_width: float = -1.0,
		_align: int = HORIZONTAL_ALIGNMENT_LEFT,
		_outlined: bool = true
	) -> void:
		labels.append(s)

	func line(_a: Vector2, _b: Vector2, _color: Color, _width: float = 3.0) -> void:
		lines += 1

	func bar(_r: Rect2, _frac: float, _fill: Color) -> void:
		labels.append("<bar>")


func _spy_for(state: TankState, peer: int) -> SpyCard:
	var m := _make(state, peer)
	var spy := SpyCard.new()
	spy.game = m["game"]
	add_child_autofree(spy)
	spy.refresh()
	spy.call("_ram_cell", 2)
	return spy


func test_the_ram_cell_shows_a_ready_mark_only_when_the_ram_works() -> void:
	var s := TankFixtures.state(2)
	var peer := s.rider_at(s.station(TankIds.ENGINE_DIESEL).slot).peer
	var ready := _spy_for(s, peer)
	assert_eq(ready.lines, 2, "an Advance past 300 s: the check mark")
	assert_true(ready.labels.has("Surge to ram"))
	for pair: Array in [[TankIds.SEG_DEPOT, Wl.WARMUP], [TankIds.SEG_CHECKPOINT, Wl.RECOVERY]]:
		var q := TankFixtures.state(2)
		q.seg.seg = pair[0]
		q.seg.kind = pair[1]
		var idle := _spy_for(q, peer)
		assert_eq(idle.lines, 0, "%s: no check mark" % pair[0])
		assert_false(idle.labels.has("<bar>"), "%s: no full bar" % pair[0])
		assert_true(idle.labels.has("-"), "%s: a dash" % pair[0])
	var early := TankFixtures.state(2)
	early.t = 120.0
	assert_eq(_spy_for(early, peer).lines, 0, "the first 300 s: no check mark")
	var bs := TankFixtures.boss(2)
	var boss := _spy_for(bs, bs.rider_at(bs.station(TankIds.ENGINE_DIESEL).slot).peer)
	assert_false(boss.labels.has("Surge to ram"), "the boss asks for a dodge")
	assert_true(boss.labels.has("Surge to dodge"))


func test_the_objective_line_and_boss_bars_model() -> void:
	var m := _make(TankFixtures.boss(1), 1)
	var obj := m["controls"]["TankObjectiveLine"] as TankObjectiveLine
	var boss := m["controls"]["TankBossBars"] as TankBossBars
	obj.refresh()
	boss.refresh()
	assert_eq(obj.model["key"], "TANK_OBJ_BOSS")
	assert_true(boss.model["show"])
	var quiet := _make(TankFixtures.state(1), 1)
	var qb := quiet["controls"]["TankBossBars"] as TankBossBars
	qb.refresh()
	assert_false(qb.model["show"])


func test_a_game_without_state_is_harmless() -> void:
	var g := TankGame.new()
	autofree(g)
	var card := TankStationCard.new()
	card.game = g
	add_child_autofree(card)
	card.refresh()
	assert_eq(card.model, {})
	var none := TankStationCard.new()
	add_child_autofree(none)
	none.refresh()
	assert_eq(none.model, {})


func _click(card: TankStationCard, design: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = design * card.k()
	card._gui_input(ev)


func test_clicking_the_bulwarks_lever_sends_a_button_intent() -> void:
	var s := TankFixtures.state(1)
	var m := _make(s, 1)
	var card := _card(m)
	card.refresh()
	assert_eq(card.mouse_filter, Control.MOUSE_FILTER_STOP, "the Bulwark's card takes clicks")
	var sent: Array = (m["ctx"].intents as F.Intents).sent
	_click(card, TankStationCard.lever_rect(2).get_center())
	assert_eq(sent.size(), 1)
	assert_eq(sent[0], TankIntents.lever("hoist", TankIds.VIA_BUTTON))
	_click(card, TankStationCard.lever_rect(0).get_center())
	assert_eq(sent[1], TankIntents.lever("drive", TankIds.VIA_BUTTON))
	_click(card, TankStationCard.lever_rect(1).get_center())
	assert_eq(sent[2]["to"], "turret")
	_click(card, Vector2(5, 5))
	assert_eq(sent.size(), 3, "a click outside the lever does nothing")
	assert_true(TankIntents.normalize(sent[0])["via"] == TankIds.VIA_BUTTON)
	assert_eq(TankIntents.normalize(sent[0])["to"], TankIds.LEVER_HOIST, "the host accepts it")


func test_other_engines_never_take_clicks_or_send_intents() -> void:
	var s := TankFixtures.state(3)
	var m := _make(s, 1)
	var card := _card(m)
	card.refresh()
	assert_eq(card.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	_click(card, TankStationCard.lever_rect(1).get_center())
	assert_eq((m["ctx"].intents as F.Intents).sent.size(), 0)
	assert_eq(
		_make(s, 2)["controls"]["TankObjectiveLine"].mouse_filter, Control.MOUSE_FILTER_IGNORE
	)


func test_the_controls_never_change_the_state() -> void:
	var s := TankFixtures.state(3)
	var before := JSON.stringify(s.to_dict())
	var m := _make(s, 1)
	for c: TankHudPanel in m["controls"].values():
		c.refresh()
	assert_eq(JSON.stringify(s.to_dict()), before)
