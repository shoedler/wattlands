extends GutTest
## SiegeIds (STATE_V2.md "Ids"), SiegeIntents (brief 2.6 wire forms and normalization) and the
## intent limiter (5 a second per peer).


func test_station_ids() -> void:
	assert_eq(SiegeIds.STATION_MINE, 0)
	assert_eq(SiegeIds.TARGET_GEN, 0, "kept as the mine")
	assert_eq(SiegeIds.STATION_BALLISTA, 1)
	assert_eq(SiegeIds.STATION_ONAGER, 2)
	assert_eq(SiegeIds.STATION_ARROWS, 3)
	assert_eq(SiegeIds.STATION_TAR, 4)
	assert_eq(SiegeIds.STATION_COUNT, 5)
	assert_eq(SiegeIds.STATION_NAMES, ["mine", "ballista", "onager", "arrows", "tar"])
	assert_eq(SiegeIds.WEAPONS, [1, 2, 3])


func test_pad_ids() -> void:
	assert_eq(SiegeIds.PAD_COUNT, 4)
	assert_eq([SiegeIds.PAD_NONE, SiegeIds.PAD_SCORPION, SiegeIds.PAD_CALTROP], [0, 1, 2])
	assert_eq(SiegeIds.pad_code("scorpion"), 1)
	assert_eq(SiegeIds.pad_code("nope"), 0)
	assert_eq(SiegeIds.BOARDED_PADS, [1, 2])


func test_enemy_ids() -> void:
	assert_eq(
		[
			SiegeIds.ENEMY_SPEAR,
			SiegeIds.ENEMY_SHIELD,
			SiegeIds.ENEMY_CHARIOT,
			SiegeIds.ENEMY_RAM,
			SiegeIds.ENEMY_TOWER
		],
		[1, 2, 3, 4, 5]
	)
	assert_eq(SiegeIds.ENEMY_NAMES, ["", "spear", "shield", "chariot", "ram", "tower"])
	assert_eq(SiegeIds.enemy_code("tower"), 5)
	assert_eq(SiegeIds.enemy_code("raiders"), 0, "v0.1 names are gone")
	assert_true(SiegeIds.is_engine(SiegeIds.ENEMY_RAM))
	assert_true(SiegeIds.is_engine(SiegeIds.ENEMY_TOWER))
	assert_false(SiegeIds.is_engine(SiegeIds.ENEMY_CHARIOT))


func test_enemy_states() -> void:
	assert_eq(
		[SiegeIds.EN_WALK, SiegeIds.EN_BATTER, SiegeIds.EN_RETREAT, SiegeIds.EN_DOCKED],
		[0, 1, 2, 3]
	)


func test_shot_kinds_and_sources() -> void:
	assert_eq(
		[SiegeIds.SHOT_BOLT, SiegeIds.SHOT_STONE, SiegeIds.SHOT_ARROW, SiegeIds.SHOT_SCORPION],
		[0, 1, 2, 3]
	)
	assert_eq(SiegeIds.shot_kind(SiegeIds.STATION_BALLISTA), SiegeIds.SHOT_BOLT)
	assert_eq(SiegeIds.shot_kind(SiegeIds.STATION_ONAGER), SiegeIds.SHOT_STONE)
	assert_eq(SiegeIds.shot_kind(SiegeIds.STATION_ARROWS), SiegeIds.SHOT_ARROW)
	assert_eq(SiegeIds.SRC_PAD, 10)


func test_perks() -> void:
	assert_eq([SiegeIds.PERK_RESERVE, SiegeIds.PERK_AQUEDUCT, SiegeIds.PERK_CAULDRON], [1, 2, 3])
	assert_eq(SiegeIds.PERK_NAMES[3], "spare_cauldron")
	for item: String in SiegeIds.PERK_ITEMS:
		assert_eq(SiegeIds.PERK_NAMES[int(SiegeIds.PERK_ITEMS[item])], item)


func test_event_types_are_the_brief_s() -> void:
	assert_eq(
		SiegeIds.EVENT_TYPES,
		[
			"wave_start",
			"wave_end",
			"rush",
			"push",
			"dock",
			"reach",
			"shot",
			"kill",
			"leak",
			"breach",
			"gate_restored",
			"buy",
			"receipt",
			"route",
			"overdrive"
		]
	)


