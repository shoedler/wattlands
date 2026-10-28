extends GutTest
## The v3 seat panel (brief v3 "HUD", "Seat choice and switching"): every crew of 1-4 on every
## choice of seats (any seat empty) builds five cards in seat order with the empty ones dark; the
## lock timer and the hint plate's states; the seat picker (left / right, swap on the Gun, confirm,
## back, the idle close, no picker for Autopilot) and the seat intent it sends through
## TankGame.local_intents; the rack pips and the Secondaries' rounds a minute, or "no target" while
## their rider pedals at nothing; the ERG / SIM tags; my numbers per seat; the layout on 852 x 480,
## 960 x 540 and 1146 x 480 (nothing in the bottom-right 200 x 60, no plate over the tank band or my
## numbers); the fonts cover the panel's text; the belt feed's machine window.

const X := preload("res://tests/games/tank/hud/tank_hud_fixtures.gd")
const D := preload("res://src/games/tank/hud/tank_hud_draw.gd")
const CANVASES: Array[Vector2i] = [Vector2i(852, 480), Vector2i(960, 540), Vector2i(1146, 480)]
const HINT_KEYS: Array[String] = [
	"TANK_HUD_SEAT_LOCKED",
	"TANK_HUD_SEAT_HINT",
	"TANK_HUD_SEAT_HINT_SWAP",
	"TANK_HUD_SEAT_PICK",
	"TANK_HUD_SEAT_MOVING",
	"TANK_HUD_SEAT_AUTO",
]


## Seats the riders of `s` on `engines` (in slot order), every other seat empty, no move pending.
static func reseat(s: TankState, engines: Array) -> void:
	for st in s.stations:
		st.slot = -1
		st.peer = 0
	for i in s.riders.size():
		var r := s.riders[i]
		r.engine = str(engines[i])
		r.seat_target = ""
		var st := s.station(r.engine)
		st.slot = r.slot
		st.peer = r.peer


## Every choice of `k` seats out of TankIds.SEATS, in seat order.
static func choices(k: int, from: int = 0) -> Array:
	if k == 0:
		return [[]]
	var out: Array = []
	for i in range(from, TankIds.SEATS.size() - k + 1):
		for rest: Array in choices(k - 1, i + 1):
			out.append([TankIds.SEATS[i]] + rest)
	return out


func _panel(g: TankGame) -> TankHudSeats:
	var p := TankHudSeats.new().setup(g, TankHud.LAYOUT["seats"]) as TankHudSeats
	add_child_autofree(p)
	p.size = Vector2(p.art_rect.size * 2)
	return p


func _mine(g: TankGame) -> TankHudMine:
	var m := TankHudMine.new().setup(g, TankHud.LAYOUT["mine"]) as TankHudMine
	add_child_autofree(m)
	m.size = Vector2(m.art_rect.size * 2)
	return m


static func _lum(t: ImageTexture) -> float:
	var img := t.get_image()
	var sum := 0.0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			sum += img.get_pixel(x, y).get_luminance()
	return sum / float(img.get_width() * img.get_height() / 4)


func test_every_crew_on_any_seats_builds_five_cards_with_the_empty_ones_dark() -> void:
	var panels: Array[TankHudSeats] = []
	for crew in range(1, 5):
		for seats: Array in choices(crew):
			var s := X.state(crew)
			reseat(s, seats)
			var p := _panel(autofree(X.game(s)))
			p.tick(0.1)
			p.refresh()
			var what := "crew %d on %s" % [crew, seats]
			assert_eq(p.cards.size(), 5, what)
			for i in 5:
				var c: Dictionary = p.cards[i]
				var engine := TankIds.SEATS[i]
				assert_eq(str(c["engine"]), engine, what)
				assert_eq(bool(c["empty"]), not seats.has(engine), "%s: %s" % [what, engine])
				assert_not_null(p.texture_of(engine), "%s: %s window" % [what, engine])
				if bool(c["empty"]):
					assert_eq(int(c["slot"]), -1)
					assert_eq(str(c["name"]), "")
				else:
					assert_eq(str(c["name"]), "Rider %d" % (int(c["slot"]) + 1), what)
			p.queue_redraw()
			panels.append(p)
	assert_eq(panels.size(), 5 + 10 + 10 + 5, "every choice of seats")
	await wait_physics_frames(2)
	for p in panels:
		assert_gt(p.draws, 0, "drew")
	# an empty room is dark and cold next to a manned one
	var s1 := X.state(1)
	var p1 := _panel(autofree(X.game(s1)))
	p1.refresh()
	var lit := _lum(p1.texture_of(TankIds.ENGINE_DIESEL))
	var dark := _lum(p1.texture_of(TankIds.ENGINE_DYNAMO))
	assert_lt(dark, lit * 0.6, "the empty Gun room is dark")
	var px := p1.texture_of(TankIds.ENGINE_DYNAMO).get_image().get_pixel(56, 40)
	assert_gte(px.b, px.r, "and cold")


