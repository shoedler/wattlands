extends GutTest
## Zero input at module level (brief 2.5): a human with Autopilot off who only pedals, triggers
## Overdrive by surge and sits through auto-confirmed shops keeps Autopilot routing and shop picks
## for the whole shift, with no double purchase. The module's part (intents pass through tagged,
## nothing ends a fallback, Autopilot buys at most two items a break) is asserted always; what
## needs the combat and shop rules (routing onto a weapon once enemies are in range) is asserted
## as soon as those rules produce enemies.

const K := preload("res://tests/games/siege/module/siege_module_kit.gd")
const F := preload("res://tests/games/siege/siege_fakes.gd")

## [phase index, event] in order.
var _log: Array = []
var _game: SiegeGame = null


func _on_event(e: Dictionary) -> void:
	_log.append([_game.state.phase_index, e])


func test_a_human_who_only_pedals_plays_the_whole_shift_on_autopilot() -> void:
	_game = K.game(1, 0, "short")
	var g := _game
	_log = []
	g.game_event.connect(_on_event)
	var me := g.state.rider(1)
	assert_false(g.ctx.players[0].autopilot, "Autopilot is off for this human")
	assert_true(me.route_fallback and me.shop_fallback, "and the fallbacks start on")
	var max_enemies := 0
	var ever_on_station := false
	var surges := 0
	var auto_buys := 0
	var tick := 0
	while tick * Wl.SIM_DT < 900.0:
		var intents: Array = []
		if g.state.shop_open() and tick % 40 == 0:
			# What the PedalScanList sends when its ERG auto-confirm picks the highlighted item.
			intents.append(SiegeIntents.buy(SiegeIds.ITEM_SCORPION, 2, true))
			intents.append(SiegeIntents.buy(SiegeIds.ITEM_MINE, 0, true))
			auto_buys += 2
		elif g.state.in_wave() and tick % 100 == 0:
			intents.append(SiegeIntents.overdrive("surge"))
			surges += 1
		K.step(g, tick, {1: intents})
		max_enemies = maxi(max_enemies, g.state.enemies.size())
		ever_on_station = ever_on_station or SiegeIds.is_weapon(me.target)
		tick += 1
	assert_gt(auto_buys, 10)
	assert_gt(surges, 5)
	assert_true(me.route_fallback, "a surge and the auto-confirms never end Autopilot routing")
	assert_true(me.shop_fallback, "nor Autopilot's shop")
	assert_gte(me.gold, 0.0)
	# Autopilot buys at most two items in a break, whatever the PedalScanList auto-confirmed.
	var per_break := {}
	for entry: Array in _log:
		var e: Dictionary = entry[1]
		if e["type"] == SiegeIds.EV_BUY and int(e["ok"]) != 0:
			per_break[entry[0]] = int(per_break.get(entry[0], 0)) + 1
	for ph: int in per_break:
		assert_lte(per_break[ph], 2, "phase %d: no double purchase" % ph)
	# Every directive the module sent is the Overdrive block, nothing else.
	for req: Array in K.directives(g).requests:
		assert_eq((req[1] as Dictionary).keys().size(), 4)
		assert_eq(req[1]["reason"], "overdrive")
	if max_enemies > 0:
		assert_true(
			ever_on_station, "enemies came into range: Autopilot sent the rider to a weapon"
		)
	K.F.free_game(g)
