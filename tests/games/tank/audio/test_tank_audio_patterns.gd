extends GutTest
## D1 for every seat, in the game: past the first revolution each stroke fires exactly as often as its pattern says, at
## its fraction, with the gates a working seat has open. The scorecard scores the seat in preview.lead and the crew test
## only compares the kit's records with its own counter, so a wrong `when` or `at` on another seat would pass both.
## The table is written out here on purpose: reading the bank's `at` would agree with any mistake in it.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")
const DT := 1.0 / 60.0
## A revolution and a horizon: the first frame primes past any fraction under one frame's turn (rivet_ring at 0.03).
const PRIME_REVS := 1.5
const RUN_S := 10.0
const PHASE_EPS := 0.012
const RPMS: Array[float] = [60.0, 90.0, 110.0]
## seat -> power, and stroke -> fractions. Everything else its machine can play stays silent.
const WORKING := {
	"drive":
	{
		"power": 1.2,
		"strokes":
		{
			"diesel_fire_a": [0.2778],
			"diesel_fire_b": [0.6111],
			"diesel_fire_c": [0.9444],
			"diesel_fire_hard": [0.2778, 0.6111, 0.9444],
			"diesel_valve_ex": [0.3, 0.6333, 0.9667],
			"diesel_valve_in": [0.1111, 0.4444, 0.7778],
			"exhaust_crackle": [0.05, 0.38, 0.72],
		},
	},
	"gun":
	{
		"power": 1.0,
		"strokes":
		{
			"cap_dump": [0.8],
			"brush_tick": [0.0, 0.3333, 0.6667],
			"hoist_ratchet": [0.0, 0.25, 0.5, 0.75],
		},
	},
	"loader":
	{
		"power": 1.0,
		"strokes":
		{
			"chuff_a": [0.0],
			"chuff_b": [0.5],
			"steam_valve": [0.25, 0.75],
			"hoist_pawl": [0.0],
		},
	},
	"lights":
	{
		"power": 1.5,
		"strokes":
		{
			"arc_relay": [0.0, 0.5],
			"arc_relay_over": [0.25, 0.75],
			"arc_spark": [0.44, 0.94],
			"belt_tick": [0.0, 0.25, 0.5, 0.75],
		},
	},
	"sec":
	{
		"power": 1.0,
		"strokes":
		{
			"bow_shot": [0.0, 0.1667, 0.3333, 0.5, 0.6667, 0.8333],
			"bolt_clack": [0.0, 0.1667, 0.3333, 0.5, 0.6667, 0.8333],
			"link_clink": [0.25, 0.75],
			"casing_tink": [0.2, 0.7],
		},
	},
	"repair": {"power": 1.0, "strokes": {"rivet_hit": [0.0], "rivet_ring": [0.03]}},
}
## The same seats with their gates shut: what is left of each.
const SHUT := {
	"gun": {"cap_dump": [0.8], "brush_tick": [0.0, 0.3333, 0.6667]},
	"loader": {"chuff_a": [0.0], "chuff_b": [0.5], "steam_valve": [0.25, 0.75]},
	"sec": {"bolt_clack": [0.0, 0.1667, 0.3333, 0.5, 0.6667, 0.8333], "link_clink": [0.25, 0.75]},
	"repair": {"repair_idle": [0.0]},
}

var _bank: AudioBank = null


func before_all() -> void:
	_bank = AudioBank.load_bank(TankAudio.BANK_PATH)


func before_each() -> void:
	AudioBuses.clear_ducks()


func after_each() -> void:
	AudioBuses.clear_ducks()


func _state_for(seat: String) -> TankState:
	var s := TankFixturesV4.make("repair") if seat == "repair" else TankFixtures.state(4)
	s.hull.speed_mps = 0.0
	return s


## A state with `seat` at work (every gate of its strokes open), or with them shut.
func _prepared(seat: String, gates_open: bool) -> TankState:
	var s := _state_for(seat)
	match seat:
		"gun":
			(s.station(TankIds.ENGINE_DYNAMO) as TankDynamoState).hoist_s = (
				1000.0 if gates_open else 0.0
			)
		"loader":
			(s.station(TankIds.ENGINE_STEAM) as TankSteamState).loaded = not gates_open
		"sec":
			var feed := s.station(TankIds.ENGINE_FEED) as TankFeedState
			feed.rpm = 120.0 if gates_open else 0.0
			feed.rounds = 8 if gates_open else 0
		"repair":
			(s.station(TankIds.ENGINE_REPAIR) as TankRepairState).working = gates_open
	return s


func _make(state: TankState) -> TankAudio:
	var g := U.make_game(state, Wl.SOLO, 1)
	autofree(g)
	var a := TankAudio.new()
	a.game = g
	add_child_autofree(a)
	return a


## One seat turning alone for `seconds`. Returns the revs reached.
func _turn(
	a: TankAudio,
	state: TankState,
	seat: String,
	rpm: float,
	power: float,
	revs: float,
	seconds: float
) -> float:
	for _i in roundi(seconds / DT):
		revs += rpm / 60.0 * DT
		a.update(
			state, DT, 1, {seat: {"revs": revs, "rpm": rpm, "power": power, "lead": true}}, 0.0
		)
	return revs


## How many k + f lie in (0, to].
func _pattern_count(f: float, to: float) -> int:
	return floori(to - f) + (1 if f > 0.0 else 0)


