class_name SiegeHudUtil
extends RefCounted
## Helpers for the HUD tests: a SiegeGame around a fixture state, with a recording context.


## A configured module (vo2 content) whose state and players are the fixture's: local peer 1
## (slot 0, in Overdrive), slot 1 rescued, slot 2 reconnecting, slot 3 a bot.
static func make_game(state: SiegeState = null) -> SiegeGame:
	var ctx := SiegeFakes.make_ctx(3, 1, "vo2", Wl.SOLO, 1)
	var g := SiegeFakes.make_game(ctx)
	g.ctx.players = SiegeFixtures.slots()
	g.state = state if state != null else SiegeFixtures.mid_wave()
	g.content = g.state.content
	return g


static func intents_sent(g: SiegeGame) -> Array:
	return (g.ctx.intents as SiegeFakes.Intents).sent


static func free_game(g: SiegeGame) -> void:
	SiegeFakes.free_game(g)
