extends GutTest
## Real rules events through the real module and view into the kit, never a hand-fed cue: the owner played the game
## and heard no arrows, while the bank passed its scorecard and every hand-fed test. A real wave's `shot` events must
## each start a flight sound that lasts the flight.

const F := preload("res://tests/games/siege/siege_fakes.gd")
const FIX_SECONDS := 150.0
## What may count as a projectile's flight sound, by shot kind. The old names are here on purpose: they ran for a
## fifth of the flight on a fifth of the volleys, and that is what these tests catch.
const FLIGHT_SOUNDS := {
	SiegeIds.SHOT_BOLT: ["bolt_whoosh", "bolt_hiss"],
	SiegeIds.SHOT_STONE: ["stone_whoosh", "stone_tumble"],
	SiegeIds.SHOT_ARROW: ["arrow_whistle", "arrow_swarm"],
	SiegeIds.SHOT_SCORPION: ["bolt_whoosh", "bolt_hiss"],
}

var _game: SiegeGame = null
var _view: SiegeView = null
var _shots: Array[Dictionary] = []


func after_each() -> void:
	if _game != null:
		F.free_game(_game)
	_game = null
	_view = null
	_shots.clear()


func _on_cue(kind: String, data: Dictionary) -> void:
	if kind == SiegeIds.EV_SHOT:
		_shots.append(data)


## A real session's first `seconds`: one rider and three bots on the real rules. `seen` gets each new start of the kit.
func _ride(seconds: float, seen: Dictionary) -> void:
	var ctx := F.make_ctx(1, 3, "short", Wl.SOLO, 1, 3)
	_game = F.make_game(ctx)
	var plans := _game.build_effort_plans()
	var final := {}
	for peer: int in plans:
		final[peer] = PlanValidator.finalize(plans[peer])
	_view = _game.make_view() as SiegeView
	add_child_autofree(_view)
	_game.cue.connect(_on_cue)
	for tick in roundi(seconds / Wl.SIM_DT):
		_game.sim_step(Wl.SIM_DT, F.frame(ctx, final, tick))
		_view.update(Wl.SIM_DT)
		_collect(seen)


func _collect(seen: Dictionary) -> void:
	var kit := _view.audio.kit
	for i in kit.played.size():
		var id := kit.played[i]
		seen[id] = int(seen.get(id, 0)) + 1
	kit.clear_played()


func _shots_of(kind: int) -> int:
	var n := 0
	for s in _shots:
		if int(s.get("kind", -1)) == kind:
			n += 1
	return n


func test_every_shot_of_a_real_wave_starts_a_flight_sound() -> void:
	var seen := {}
	_ride(FIX_SECONDS, seen)
	var bolts := _shots_of(SiegeIds.SHOT_BOLT) + _shots_of(SiegeIds.SHOT_SCORPION)
	var arrows := _shots_of(SiegeIds.SHOT_ARROW)
	var stones := _shots_of(SiegeIds.SHOT_STONE)
	assert_gt(arrows, 10, "the organ fires in the first %d s" % FIX_SECONDS)
	assert_gt(bolts, 5, "the bolt throwers fire")
	assert_gt(stones, 2, "the onager fires")
	var flying := func(kind: int) -> int:
		var n := 0
		for id: String in FLIGHT_SOUNDS[kind]:
			n += int(seen.get(id, 0))
		return n
	assert_eq(flying.call(SiegeIds.SHOT_ARROW), arrows, "one flight per volley")
	assert_eq(flying.call(SiegeIds.SHOT_STONE), stones, "one flight per stone")
	assert_eq(flying.call(SiegeIds.SHOT_BOLT), bolts, "one flight per bolt, the Scorpion's too")
