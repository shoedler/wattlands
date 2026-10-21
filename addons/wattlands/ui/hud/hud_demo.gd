extends Node
## HUD kit demo (BRIEF 3.9, 7.8): every kit widget, a game Control holding a PedalScanList,
## toasts and a banner, fed with animated mock data on a private EventBus. Open
## addons/wattlands/ui/hud/hud_demo.tscn to look at the HUD; tools/screenshot can capture it.
## With `-- --capture=<png path>` (a windowed run) it saves one frame after `--capture-at`
## seconds (default 1.5) and quits. Mock data only: nothing touches a trainer.

const LOCAL := 1

var _bus: WlEventBus = null
var _hud: HudLayer = null
var _plan: EffortPlan = null
var _t: float = 0.0
var _capture_path: String = ""
var _capture_at: float = 1.5
var _captured: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capture_path = CmdLine.get_str("capture", "")
	_capture_at = CmdLine.get_float("capture-at", 1.5)
	var bg := ColorRect.new()
	bg.color = Color("#2E4A3A")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_bus = WlEventBus.new()
	add_child(_bus)
	var ctx := GameContext.new()
	ctx.events = _bus
	ctx.local_peer = LOCAL
	ctx.strings = GameStrings.new()
	var me := PlayerSlot.new()
	me.peer_id = LOCAL
	me.name = "Ada"
	me.ftp = 250.0
	me.apply_look(0)
	ctx.players = [me]
	_plan = EffortPlan.of([
		PlanPhase.erg(Wl.WARMUP, 50, 300, "Ride out").with_ramp(65),
		PlanPhase.erg(Wl.WORK, 90, 240, "Wave 1"),
		PlanPhase.erg(Wl.RECOVERY, 55, 180, "Break"),
		PlanPhase.sim(Wl.WORK, Wl.GRADE_GAME, 120, "Overdrive"),
		PlanPhase.erg(Wl.WORK, 60, 0, "Reel 1").with_open(120, 540),
		PlanPhase.erg(Wl.COOLDOWN, 50, 180, "Cool-down"),
	])
	var shop := PanelContainer.new()
	shop.name = "ShopPanel"
	var list := PedalScanList.new()
	list.custom_minimum_size = Vector2(420, 0)
	list.erg_auto_confirm = true
	list.set_items([
		{"id": "ballista", "text": "Ballista", "detail": "40 denarii"},
		{"id": "wall", "text": "Shield wall", "detail": "25 denarii"},
		{"id": "save", "text": "Save denarii"},
		{"id": "oil", "text": "Hot oil", "detail": "Needs 60", "disabled": true},
	])
	shop.add_child(list)
	var spec := HudSpec.new() \
		.add(HudSpec.TIMELINE, HudSpec.TOP_LEFT) \
		.add(HudSpec.READOUT, HudSpec.TOP_RIGHT, {"source": "custom", "id": "gate", "label": "Gate HP"}) \
		.add(HudSpec.READOUT, HudSpec.TOP_RIGHT, {"source": "wkg"}) \
		.add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT) \
		.add(HudSpec.CADENCE, HudSpec.BOTTOM_LEFT) \
		.add(HudSpec.WBAL, HudSpec.BOTTOM_LEFT) \
		.add(HudSpec.TEAMMATES, HudSpec.BOTTOM) \
		.add(HudSpec.GEAR, HudSpec.BOTTOM_RIGHT) \
		.add_control(shop, HudSpec.BOTTOM_RIGHT) \
		.toasts_at(HudSpec.TOP).banners_at(HudSpec.TOP)
	_hud = HudLayer.new()
	_hud.sounds = false
	_hud.wkg_weight_kg = 75.0
	add_child(_hud)
	_hud.build(spec, ctx)
	_bus.roster_changed.emit({
		LOCAL: {"name": "Ada", "slot_index": 0, "raw_w": 262.0, "ftp_pct": 105.0, "status": {"in_band": true, "text": ""}},
		2: {"name": "Bo", "slot_index": 1, "raw_w": 198.0, "ftp_pct": 88.0, "status": {"in_band": false, "text": "Diesel"}},
		3: {"name": "Cy", "slot_index": 2, "raw_w": 120.0, "ftp_pct": 60.0, "rescue": true},
		-1: {"name": "Bot 1", "slot_index": 3, "raw_w": 230.0, "ftp_pct": 92.0, "status": {"in_band": true}},
		4: {"name": "Dee", "slot_index": 4, "raw_w": 0.0, "ftp_pct": 0.0, "afk": true, "connected": false},
	})
	_bus.power_band_changed.emit(LOCAL, 0.76 * 250.0, 1.05 * 250.0)
	_bus.cadence_band_changed.emit(LOCAL, 85.0, 100.0)
	_bus.readout_changed.emit("gate", "1250")
	_bus.toast_requested.emit("Ram at the north gate", [])
	_bus.banner_requested.emit("Wave {0}", [2], 3.0)
	_hud.set_safety_state(true, false, false)


func _process(delta: float) -> void:
	_t += delta
	var t := Telemetry.new()
	t.peer_id = LOCAL
	t.mode = Wl.SIM
	t.power_w = 230.0 + 30.0 * sin(_t * 1.3)
	t.ftp_pct = t.power_w / 2.5
	t.cadence_rpm = 92.0 + 6.0 * sin(_t * 0.7)
	t.wbal_j = 20000.0 * (0.62 + 0.1 * sin(_t * 0.3))
	t.gear = 14
	var ph := PhaseState.new()
	var p := _plan.phase(3)
	ph.index = 3
	ph.kind = p.kind
	ph.mode = p.mode
	ph.label = p.label
	ph.duration_s = p.duration_s
	ph.elapsed_s = 37.0 + _t
	ph.remaining_s = maxf(0.0, p.duration_s - ph.elapsed_s)
	ph.count = _plan.size()
	_hud.update(t, ph, _plan)
	if not _capture_path.is_empty() and not _captured and _t >= _capture_at:
		_captured = true
		_capture.call_deferred()


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _capture_path
	if path.is_relative_path():
		path = ProjectSettings.globalize_path("res://").path_join(path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := img.save_png(path)
	print("hud_demo: saved %s (%dx%d, error %d)" % [path, img.get_width(), img.get_height(), err])
	get_tree().quit(0 if err == OK else 1)