func test_the_lock_timer_and_the_hint_follow_the_seat_lock() -> void:
	var s := X.state(2)
	var g: TankGame = autofree(X.game(s, 1))
	var p := _panel(g)
	var r := s.rider(1)
	r.autopilot = false
	r.seat_lock_s = 42.3
	p.refresh()
	assert_eq(TankHudSeats.hint_key(p.me), "TANK_HUD_SEAT_LOCKED")
	assert_eq(p.lock_text(42.3), "0:43", "the seconds left")
	var mine_card: Dictionary = p.cards[0]
	assert_true(bool(mine_card["local"]))
	assert_almost_eq(float(mine_card["lock_s"]), 42.3, 1e-6)
	r.seat_lock_s = 0.0
	p.refresh()
	assert_eq(TankHudSeats.hint_key(p.me), "TANK_HUD_SEAT_HINT", "< > move  OK sit")
	assert_eq(TankHud.tx(g, "TANK_HUD_SEAT_HINT"), "< > move  OK sit")
	assert_eq(p.lock_text(0.0), "MOVE OK")
	g.seat_picker.pick = TankIds.ENGINE_STEAM
	p.refresh()
	assert_eq(TankHudSeats.hint_key(p.me), "TANK_HUD_SEAT_PICK")
	g.seat_picker.close()
	r.seat_target = TankIds.ENGINE_ARC
	p.refresh()
	assert_eq(TankHudSeats.hint_key(p.me), "TANK_HUD_SEAT_MOVING")
	assert_eq(int(p.cards[3]["incoming"]), r.slot, "the target card shows the mover")
	r.seat_target = ""
	r.autopilot = true
	p.refresh()
	assert_eq(TankHudSeats.hint_key(p.me), "TANK_HUD_SEAT_AUTO", "Autopilot: no picker")
	var gun := s.rider(2)
	gun.autopilot = false
	gun.seat_lock_s = 0.0
	var pg := _panel(autofree(X.game(s, 2)))
	pg.refresh()
	assert_eq(
		TankHudSeats.hint_key(pg.me), "TANK_HUD_SEAT_HINT_SWAP", "the Gun keeps < > for targets"
	)
	var spectator := _panel(autofree(X.game(s, 99)))
	spectator.refresh()
	assert_eq(spectator.me, {})
	assert_eq(TankHudSeats.hint_key(spectator.me), "")


