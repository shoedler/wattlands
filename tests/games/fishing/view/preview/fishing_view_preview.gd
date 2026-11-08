extends Node
## Art review of the view and HUD from hand-made riders (no rules run), one scene per scenario:
## tools/screenshot --scene=res://tests/games/fishing/view/preview/fishing_view_<name>.tscn
## (dock: four boats at the harbour, one stopped at its menu; fast/sprint: surging mid-ocean,
## bow up; brake: just after a power cut, bow down; fight: a fight on the reef; reef: waiting by
## the great arch; wreck: a grouper fight by the old wreck, the line taut; kelp: a fish on a slack
## line on the shelf; shallows: waiting over seagrass and sand; abyss: by the basalt where the
## floor drops away; grouper: a fight in the deep; edge: stopped by the world's edge; workout:
## two boats on the endless workout map, one fighting; cruise: driving at FTP; hump: about 70 %
## FTP, the stern squatting; plane: on the plane; towed: a tuna towing the boat stern first; card:
## tools/picker_cards' picker card, a giant grouper close under the boat, the other boat away;
## jig: waiting with the lure part of the way home, two other riders fighting (crew strips);
## bluewater: the big game trip's biome, a grouper on the floor and a tuna under the other boat;
## bluewater_edge: stopped at the end of the big game map).
## `art` sets the art size (the flex PixelViewport's; capture at 3 screen px per art px with
## --size), `hr_bpm` a heart rate sensor (0: none), `nohud` the view alone. The local rider's
## telemetry comes from its state every frame (HudLayer.update and FishingGame.local_tm), as in a
## session.

const FX := preload("res://tests/games/fishing/view/fishing_view_fixtures.gd")
## Telemetry time runs this much faster than the preview, so the graphs fill in seconds.
const TIME_LAPSE := 12.0

@export var scenario: String = "dock"
@export var art: Vector2i = Vector2i(640, 360)
@export var hr_bpm: int = 0
## The picker card's render: the view alone, no HUD.
@export var nohud: bool = false

var game: FishingGame = null
var hud: HudLayer = null
var _t: float = 0.0


func _ready() -> void:
	var n := 4 if scenario == "dock" else (3 if scenario == "jig" else 2)
	var content_id := "roam_30"
	if scenario == "workout":
		content_id = "base_60"
	elif scenario.begins_with("bluewater"):
		content_id = "big_game_30"
	game = FX.make_game(n, 0, Wl.SOLO, content_id)
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
			me.power_w = 480.0
			FX.set_fight(other, 9120.0, 3, 25.0, 40.0)
		"cruise":
			FX.set_drive(me, 4300.0, 15.0)
			me.plane = 1.0
			me.planing = true
			me.heave_m = 0.06
			me.pitch_deg = 3.0
			me.wake = 0.8
			me.power_w = 205.0
			me.p_eff_w = 258.0
			me.cadence_ema = 88.0
			FX.set_drive(other, 4180.0, 14.0)
		"hump":
			FX.set_drive(me, 4300.0, 11.0)
			me.pitch_deg = 9.5
			me.heave_m = -0.06
			me.wake = 0.9
			me.power_w = 150.0
			FX.set_drive(other, 4180.0, 9.0)
		"plane":
			FX.set_drive(me, 4300.0, 13.5)
			me.pitch_deg = 3.6
			me.heave_m = 0.06
			me.plane = 1.0
			me.planing = true
			me.wake = 1.0
			me.power_w = 210.0
			FX.set_drive(other, 4180.0, 9.0)
		"towed":
			FX.set_fight(me, 5900.0, 4, 26.0, 40.0, 0.85, 0.0)
			me.tow_n = 420.0
			me.v_mps = -1.2
			me.heave_m = -0.07
			me.pitch_deg = 3.6
			FX.set_drive(other, 5800.0, 15.0)
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
		"card":
			FX.set_fight(me, 14150.0, 8, 26.0, 20.0, 0.3, 0.0)
			FX.set_drive(other, 13150.0, 15.0)
		"jig":
			FX.set_wait(me, 5930.0, 3, 22.0, 14.0)
			me.lure_dx = 22.0
			me.cadence_ema = 91.0
			me.pub_lo = 82
			me.pub_hi = 98
			me.power_w = 168.0
			FX.set_fight(other, 5800.0, 4, 41.0, 40.0, 0.2, 0.0)
			other.applied_target_w = 180.0
			other.power_w = 158.0
			other.reel = 0.45
			FX.set_fight(st.rider(2), 6100.0, 3, 36.0, 20.0, 0.2, 0.0)
			st.rider(2).applied_target_w = 202.0
			st.rider(2).power_w = 205.0
			st.rider(2).reel = 0.2
			me.points = 54
		"bluewater":
			FX.set_fight(me, 4100.0, 8, 30.0, 110.0, 0.4, 0.1)
			FX.set_fight(other, 4050.0, 4, 24.0, 36.0, 0.2, 0.0)
			other.applied_target_w = 188.0
			other.power_w = 176.0
			other.reel = 0.35
		"bluewater_edge":
			FX.set_menu(me, 8890.0, 3)
			FX.set_drive(other, 8700.0, 15.0)
		"edge":
			FX.set_menu(me, 17890.0, 3)
			FX.set_drive(other, 17700.0, 15.0)
	if me.in_fight():
		me.band_lo = 84.0
		me.band_hi = 100.0
		me.pub_lo = 84
		me.pub_hi = 100
		me.applied_target_w = 236.0
		me.power_w = 231.0
		me.reel = 0.4
	var pv := PixelViewport.new()
	pv.pixel_base = art
	pv.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(pv)
	pv.set_game_view(game.make_view() as Node2D)
	if nohud:
		return
	hud = HudLayer.new()
	add_child(hud)
	hud.build(game.hud_spec(), game.ctx, pv)


func _process(delta: float) -> void:
	_t += delta
	var r := game.state.rider(0)
	if scenario == "jig":
		r.lure_dx = maxf(22.0 - 14.0 * _t, 10.0)  # the lure comes home
	var tm := Telemetry.new()
	tm.t = 600.0 + _t * TIME_LAPSE
	game.state.t = tm.t
	# a little wobble round the state's numbers, so the graphs have a shape
	var u := _t * TIME_LAPSE
	var wob := (
		sin(u * 0.9) * 0.05 + sin(u * 0.23) * 0.06 + (0.03 if posmod(int(u), 7) == 0 else 0.0)
	)
	tm.power_w = maxf(r.power_w if r.power_w > 0.0 else r.p_eff_w, 0.0) * (1.0 + wob)
	tm.cadence_rpm = r.cadence_ema
	tm.ftp_pct = 100.0 * tm.power_w / r.ftp
	tm.applied_target_w = roundi(r.applied_target_w)
	tm.heart_rate_bpm = hr_bpm
	game.local_tm = tm
	if hud != null:
		hud.update(tm, null, null)
