extends GutTest
## SiegeIntents and SiegeIntentLimiter (brief 2.6): normalization with int(), junk rejected, the
## auto tag, and 5 intents a second per peer.


func test_route_targets() -> void:
	var cases := {
		"gen": SiegeIds.TARGET_GEN,
		"next": SiegeIds.ROUTE_NEXT,
		"prev": SiegeIds.ROUTE_PREV,
		"hot": SiegeIds.ROUTE_HOT
	}
	for w: String in cases:
		var n := SiegeIntents.normalize({"k": "route", "to": w})
		assert_eq(n["to"], cases[w], w)
		assert_eq(n["via"], SiegeIds.VIA_ACTION)
		assert_false(n["auto"])
	assert_eq(
		SiegeIntents.normalize({"k": "route", "to": 3.0})["to"], 3, "a JSON number becomes an int"
	)
	assert_eq(SiegeIntents.normalize({"k": "route", "to": 8})["to"], 8)
	for bad: Variant in [0, 9, -1, 2.5, "3", "north", null, [1]]:
		assert_eq(SiegeIntents.normalize({"k": "route", "to": bad}), {}, "route to %s" % [bad])


func test_buys() -> void:
	var n := SiegeIntents.normalize({"k": "buy", "item": "build_ballista", "pad": 5.0})
	assert_eq(
		n, {"k": "buy", "to": 0, "item": "build_ballista", "pad": 5, "auto": false, "via": "action"}
	)
	assert_eq(
		SiegeIntents.normalize({"k": "buy", "item": "repair", "pad": 99})["pad"],
		0,
		"no pad for a team item"
	)
	assert_eq(SiegeIntents.normalize({"k": "buy", "item": "upgrade"}), {}, "upgrade needs a pad")
	assert_eq(SiegeIntents.normalize({"k": "buy", "item": "save"}), {}, "save is never sent")
	assert_eq(SiegeIntents.normalize({"k": "buy", "item": "catapult", "pad": 1}), {})
	var auto := SiegeIntents.normalize(SiegeIntents.buy("generator", 0, true))
	assert_true(auto["auto"], "a PedalScanList auto-confirm")
	assert_eq(auto["via"], SiegeIds.VIA_AUTO)
	assert_true(SiegeIntents.normalize({"k": "buy", "item": "repair", "auto": 1.0})["auto"])
	assert_false(SiegeIntents.normalize({"k": "buy", "item": "repair", "auto": 0})["auto"])
	for item: String in SiegeIds.ITEMS:
		var raw := SiegeIntents.buy(item, 2)
		assert_false(SiegeIntents.normalize(raw).is_empty(), item)


func test_overdrive_and_junk() -> void:
	assert_eq(SiegeIntents.normalize(SiegeIntents.overdrive("surge"))["via"], "surge")
	assert_eq(SiegeIntents.normalize({"k": "overdrive"})["via"], "action")
	assert_true(SiegeIntents.normalize({"k": "overdrive", "auto": 1})["auto"])
	assert_eq(SiegeIntents.normalize({"k": "overdrive", "via": "telepathy"}), {})
	for junk: Variant in [null, 5, "route", [], {}, {"k": 1}, {"k": "boost"}]:
		assert_eq(SiegeIntents.normalize(junk), {}, str(junk))
	var big := {"k": "overdrive"}
	for i in 10:
		big["x%d" % i] = i
	assert_eq(SiegeIntents.normalize(big), {}, "too many keys")
	var list := SiegeIntents.normalize_all([null, {"k": "route", "to": "gen"}, {"k": "nope"}])
	assert_eq(list.size(), 1)


func test_the_limiter_allows_five_a_second_per_peer() -> void:
	var lim := SiegeIntentLimiter.new()
	var raw: Array = []
	for i in 8:
		raw.append({"k": "route", "to": "next"})
	assert_eq(lim.filter(2, 100, raw).size(), 5, "5 of 8 in one tick")
	assert_eq(lim.filter(3, 100, raw).size(), 5, "per peer")
	assert_eq(lim.filter(2, 119, raw).size(), 0, "still inside the second")
	assert_eq(lim.filter(2, 120, raw).size(), 5, "a second later")
	assert_eq(lim.filter(4, 1, [null, 7, {"k": "x"}]).size(), 0)
	assert_true(lim.allow(4, 2), "junk never counted")
	var spread := SiegeIntentLimiter.new()
	var ok := 0
	for t in 40:
		ok += int(spread.allow(1, t * 4))
	assert_eq(ok, 40, "one every 0.2 s is 5 a second: all allowed")