func test_the_picker_picks_empty_seats_and_confirm_sends_the_seat_intent() -> void:
	var s := X.state(2)
	var r := s.rider(1)
	r.autopilot = false
	r.seat_lock_s = 0.0
	var pk := TankHudSeatPicker.new()
	var right: Array[StringName] = [&"right"]
	var left: Array[StringName] = [&"left"]
	var ok: Array[StringName] = [&"confirm"]
	var out := pk.feed(s, r, right)
	assert_eq(pk.pick, TankIds.ENGINE_STEAM, "right of Drive past the manned Gun")
	assert_eq(out["taken"], [&"right"])
	assert_eq(out["intents"], [])
	pk.feed(s, r, right)
	assert_eq(pk.pick, TankIds.ENGINE_ARC)
	pk.feed(s, r, left)
	pk.feed(s, r, left)
	assert_eq(pk.pick, TankIds.ENGINE_FEED, "wrapping past the manned seats and your own")
	out = pk.feed(s, r, ok)
	assert_eq(out["intents"], [TankIntents.seat(TankIds.ENGINE_FEED)])
	assert_eq(out["taken"], [&"confirm"], "the confirm sits, it does nothing else")
	assert_false(pk.is_open())
	var n := TankIntents.normalize((out["intents"] as Array)[0])
	assert_eq(int(n["to"]), TankIds.engine_code(TankIds.ENGINE_FEED))
	assert_true(TankIntents.owned(TankIds.INTENT_SEAT, r.engine))
	assert_true(TankIntents.is_deliberate(n), "a seat pick ends the Autopilot fallback")
	# back closes; the picker closes itself when idle
	pk.feed(s, r, right)
	var back: Array[StringName] = [&"back"]
	pk.feed(s, r, back)
	assert_false(pk.is_open())
	pk.feed(s, r, right)
	var none: Array[StringName] = []
	for i in roundi(TankHudSeatPicker.IDLE_S / TankHudSeatPicker.DT):
		pk.feed(s, r, none)
	assert_false(pk.is_open(), "closed after %.0f s without a key" % TankHudSeatPicker.IDLE_S)
	# a seat another rider is moving into is not offered
	s.rider(2).seat_target = TankIds.ENGINE_STEAM
	assert_false(TankHudSeatPicker.empty_seats(s, r).has(TankIds.ENGINE_STEAM))
	s.rider(2).seat_target = ""
	# only while the lock is open, never for Autopilot, never with a move pending
	r.seat_lock_s = 5.0
	out = pk.feed(s, r, right)
	assert_false(pk.is_open())
	assert_eq(out["taken"], [], "a locked rider's keys go to their seat")
	r.seat_lock_s = 0.0
	r.autopilot = true
	pk.feed(s, r, right)
	assert_false(pk.is_open(), "no picker for Autopilot")
	r.autopilot = false
	r.seat_target = TankIds.ENGINE_ARC
	pk.feed(s, r, right)
	assert_false(pk.is_open(), "a move is pending")


func test_the_module_sends_the_seat_intent_and_drops_the_keys_it_took() -> void:
	var s := X.state(2)
	for e in s.enemies:
		e.telegraph_s = 0.0
	var drv := s.rider(1)
	drv.autopilot = false
	var g: TankGame = autofree(X.game(s, 1))
	var no: Array[StringName] = []
	var right: Array[StringName] = [&"right"]
	var ok: Array[StringName] = [&"confirm"]
	assert_eq(g.local_intents(right, no), [], "right opens the picker")
	assert_eq(g.seat_picker.pick, TankIds.ENGINE_STEAM)
	assert_eq(g.local_intents(ok, no), [TankIntents.seat(TankIds.ENGINE_STEAM)])
	# the Gun: left / right still cycle targets, swap opens the picker, confirm sits (no fire)
	var gun := s.rider(2)
	gun.autopilot = false
	gun.seat_lock_s = 0.0
	var gg: TankGame = autofree(X.game(s, 2))
	var left: Array[StringName] = [&"left"]
	assert_eq(gg.local_intents(left, no), [TankIntents.target(TankIds.TARGET_PREV)])
	assert_false(gg.seat_picker.is_open())
	var swap: Array[StringName] = [&"swap"]
	gg.local_intents(swap, no)
	assert_true(gg.seat_picker.is_open())
	var sit := gg.local_intents(ok, no)
	assert_eq(sit, [TankIntents.seat(TankIds.ENGINE_STEAM)], "a sit, never a shot")
	gun.seat_lock_s = 20.0
	assert_eq(gg.local_intents(ok, no), [TankIntents.make(TankIds.INTENT_FIRE)], "locked: fire")


func test_the_rack_pips_and_the_secondaries_rate_come_from_the_state() -> void:
	var s := X.state(4)
	var p := _panel(autofree(X.game(s)))
	p.refresh()
	assert_eq(p.rack, 2, "the fixture's rack")
	(s.station(TankIds.ENGINE_STEAM) as TankSteamState).rack = 3
	p.refresh()
	assert_eq(p.rack, 3)
	(s.station(TankIds.ENGINE_STEAM) as TankSteamState).rack = 9
	assert_eq(TankHudModel.rack(s), TankConst.RACK_MAX, "clamped to the rack")
	assert_eq(p.feed_rpm, 0.0, "the Secondaries seat is empty: silent")
	reseat(
		s, [TankIds.ENGINE_DIESEL, TankIds.ENGINE_DYNAMO, TankIds.ENGINE_STEAM, TankIds.ENGINE_FEED]
	)
	(s.station(TankIds.ENGINE_FEED) as TankFeedState).rpm = 184.0
	p.refresh()
	assert_eq(p.feed_rpm, 184.0)
	assert_eq(p.tx("TANK_HUD_PER_MIN", [roundi(p.feed_rpm)]), "184/min")
	p.queue_redraw()
	await wait_physics_frames(2)
	assert_gt(p.draws, 0)


