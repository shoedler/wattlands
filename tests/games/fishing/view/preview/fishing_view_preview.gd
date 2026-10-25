extends Node
## Art review of the view and HUD from hand-made riders (no rules run), one scene per scenario:
## tools/screenshot --scene=res://tests/games/fishing/view/preview/fishing_view_<name>.tscn
## (dock: four boats at the harbour, one stopped at its menu; fast/sprint: surging mid-ocean,
## bow up; brake: just after a power cut, bow down; fight: a fight on the reef; reef: waiting by
## the great arch; wreck: a grouper fight by the old wreck, the line taut; kelp: a fish on a slack
## line on the shelf; shallows: waiting over seagrass and sand; abyss: by the basalt where the
## floor drops away; grouper: a fight in the deep; edge: stopped by the world's edge; workout:
## two boats on the endless workout map, one fighting).

const FX := preload("res://tests/games/fishing/view/fishing_view_fixtures.gd")

@export var scenario: String = "dock"

var game: FishingGame = null


func _ready() -> void:
	var n := 4 if scenario == "dock" else 2
	game = FX.make_game(n, 0, Wl.SOLO, "base_60" if scenario == "workout" else "roam_30")
	add_child(game)
	var st := game.state
	st.t = 600.0
	var me := st.rider(0)
	var other := st.rider(1)
	match scenario:
		"dock":
			FX.set_menu(me, 130.0, 0)
			FX.set_drive(other, 190.0, 4.0)
			FX.set_wait(st.rider(2), 70.0, 1, 10.0, 4.0)
			FX.set_drive(st.rider(3), 250.0, 2.0)
			st.rider(3).paused = true
			me.points = 120
			other.points = 340
		"fast", "sprint":
			FX.set_drive(me, 9000.0, 24.0)
			me.pitch_deg = 14.0
			me.wake = 1.0
			me.p_eff_w = 600.0
			FX.set_fight(other, 9120.0, 3, 25.0, 40.0)
		"brake":
			FX.set_drive(me, 9000.0, 14.0)
			me.pitch_deg = -6.0
			me.brake = 0.8
			me.wake = 0.7
			me.p_eff_w = 40.0
			FX.set_drive(other, 8900.0, 15.0)
		"fight":
			FX.set_fight(me, 5900.0, 3, 28.0, 22.0, 0.5, 0.05)
			FX.set_drive(other, 5800.0, 15.0)
		"reef":
			FX.set_wait(me, 5930.0, 4, 30.0, 18.0)
			FX.set_drive(other, 6060.0, 15.0)
		"wreck":
			FX.set_fight(me, 14150.0, 8, 34.0, 380.0, 0.85, 0.0)
			FX.set_wait(other, 14000.0, 6, 14.0, 120.0)
		"kelp":
			FX.set_fight(me, 10300.0, 5, -30.0, 70.0, 0.0, 0.9)
			FX.set_drive(other, 10180.0, 15.0)
		"shallows":
			FX.set_wait(me, 2400.0, 1, -24.0, 5.0)
			FX.set_drive(other, 2300.0, 15.0)
		"abyss":
			FX.set_drive(me, 16700.0, 8.0)
			FX.set_drive(other, 16500.0, 15.0)
		"workout":
			FX.set_fight(me, 1200.0, 0, 22.0, 6.0, 0.35, 0.1)
			FX.set_drive(other, 1140.0, 15.0)
		"grouper":
			FX.set_fight(me, 14250.0, 8, 30.0, 420.0, 0.55, 0.05)
			FX.set_wait(other, 14100.0, 6, 14.0, 120.0)
		"edge":
			FX.set_menu(me, 17890.0, 3)
			FX.set_drive(other, 17700.0, 15.0)
	var pv := PixelViewport.new()
	pv.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(pv)
	pv.set_game_view(game.make_view() as Node2D)
	var hud := HudLayer.new()
	add_child(hud)
	hud.build(game.hud_spec(), game.ctx, pv)
