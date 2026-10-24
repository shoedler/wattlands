extends Node
## Art review of the view and HUD from hand-made riders (no rules run), one scene per scenario:
## tools/screenshot --scene=res://tests/games/fishing/view/preview/fishing_view_<name>.tscn
## (dock: four boats at the harbour, one stopped at its menu; fast: driving hard mid-ocean;
## grouper: a fight in the deep; edge: stopped by the world's edge).

const FX := preload("res://tests/games/fishing/view/fishing_view_fixtures.gd")

@export var scenario: String = "dock"

var game: FishingGame = null


func _ready() -> void:
	var n := 4 if scenario == "dock" else 2
	game = FX.make_game(n, 0)
	add_child(game)
	var st := game.state
	st.t = 600.0
	var me := st.rider(0)
	var other := st.rider(1)
	match scenario:
		"dock":
			FX.set_menu(me, 120.0, 0)
			FX.set_drive(other, 150.0, 4.0)
			FX.set_wait(st.rider(2), 60.0, 1, 10.0, 4.0)
			FX.set_drive(st.rider(3), 40.0, 2.0)
			st.rider(3).paused = true
			me.points = 120
			other.points = 340
		"fast":
			FX.set_drive(me, 3000.0, 7.5)
			me.pitch_deg = 9.0
			me.wake = 1.0
			me.p_eff_w = 330.0
			FX.set_fight(other, 3080.0, 3, 25.0, 12.0)
		"grouper":
			FX.set_fight(me, 7100.0, 8, 30.0, 420.0, 0.55, 0.05)
			FX.set_wait(other, 6960.0, 6, 14.0, 120.0)
		"edge":
			FX.set_menu(me, 8930.0, 3)
			FX.set_drive(other, 8700.0, 5.0)
	var pv := PixelViewport.new()
	pv.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(pv)
	pv.set_game_view(game.make_view() as Node2D)
	var hud := HudLayer.new()
	add_child(hud)
	hud.build(game.hud_spec(), game.ctx, pv)