func test_the_secondaries_card_says_no_target_while_its_rider_pedals_at_nothing() -> void:
	var s := X.state(4)
	assert_eq(TankHudModel.feed_label(s, 90.0), "", "an empty seat: no rate line")
	reseat(
		s, [TankIds.ENGINE_DIESEL, TankIds.ENGINE_DYNAMO, TankIds.ENGINE_STEAM, TankIds.ENGINE_FEED]
	)
	var fd := s.station(TankIds.ENGINE_FEED) as TankFeedState
	fd.rpm = 180.0
	assert_eq(TankHudModel.feed_label(s, 90.0), "TANK_HUD_PER_MIN", "firing: the rate")
	fd.rpm = 0.0
	assert_eq(
		TankHudModel.feed_label(s, 90.0), "TANK_HUD_NO_TARGET", "pedalling, silent: no target"
	)
	assert_eq(TankHudModel.feed_label(s, 0.0), "TANK_HUD_PER_MIN", "not pedalling: 0/min")
	s.hull.breakdown = true
	assert_eq(TankHudModel.feed_label(s, 90.0), "TANK_HUD_PER_MIN", "the guns down: 0/min")
	s.hull.breakdown = false
	fd.reserve = true
	assert_eq(TankHudModel.feed_label(s, 90.0), "", "on reserve: the card says RESERVE")
	var g: TankGame = autofree(X.game(s))
	var txt := TankHud.tx(g, "TANK_HUD_NO_TARGET")
	assert_eq(txt, "no target")
	for art in CANVASES:
		var w := TankHudSeats.card_rects(art)[0].size.x
		assert_lte(D.text_w(txt) + 6.0, w - 6.0, "it fits a card on %s" % str(art))
	var idle := TankHud.tx(g, "TANK_HUD_DO_FEED_IDLE", ["60"])
	assert_lte(
		D.text_w(idle, 2), float(TankHudMine.W) - 12.0, "my numbers' line fits in large type"
	)
	fd.reserve = false
	for e in s.enemies:
		e.telegraph_s = 0.0
	s.boss.telegraph_s = 0.0
	assert_eq(TankHudModel.telegraph_left(s), 0.0, "no shot coming: no surge")
	var r := s.rider_at(fd.slot)
	var line := TankHudModel.instruction(s, r, {"cad": 90.0})
	assert_eq(line["key"], "TANK_HUD_DO_FEED_IDLE", "my numbers say it too")


func test_every_seat_card_carries_its_erg_or_sim_tag() -> void:
	var cards := TankHudModel.seat_cards(X.state(3), 1)
	var modes: Array[String] = []
	for c: Dictionary in cards:
		modes.append(str(c["mode"]))
	assert_eq(modes, [Wl.SIM, Wl.ERG, Wl.SIM, Wl.ERG, Wl.SIM], "Drive, Gun, Loader, Lights, Sec.")
	assert_eq(Wl.SIM, "SIM")
	assert_eq(Wl.ERG, "ERG")