func _expected(fractions: Array, from: float, to: float) -> int:
	var n := 0
	for f: Variant in fractions:
		n += _pattern_count(float(f), to) - _pattern_count(float(f), from)
	return n


## Every sound its machine's events can play: one the table does not name must stay silent.
func _assert_counts(
	a: TankAudio, machine: String, strokes: Dictionary, from: float, to: float, text: String
) -> void:
	for ev: Dictionary in _bank.machines[machine]["events"]:
		var id := str(ev["sound"])
		var fractions: Array = strokes.get(id, [])
		assert_eq(a.played.count(id), _expected(fractions, from, to), "%s: %s" % [text, id])


## Each stroke lands on one of its fractions and every fraction is hit: a shifted `at` keeps the count.
func _assert_phases(
	a: TankAudio, strokes: Dictionary, rpm: float, revs: float, text: String
) -> void:
	var rate := rpm / 60.0
	for id: String in strokes:
		var fractions: Array = strokes[id]
		var hit := {}
		for i in a.played.size():
			if a.played[i] != id:
				continue
			var phase := fposmod(revs + (a.played_t[i] - a.kit._t) * rate, 1.0)
			var best := INF
			var best_f := -1.0
			for f: Variant in fractions:
				var d := absf(phase - float(f))
				d = minf(d, 1.0 - d)
				if d < best:
					best = d
					best_f = float(f)
			assert_lte(best, PHASE_EPS, "%s: %s at %.4f" % [text, id, phase])
			hit[best_f] = true
		assert_eq(hit.size(), fractions.size(), "%s: %s hits each fraction" % [text, id])


func test_every_seat_fires_its_whole_pattern_past_the_first_revolution() -> void:
	for seat: String in WORKING:
		var machine: String = TankAudio.MACHINE_OF_SEAT[seat]
		var strokes: Dictionary = WORKING[seat]["strokes"]
		var power: float = WORKING[seat]["power"]
		for rpm in RPMS:
			var state := _prepared(seat, true)
			var a := _make(state)
			var revs := _turn(a, state, seat, rpm, power, 0.0, PRIME_REVS * 60.0 / rpm)
			a.kit.clear_played()
			var voice := a.kit.machine_voice(seat)
			var from := voice.planned_to()
			revs = _turn(a, state, seat, rpm, power, revs, RUN_S)
			var to := voice.planned_to()
			var text := "%s at %d rpm" % [seat, int(rpm)]
			assert_gt(to - from, 9.0, text)
			_assert_counts(a, machine, strokes, from, to, text)
			_assert_phases(a, strokes, rpm, revs, text)
			assert_eq(voice.dropped, 0, text)


func test_a_seat_with_its_gates_shut_keeps_its_base_strokes_and_nothing_more() -> void:
	for seat: String in SHUT:
		var state := _prepared(seat, false)
		var a := _make(state)
		var revs := _turn(a, state, seat, 90.0, 1.0, 0.0, PRIME_REVS * 60.0 / 90.0)
		a.kit.clear_played()
		var voice := a.kit.machine_voice(seat)
		var from := voice.planned_to()
		revs = _turn(a, state, seat, 90.0, 1.0, revs, RUN_S)
		var machine: String = TankAudio.MACHINE_OF_SEAT[seat]
		_assert_counts(a, machine, SHUT[seat], from, voice.planned_to(), seat)


func test_under_the_jars_gate_the_brush_is_the_dynamos_stroke_and_louder_for_it() -> void:
	var state := _state_for("gun")
	var a := _make(state)
	var revs := _turn(a, state, "gun", 90.0, 0.4, 0.0, 2.0)
	assert_does_not_have(a.played, "cap_dump", "the jars do not fill at 0.4")
	assert_has(a.played, "brush_tick")
	var low: float = a.played_db[a.played.rfind("brush_tick")]
	a.kit.clear_played()
	revs = _turn(a, state, "gun", 90.0, 0.7, revs, 2.0)
	assert_has(a.played, "cap_dump")
	var above: float = a.played_db[a.played.rfind("brush_tick")]
	assert_almost_eq(low - above, 8.0, 0.01, "the tick steps back once the dump plays")


func _compressor_db(a: TankAudio) -> float:
	var loop := a.kit.machine_loop("repair")
	for i in loop.count:
		if str(loop.layer(i)["sound"]) == "repair_compressor":
			return loop.db[i]
	return -INF


func test_a_repairs_seat_with_a_full_hull_answers_the_riders_legs() -> void:
	var state := _prepared("repair", false)
	var rep := state.station(TankIds.ENGINE_REPAIR) as TankRepairState
	var a := _make(state)
	var revs := 0.0
	var taps: Array[float] = []
	var hums: Array[float] = []
	for power: float in [0.5, 0.9, 1.2]:
		a.kit.clear_played()
		revs = _turn(a, state, "repair", 90.0, power, revs, 3.0)
		taps.append(a.played_db[a.played.rfind("repair_idle")])
		hums.append(_compressor_db(a))
	for i in 2:
		assert_gt(taps[i + 1], taps[i], "the tap rises with power")
		assert_gt(hums[i + 1], hums[i], "the compressor rises with power")
	rep.working = true
	revs = _turn(a, state, "repair", 90.0, 1.2, revs, 2.0)
	assert_gt(_compressor_db(a), hums[2] + 8.0, "and sits well under the seat at work")
	assert_has(a.played, "rivet_hit")