func test_predicates() -> void:
	assert_true(SiegeIds.is_station(0))
	assert_true(SiegeIds.is_station(4))
	assert_false(SiegeIds.is_station(5))
	assert_false(SiegeIds.is_station(-1))
	assert_true(SiegeIds.is_weapon(2))
	assert_false(SiegeIds.is_weapon(4))
	assert_false(SiegeIds.is_weapon(0))
	assert_true(SiegeIds.is_pad(4))
	assert_false(SiegeIds.is_pad(5))
	assert_false(SiegeIds.is_pad(0))


func test_route_words_accept_mine_and_gen() -> void:
	assert_eq(SiegeIntents.normalize(SiegeIntents.route("mine"))["to"], SiegeIds.STATION_MINE)
	assert_eq(SiegeIntents.normalize(SiegeIntents.route("gen"))["to"], SiegeIds.STATION_MINE)
	assert_eq(SiegeIntents.normalize(SiegeIntents.route("next"))["to"], SiegeIds.ROUTE_NEXT)
	assert_eq(SiegeIntents.normalize(SiegeIntents.route("prev"))["to"], SiegeIds.ROUTE_PREV)
	assert_eq(SiegeIntents.normalize(SiegeIntents.route("hot"))["to"], SiegeIds.ROUTE_HOT)


func test_route_to_a_station_number() -> void:
	for id in 5:
		assert_eq(SiegeIntents.normalize(SiegeIntents.route(id))["to"], id)
	assert_eq(SiegeIntents.normalize({"k": "route", "to": 3.0})["to"], 3, "JSON floats are fine")


func test_bad_routes_are_junk() -> void:
	assert_eq(SiegeIntents.normalize(SiegeIntents.route(5)), {})
	assert_eq(SiegeIntents.normalize(SiegeIntents.route(-1)), {})
	assert_eq(SiegeIntents.normalize(SiegeIntents.route(2.5)), {})
	assert_eq(SiegeIntents.normalize(SiegeIntents.route("tower")), {})
	assert_eq(SiegeIntents.normalize({"k": "route"}), {})


func test_buy_a_station_upgrade_needs_a_station_1_to_4() -> void:
	var it := SiegeIntents.normalize(SiegeIntents.pick(SiegeIds.ITEM_UPGRADE, 2))
	assert_eq(it["item"], "upgrade")
	assert_eq(it["station"], 2)
	assert_eq(it["pad"], 0)
	assert_eq(
		SiegeIntents.normalize(SiegeIntents.pick(SiegeIds.ITEM_UPGRADE, 0)), {}, "not the mine"
	)
	assert_eq(SiegeIntents.normalize(SiegeIntents.pick(SiegeIds.ITEM_UPGRADE, 5)), {})
	assert_eq(SiegeIntents.normalize({"k": "buy", "item": "upgrade"}), {})


func test_buy_a_pad_item_needs_a_pad_1_to_4() -> void:
	var it := SiegeIntents.normalize(SiegeIntents.pick(SiegeIds.ITEM_SCORPION, 3))
	assert_eq(it["pad"], 3)
	assert_eq(it["station"], 0)
	assert_eq(SiegeIntents.normalize(SiegeIntents.pick(SiegeIds.ITEM_PAD_UPGRADE, 4))["pad"], 4)
	assert_eq(SiegeIntents.normalize(SiegeIntents.pick(SiegeIds.ITEM_SCORPION, 5)), {})
	assert_eq(SiegeIntents.normalize(SiegeIntents.pick(SiegeIds.ITEM_PAD_UPGRADE, 0)), {})


func test_plain_items_need_nothing_else() -> void:
	for item: String in [
		SiegeIds.ITEM_MINE,
		SiegeIds.ITEM_IRON_BANDS,
		SiegeIds.ITEM_REPAIR,
		SiegeIds.ITEM_RESERVE,
		SiegeIds.ITEM_AQUEDUCT,
		SiegeIds.ITEM_CAULDRON
	]:
		var it := SiegeIntents.normalize(SiegeIntents.pick(item))
		assert_eq(it["item"], item)
		assert_eq(it["station"], 0)
		assert_eq(it["pad"], 0)


func test_v01_items_and_save_are_junk() -> void:
	for item: String in ["build_ballista", "generator", "save", "nope"]:
		assert_eq(SiegeIntents.normalize({"k": "buy", "item": item}), {}, item)