func test_my_numbers_follow_the_seat() -> void:
	var want := {
		TankIds.ENGINE_DIESEL: TankHudModel.DO_HOLD,
		TankIds.ENGINE_DYNAMO: TankHudModel.DO_HOLD,
		TankIds.ENGINE_STEAM: TankHudModel.DO_BUILD,
		TankIds.ENGINE_ARC: TankHudModel.DO_HOLD,
		TankIds.ENGINE_FEED: TankHudModel.DO_FEED,
	}
	for engine: String in TankIds.SEATS:
		var s := X.state(1)
		for e in s.enemies:
			e.telegraph_s = 0.0
		reseat(s, [engine])
		var r := s.rider(1)
		r.target_pct = float(TankFixtures.TARGETS[engine])
		(s.station(TankIds.ENGINE_FEED) as TankFeedState).rpm = 180.0
		var g: TankGame = autofree(X.game(s, 1))
		var m := _mine(g)
		m.refresh()
		assert_eq(str(m.m["engine"]), engine)
		assert_eq(str(m.m["seat"]), str(TankIds.SEAT_LABELS[engine]), engine)
		assert_eq(str(m.m["kind"]), str(want[engine]), engine)
		var line := str(m.m["line"])
		assert_ne(line, "", engine)
		assert_lte(D.text_w(line, 2), float(TankHudMine.W - 12), "%s: %s fits" % [engine, line])
		var mode := TankHudModel.plan_mode(s, engine)
		assert_eq(bool(m.m["sim"]), mode == Wl.SIM, engine)
		if mode == Wl.ERG:
			var band: Vector2 = m.m["band"]
			var target := r.target_pct / 100.0 * r.ftp
			assert_almost_eq(band.x, 0.95 * target, 0.01, "%s: its ERG band" % engine)
		if engine == TankIds.ENGINE_FEED:
			assert_eq(line, "SPIN 60+ 180/MIN", "the rounds a minute")
		m.queue_redraw()
	var g0: TankGame = autofree(X.game(X.state(1)))
	assert_eq(TankHud.tx(g0, "TANK_HUD_SPRINT"), "SPRINT", "W' is SPRINT")
	await wait_physics_frames(2)


func test_the_layout_keeps_the_corner_the_tank_band_and_my_numbers_clear() -> void:
	var g: TankGame = autofree(X.game(X.state(4)))
	var widest := 0.0
	for k in HINT_KEYS:
		widest = maxf(widest, D.text_w(TankHud.tx(g, k)) + 10.0)
	for art in CANVASES:
		var canvas := Rect2(Vector2.ZERO, Vector2(art))
		var own := Rect2(TankHud.anchored(TankHud.LAYOUT["seats"], art))
		var mine := Rect2(TankHud.anchored(TankHud.LAYOUT["mine"], art))
		var clear := Rect2(TankHud.anchored(TankHud.CLEAR, art))
		var cards := TankHudSeats.card_rects(art)
		for i in cards.size():
			var c := Rect2(cards[i].position + own.position, cards[i].size)
			var h := TankHudSeats.hint_rect(cards[i], widest, art)
			h.position += own.position
			for r: Rect2 in [c, h]:
				var what := "card %d %s on %s" % [i, r, art]
				assert_true(canvas.encloses(r), what)
				assert_false(r.intersects(clear), "%s: the corner" % what)
				assert_false(r.intersects(mine), "%s: my numbers" % what)
				assert_gte(r.position.y, float(TankHud.TANK_BAND_Y.y), "%s: the tank band" % what)


func test_the_fonts_cover_the_seat_panels_text() -> void:
	var g: TankGame = autofree(X.game(X.state(2)))
	var have := {}
	for ch in TankHudFont.chars():
		have[ch] = true
	var keys: Array[String] = HINT_KEYS.duplicate()
	keys.append_array(["TANK_HUD_SEAT_EMPTY", "TANK_HUD_SEAT_MOVE_OK", "TANK_HUD_SPRINT"])
	keys.append_array(["TANK_HUD_DO_BUILD", "TANK_HUD_DO_OVER", "TANK_HUD_DO_FEED"])
	keys.append("TANK_HUD_DO_FEED_IDLE")
	keys.append_array(["TANK_HUD_PER_MIN", "TANK_HELP_SEATS", "TANK_HELP_SEAT_LOCK"])
	keys.append("TANK_HUD_NO_TARGET")
	for e: String in TankIds.SEATS:
		keys.append("TANK_HUD_TAB_" + e.to_upper())
		keys.append("TANK_HUD_TAB_SHORT_" + e.to_upper())
		keys.append(str(TankIds.SEAT_LABELS[e]))
	for k in keys:
		var t := TankHud.tx(g, k, ["60", "180"])
		assert_ne(t, k, "%s has a string" % k)
		for ch in t.to_upper() + t.to_lower():
			assert_true(have.has(ch), "%s: %s in the stencil faces" % [k, ch])
	for e2: String in TankIds.SEATS:
		var tab := TankHud.tx(g, "TANK_HUD_TAB_" + e2.to_upper())
		assert_lte(D.text_w(tab) + 16.0, float(TankHudSeats.CARD_W) - 8.0, "%s's tab fits" % e2)
	assert_true(D.ICONS.has(TankIds.ENGINE_FEED), "the Secondaries' icon")


