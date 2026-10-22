extends Control
## A windowed look at Siege's HUD over the view for tools/screenshot --scene: the mid-wave
## fixture (Overdrive running, a rescue, a reconnect, 43 enemies) with the kit HUD and Siege's
## own Controls, and a stand-in for the app's PANIC button in the reserved corner.
## Options (SIEGE_FIXTURE, ";"-separated): break, prompt, client.

var game: SiegeGame = null
var hud: HudLayer = null


func _ready() -> void:
	var opts := {}
	for tok in OS.get_environment("SIEGE_FIXTURE").split(";", false):
		opts[tok] = true
	var state := SiegeFixtures.mid_wave()
	if opts.has("break"):
		state.role = SiegeIds.ROLE_BREAK
		state.wave_no = 2
		state.phase_kind = Wl.RECOVERY
		state.phase_duration_s = 180.0
		state.phase_elapsed_s = 172.0
		state.enemies.clear()
		state.shots.clear()
		state.zones.clear()
	if opts.has("prompt"):
		var r := state.rider_at(0)
		r.od_state = SiegeIds.OD_READY
		r.od_s = 0.0
		r.od_prompt = true
	var ctx := SiegeFakes.make_ctx(3, 1, "vo2", Wl.SOLO, 1)
	ctx.players = SiegeFixtures.slots()
	game = SiegeFakes.make_game(ctx)
	game.state = state
	game.content = state.content
	var view := SiegeView.new()
	view.game = game
	view.bind(state, state.content.map)
	add_child(view)
	view.rig.push_in(1.0, 0.0)
	hud = HudLayer.new()
	hud.sounds = false
	add_child(hud)
	hud.reserve_corner(HudSpec.BOTTOM_RIGHT, Vector2(380, 100))
	hud.build(game.hud_spec(), ctx)
	hud.set_readout(SiegeHud.READOUT_GATE, "72 / 125")
	hud.set_readout(SiegeHud.READOUT_DENARII, "57")
	var roster := {}
	for p in ctx.players:
		var rd := state.rider(p.peer_id)
		roster[p.peer_id] = {
			"raw_w": rd.raw_w,
			"cadence_rpm": rd.cadence_rpm,
			"ftp_pct": rd.raw_w / rd.ftp * 100.0,
			"rescue": rd.rescue,
			"afk": rd.afk,
			"connected": true,
			"status": {},
			"name": p.name,
			"slot_index": p.slot_index,
		}
	hud.set_roster(roster)
	var panic := ColorRect.new()
	panic.color = Color("#8a1f17")
	panic.position = Vector2(1508, 948)
	panic.size = Vector2(380, 100)
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	layer.add_child(panic)
	state.tick += 1
	view.refresh(0.05)