func test_pick_is_the_shop_intent_and_buy_is_its_old_wire_word() -> void:
	assert_eq(SiegeIds.INTENT_KINDS, ["route", "pick", "overdrive"])
	var it := SiegeIntents.normalize(SiegeIntents.pick(SiegeIds.ITEM_UPGRADE, 3))
	assert_eq(it["k"], "pick")
	assert_eq(it["station"], 3)
	var old := SiegeIntents.normalize({"k": "buy", "item": "mine"})
	assert_eq(old["k"], "pick", "an old client's buy reads as a pick")
	assert_eq(old["item"], "mine")
	assert_eq(SiegeIntents.normalize({"k": "pick", "item": "save"}), {}, "Save gold is no intent")
	assert_eq(SiegeIntents.normalize({"k": "pick"}), {})
	assert_eq(SiegeIntents.normalize({"k": "pick", "item": 5}), {})
	assert_eq(SiegeIntents.at_of(it), 3)
	var pad := SiegeIntents.normalize(SiegeIntents.pick(SiegeIds.ITEM_SCORPION, 2))
	assert_eq(SiegeIntents.at_of(pad), 2)
	assert_eq(SiegeIntents.at_of(SiegeIntents.normalize(SiegeIntents.pick("mine"))), 0)


func test_picks_share_the_five_a_second_limit() -> void:
	var lim := SiegeIntentLimiter.new()
	var raw: Array = []
	for i in 8:
		raw.append(SiegeIntents.pick(SiegeIds.ITEM_MINE))
	assert_eq(lim.filter(1, 0, raw).size(), 5, "a flood of picks is cut like any intent")


func test_item_codes_round_trip() -> void:
	for item: String in SiegeIds.ITEMS:
		assert_eq(SiegeIds.item_of(SiegeIds.item_code(item)), item)
	assert_eq(SiegeIds.item_code("nope"), 0)
	assert_eq(SiegeIds.item_of(0), "")
	assert_eq(SiegeIds.item_of(99), "")


func test_auto_tags() -> void:
	var it := SiegeIntents.normalize(SiegeIntents.pick(SiegeIds.ITEM_MINE, 0, true))
	assert_true(it["auto"])
	assert_eq(it["via"], SiegeIds.VIA_AUTO)
	assert_true(SiegeIntents.normalize({"k": "overdrive", "via": "auto"})["auto"])
	assert_false(SiegeIntents.normalize(SiegeIntents.overdrive("surge"))["auto"])


func test_overdrive_vias() -> void:
	for via: String in ["action", "surge", "button"]:
		assert_eq(SiegeIntents.normalize(SiegeIntents.overdrive(via))["via"], via)
	assert_eq(SiegeIntents.normalize({"k": "overdrive", "via": "telepathy"}), {})
	assert_eq(SiegeIntents.normalize({"k": "overdrive"})["via"], "action", "the default")


func test_junk_is_dropped() -> void:
	assert_eq(SiegeIntents.normalize(null), {})
	assert_eq(SiegeIntents.normalize("route"), {})
	assert_eq(SiegeIntents.normalize({"k": "dance"}), {})
	var big := {"k": "overdrive"}
	for i in 10:
		big["x%d" % i] = i
	assert_eq(SiegeIntents.normalize(big), {}, "too many keys")
	assert_eq(SiegeIntents.normalize_all([null, SiegeIntents.route("mine"), {"k": 1}]).size(), 1)


func test_the_limiter_allows_5_a_second_per_peer() -> void:
	var lim := SiegeIntentLimiter.new()
	var raw: Array = []
	for i in 8:
		raw.append(SiegeIntents.route("next"))
	assert_eq(lim.filter(1, 0, raw).size(), 5)
	assert_eq(lim.filter(1, 10, raw).size(), 0, "still inside the second")
	assert_eq(lim.filter(2, 10, raw).size(), 5, "another peer has its own budget")
	assert_eq(lim.filter(1, 20, raw).size(), 5, "a new second")


func test_the_limiter_drops_junk_before_counting() -> void:
	var lim := SiegeIntentLimiter.new()
	var raw: Array = [null, {"k": "x"}, SiegeIntents.route("hot")]
	assert_eq(lim.filter(1, 0, raw).size(), 1)
	for i in 4:
		assert_true(lim.allow(1, 1))
	assert_false(lim.allow(1, 1))
