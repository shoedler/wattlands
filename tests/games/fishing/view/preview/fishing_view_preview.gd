extends Node
## A still life of the Fishing view and HUD for art review (tools/screenshot
## --scene=res://tests/games/fishing/view/preview/fishing_view_preview.tscn): four lanes in a
## reel, a marlin fight, a pick and a Landing, from hand-made state (no rules run).

const FX := preload("res://tests/games/fishing/view/fishing_view_fixtures.gd")

var game: FishingGame = null


func _ready() -> void:
	game = FX.make_game(4, 0)
	add_child(game)
	var st := game.state
	st.t = 200.0
	FX.set_reel(st.lane(0), 55.0)
	FX.set_fight(st.lane(1), 3, 120.0, 0.6, 0.55, 0.1)
	st.lane(1).cosmetics.assign([1, 1, 1, 1])
	FX.set_pick(st.lane(2), 1)
	FX.set_landing(st.lane(3), 6.0, 0.7)
	st.hookup_level = 2
	st.team_points = 345
	st.team_fish = 4
	st.catches.assign([0, 0, 0, 1, 1, 1, 2, 2, 0, 3, 0, 0])
	var pv := PixelViewport.new()
	pv.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(pv)
	pv.set_game_view(game.make_view() as Node2D)
	var hud := HudLayer.new()
	add_child(hud)
	hud.build(game.hud_spec(), game.ctx, pv)