func test_the_belt_feed_paints_two_rounds_a_revolution() -> void:
	assert_eq(TankMech.PARTS["feed"]["rounds_fed_both_belts"], TankFeedState.ROUNDS_PER_REV)
	var a := Image.create_empty(TankMech.W, TankMech.H, false, Image.FORMAT_RGBA8)
	var b := Image.create_empty(TankMech.W, TankMech.H, false, Image.FORMAT_RGBA8)
	var c := Image.create_empty(TankMech.W, TankMech.H, false, Image.FORMAT_RGBA8)
	TankMech.paint_ex(a, "feed", 0.3, 1.0, 1.0, Color(0.9, 0.5, 0.2), 90.0)
	TankMech.paint_ex(b, "feed", 1.3, 1.0, 1.0, Color(0.9, 0.5, 0.2), 90.0)
	TankMech.paint_ex(c, "feed", 0.55, 1.0, 1.0, Color(0.9, 0.5, 0.2), 90.0)
	var loop := 0
	var moved := 0
	var counter := Rect2i(12, 5, 17, 9)
	for y in TankMech.H:
		for x in TankMech.W:
			if counter.has_point(Vector2i(x, y)):
				continue
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				loop += 1
			if not a.get_pixel(x, y).is_equal_approx(c.get_pixel(x, y)):
				moved += 1
	assert_eq(loop, 0, "one crank revolution is one seamless loop (but the round counter)")
	assert_gt(moved, 20, "the feed moves with the crank")
	var low := Image.create_empty(TankMech.W, TankMech.H, false, Image.FORMAT_RGBA8)
	TankMech.paint_ex(low, "feed", 0.3, 0.3, 1.0, Color(0.9, 0.5, 0.2), 90.0)
	var lit := 0
	for y2 in TankMech.H:
		for x2 in TankMech.W:
			if not a.get_pixel(x2, y2).is_equal_approx(low.get_pixel(x2, y2)):
				lit += 1
	assert_gt(lit, 20, "and changes with the power")


func test_the_secondaries_dial_shows_while_their_seat_is_manned() -> void:
	var s := X.state(4)
	var g: TankGame = autofree(X.game(s))
	var tags := TankHudTags.new().setup(g, TankHud.LAYOUT["tags"]) as TankHudTags
	add_child_autofree(tags)
	tags.size = Vector2(tags.art_rect.size * 2)
	tags.refresh()
	assert_false(tags.m.has("sec"), "the Secondaries seat is empty: no dial")
	var seats := [TankIds.ENGINE_DIESEL, TankIds.ENGINE_DYNAMO, TankIds.ENGINE_STEAM]
	seats.append(TankIds.ENGINE_FEED)
	reseat(s, seats)
	(s.station(TankIds.ENGINE_FEED) as TankFeedState).rpm = 180.0
	tags.refresh()
	assert_true(tags.m.has("sec"), "manned and firing")
	var sec: Dictionary = tags.m["sec"]
	assert_eq(float(sec["rpm"]), 180.0)
	assert_between(float(sec["deg"]), TankHudTags.SEC_MIN, TankHudTags.SEC_MAX)
	var be := TankHudTags.bow_elevation(s, tags.geom())
	assert_eq(float(be["deg"]), float(sec["deg"]), "one function for the guns' elevation")
	(s.station(TankIds.ENGINE_FEED) as TankFeedState).rpm = 0.0
	for e in s.enemies:
		e.mode = TankIds.EM_DEAD
	tags.refresh()
	assert_false(tags.m.has("sec"), "silent with nothing in reach")
	assert_false(bool(TankHudTags.bow_elevation(s, tags.geom())["target"]))
	(s.station(TankIds.ENGINE_FEED) as TankFeedState).rpm = 120.0
	tags.refresh()
	tags.queue_redraw()
	await wait_physics_frames(2)
	assert_gt(tags.draws, 0)
