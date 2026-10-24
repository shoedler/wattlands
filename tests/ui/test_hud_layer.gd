extends GutTest
## HudLayer (BRIEF 3.6, 3.9; docs/OWNERSHIP.md HUD1-HUD12, GM15, PL11): anchors and stacking,
## Rect2i art-pixel placement through a (fake) PixelViewport at scales 2 and 3 with a
## letterbox and on resize, the game's own Controls, the toast and banner areas, everything
## the session bus drives (bands, roster, toasts, banners, readouts, rescue, pause, warm-up),
## the local feed, per-tick update(), and raw W / %FTP always visible.

const FakePV := preload("res://tests/ui/fake_pixel_viewport.gd")
const LOCAL := 1

var _bus: WlEventBus = null
var _ctx: GameContext = null
var _hud: HudLayer = null
## The real TrainerService autoload and its stand-in while a test swaps them
## (_swap_trainer_service); after_each puts the real one back.
var _real_ts: Node = null
var _stand_in: Node = null


## A TrainerService autoload stand-in with only status(), all HudLayer reads of it.
class FakeTrainerService:
	extends Node
	var st: String = TrainerDevice.STATUS_DISCONNECTED

	func status() -> String:
		return st


func before_each() -> void:
	_bus = autofree(WlEventBus.new())
	_ctx = GameContext.new()
	_ctx.events = _bus
	_ctx.local_peer = LOCAL
	_ctx.strings = GameStrings.new()
	var me := PlayerSlot.new()
	me.peer_id = LOCAL
	me.ftp = 250.0
	me.apply_look(0)
	_ctx.players = [me]
	_hud = HudLayer.new()
	_hud.screen_size_override = Vector2(1920, 1080)
	_hud.sounds = false
	_hud.wkg_weight_kg = 0.0
	add_child_autofree(_hud)
	_hud.set_process(false)


func after_each() -> void:
	_restore_trainer_service()


func _spec() -> HudSpec:
	return (
		HudSpec
		. new()
		. add(HudSpec.TIMELINE, HudSpec.TOP_LEFT)
		. add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT)
		. add(HudSpec.CADENCE, HudSpec.BOTTOM_LEFT)
		. add(HudSpec.WBAL, HudSpec.BOTTOM_LEFT)
		. add(HudSpec.READOUT, HudSpec.TOP_RIGHT, {"source": "custom", "id": "gate_hp"})
		. add(HudSpec.TEAMMATES, HudSpec.BOTTOM)
		. add(HudSpec.GEAR, HudSpec.BOTTOM_RIGHT)
	)


func _tele(mode: String, power: float, target: int = 0) -> Telemetry:
	var t := Telemetry.new()
	t.peer_id = LOCAL
	t.mode = mode
	t.power_w = power
	t.applied_target_w = target
	t.ftp_pct = power / 2.5
	t.cadence_rpm = 90.0
	t.wbal_j = 10000.0
	return t


# --- basics -----------------------------------------------------------------------------------


func test_layer_and_process_mode() -> void:
	assert_eq(_hud.layer, HudLayer.LAYER)
	assert_eq(HudLayer.LAYER, 10)
	assert_eq(_hud.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_same(_hud.root().theme, WlTheme.get_theme(), "the shared Theme")


func test_build_places_each_widget_at_its_anchor() -> void:
	_hud.build(_spec(), _ctx)
	assert_eq(_hud.anchor_of(_hud.widget(HudSpec.TIMELINE)), HudSpec.TOP_LEFT)
	assert_eq(_hud.anchor_of(_hud.widget(HudSpec.POWER_GAUGE)), HudSpec.BOTTOM_LEFT)
	assert_eq(_hud.anchor_of(_hud.widget(HudSpec.CADENCE)), HudSpec.BOTTOM_LEFT)
	assert_eq(_hud.anchor_of(_hud.widget(HudSpec.READOUT)), HudSpec.TOP_RIGHT)
	assert_eq(_hud.anchor_of(_hud.widget(HudSpec.TEAMMATES)), HudSpec.BOTTOM)
	assert_eq(_hud.anchor_of(_hud.widget(HudSpec.GEAR)), HudSpec.BOTTOM_RIGHT)
	assert_eq(
		_hud.widgets_of(HudSpec.POWER_GAUGE).size(), 1, "no extra gauge when the spec has one"
	)


func test_bottom_anchors_stack_upward_top_anchors_downward() -> void:
	var spec := (
		HudSpec
		. new()
		. add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT)
		. add(HudSpec.CADENCE, HudSpec.BOTTOM_LEFT)
		. add(HudSpec.TIMELINE, HudSpec.TOP_LEFT)
		. add(HudSpec.WBAL, HudSpec.TOP_LEFT)
	)
	_hud.build(spec, _ctx)
	var bl := _hud.anchor_box(HudSpec.BOTTOM_LEFT)
	var gauge := _hud.widget(HudSpec.POWER_GAUGE)
	var cad := _hud.widget(HudSpec.CADENCE)
	assert_gt(
		gauge.get_index(), cad.get_index(), "the first bottom entry sits nearest the bottom edge"
	)
	var tl := _hud.anchor_box(HudSpec.TOP_LEFT)
	assert_lt(
		_hud.widget(HudSpec.TIMELINE).get_index(),
		_hud.widget(HudSpec.WBAL).get_index(),
		"top entries stack downward"
	)
	assert_not_null(bl)
	assert_not_null(tl)


func test_anchor_boxes_sit_at_the_screen_edges() -> void:
	_hud.build(_spec(), _ctx)
	var m := float(WlTheme.MARGIN_PX)
	var tl := _hud.anchor_box(HudSpec.TOP_LEFT)
	assert_eq(tl.position, Vector2(m, m))
	var tr_box := _hud.anchor_box(HudSpec.TOP_RIGHT)
	assert_almost_eq(tr_box.position.x + tr_box.size.x, 1920.0 - m, 0.01)
	assert_eq(tr_box.position.y, m)
	var bl := _hud.anchor_box(HudSpec.BOTTOM_LEFT)
	assert_eq(bl.position.x, m)
	assert_almost_eq(bl.position.y + bl.size.y, 1080.0 - m, 0.01)
	var br := _hud.anchor_box(HudSpec.BOTTOM_RIGHT)
	assert_almost_eq(br.position.x + br.size.x, 1920.0 - m, 0.01)
	var b := _hud.anchor_box(HudSpec.BOTTOM)
	assert_almost_eq(b.position.x + b.size.x * 0.5, 960.0, 1.0, "bottom is centered")
	assert_gt(bl.size.y, 300.0, "three stacked widgets")


func test_anchor_position_math() -> void:
	var ss := Vector2(1920, 1080)
	var sz := Vector2(100, 50)
	assert_eq(HudLayer.anchor_position(HudSpec.TOP, sz, ss), Vector2(910, 32))
	assert_eq(HudLayer.anchor_position(HudSpec.BOTTOM, sz, ss), Vector2(910, 998))
	assert_eq(HudLayer.anchor_position(HudSpec.BOTTOM_RIGHT, sz, ss), Vector2(1788, 998))


func test_relayout_on_screen_size_change() -> void:
	_hud.build(_spec(), _ctx)
	_hud.screen_size_override = Vector2(2560, 1080)
	_hud.relayout()
	var tr_box := _hud.anchor_box(HudSpec.TOP_RIGHT)
	assert_almost_eq(tr_box.position.x + tr_box.size.x, 2560.0 - WlTheme.MARGIN_PX, 0.01)


func test_invalid_positions_and_unknown_widgets_are_rejected() -> void:
	var spec := HudSpec.new().add(HudSpec.POWER_GAUGE, "middle").add("radar", HudSpec.TOP).add(
		HudSpec.CADENCE, HudSpec.TOP
	)
	_hud.build(spec, _ctx)
	assert_push_error("invalid position")
	assert_push_error("unknown kit widget")
	assert_not_null(_hud.widget(HudSpec.CADENCE))


func test_power_is_always_visible() -> void:
	_hud.build(HudSpec.new().add(HudSpec.TIMELINE, HudSpec.TOP), _ctx)
	var g := _hud.widget(HudSpec.POWER_GAUGE)
	assert_not_null(g, "a gauge is added when the game shows no raw W and %FTP")
	assert_eq(_hud.anchor_of(g), HudSpec.BOTTOM_LEFT)
	_hud.build(
		HudSpec.new().add(HudSpec.READOUT, HudSpec.TOP_RIGHT, {"source": "power_w"}).add(
			HudSpec.READOUT, HudSpec.TOP_RIGHT, {"source": "ftp_pct"}
		),
		_ctx
	)
	assert_null(_hud.widget(HudSpec.POWER_GAUGE), "power_w and ftp_pct readouts are enough")
	_hud.ensure_power_visible = false
	_hud.build(HudSpec.new(), _ctx)
	assert_null(_hud.widget(HudSpec.POWER_GAUGE))


func test_rebuild_replaces_widgets_and_frees_unused_controls() -> void:
	var card := Label.new()
	_hud.build(_spec().add_control(card, HudSpec.TOP), _ctx)
	var old_gauge := _hud.widget(HudSpec.POWER_GAUGE)
	_hud.build(HudSpec.new().add(HudSpec.POWER_GAUGE, HudSpec.TOP), _ctx)
	assert_false(is_instance_valid(old_gauge), "old widgets freed")
	assert_false(is_instance_valid(card), "a control the new spec doesn't use is freed")
	assert_eq(_hud.widgets_of(HudSpec.POWER_GAUGE).size(), 1)


# --- game controls, toasts and banner areas ---------------------------------------------------


func test_game_controls_at_anchors_after_kit_widgets() -> void:
	var card := PanelContainer.new()
	card.name = "RoutingCard"
	var spec := HudSpec.new().add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_RIGHT).add_control(
		card, HudSpec.BOTTOM_RIGHT
	)
	_hud.build(spec, _ctx)
	assert_eq(_hud.anchor_of(card), HudSpec.BOTTOM_RIGHT)
	assert_lt(
		card.get_index(),
		_hud.widget(HudSpec.POWER_GAUGE).get_index(),
		"stacks above the gauge (bottom anchors go up)"
	)


func test_toast_and_banner_areas_at_anchors() -> void:
	var spec := (
		HudSpec
		. new()
		. add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT)
		. toasts_at(HudSpec.BOTTOM)
		. banners_at(HudSpec.TOP)
	)
	_hud.build(spec, _ctx)
	assert_eq(_hud.anchor_of(_hud.toasts()), HudSpec.BOTTOM)
	assert_eq(_hud.anchor_of(_hud.banner()), HudSpec.TOP)


# --- Rect2i placement --------------------------------------------------------------------------


func _fishing_spec(card: Control) -> HudSpec:
	return (
		HudSpec
		. new()
		. add(HudSpec.POWER_GAUGE, Rect2i(427, 0, 213, 42))
		. add(HudSpec.CADENCE, Rect2i(427, 42, 213, 42))
		. add_control(card, Rect2i(0, 10, 100, 20))
		. toasts_at(Rect2i(0, 40, 640, 30))
		. banners_at(Rect2i(0, 90, 427, 60))
	)


func test_rect_positions_map_through_the_pixel_viewport_at_scale_2() -> void:
	var pv: FakePV = add_child_autofree(FakePV.new())
	pv.fake_scale = 2
	pv.fake_offset = Vector2(0, 30)
	var card := Control.new()
	_hud.build(_fishing_spec(card), _ctx, pv)
	var gauge := _hud.widget(HudSpec.POWER_GAUGE)
	assert_eq(_hud.rect_of(gauge), Rect2i(427, 0, 213, 42))
	assert_eq(_hud.slot_screen_rect(gauge), Rect2(854, 30, 426, 84))
	assert_eq(_hud.slot_screen_rect(_hud.widget(HudSpec.CADENCE)), Rect2(854, 114, 426, 84))
	assert_eq(_hud.slot_screen_rect(card), Rect2(0, 50, 200, 40))
	assert_eq(_hud.slot_screen_rect(_hud.toasts()), Rect2(0, 110, 1280, 60))
	assert_eq(_hud.slot_screen_rect(_hud.banner()), Rect2(0, 210, 854, 120))
	assert_eq(_hud.anchor_of(gauge), "", "not at an anchor")
	assert_lt(gauge.ui_scale, 1.0, "shrunk to its rect")


func test_rect_positions_at_scale_3_and_on_resize() -> void:
	var pv: FakePV = add_child_autofree(FakePV.new())
	pv.fake_scale = 3
	pv.fake_offset = Vector2.ZERO
	var card := Control.new()
	_hud.build(_fishing_spec(card), _ctx, pv)
	var gauge := _hud.widget(HudSpec.POWER_GAUGE)
	assert_eq(_hud.slot_screen_rect(gauge), Rect2(1281, 0, 639, 126))
	pv.set_fake(2, Vector2(320, 180))
	await wait_process_frames(2)
	assert_eq(_hud.slot_screen_rect(gauge), Rect2(1174, 180, 426, 84), "re-laid out on resize")
	assert_eq(_hud.slot_screen_rect(card), Rect2(320, 200, 200, 40))


## Tank's teammate strip (art 268, 2, 140 x 22 at scale 3 = 420 x 66) stays one row inside
## its slot; a slot too small keeps the minimum scale and wraps.
func test_rect_teammates_strip_stays_one_row_inside_its_slot() -> void:
	var pv: FakePV = add_child_autofree(FakePV.new())
	pv.fake_scale = 3
	pv.fake_offset = Vector2.ZERO
	var rect := Rect2i(268, 2, 140, 22)
	_hud.build(HudSpec.new().add(HudSpec.TEAMMATES, rect), _ctx, pv)
	var roster := {}
	for i in 3:
		roster[i + 1] = {"name": "R%d" % i, "slot_index": i}
	_bus.roster_changed.emit(roster)
	_hud.relayout()
	await wait_process_frames(3)
	var tm := _hud.widget(HudSpec.TEAMMATES) as HudTeammates
	var slot := _hud.slot_screen_rect(tm)
	assert_eq(slot.size, Vector2(420, 66))
	assert_eq(tm.columns(), 3, "one row")
	assert_gte(tm.ui_scale, HudTeammates.MIN_SCALE)
	assert_lte(tm.custom_minimum_size.x, slot.size.x + 0.5)
	assert_lte(tm.custom_minimum_size.y, slot.size.y + 0.5, "does not grow below the slot")
	for i in 4:
		roster[i + 1] = {"name": "R%d" % i, "slot_index": i}
	_bus.roster_changed.emit(roster)
	_hud.relayout()
	await wait_process_frames(3)
	assert_eq(tm.columns(), 2, "too small for one row at the minimum scale: wraps")
	assert_eq(tm.ui_scale, HudTeammates.MIN_SCALE)


## The app shell keeps its on-screen panic button clear of the HUD: a reserved corner moves
## that corner's stack inward and narrows the centre stack of that edge.
func test_reserve_corner_keeps_the_corner_clear() -> void:
	var spec := HudSpec.new().add(HudSpec.READOUT, HudSpec.BOTTOM_RIGHT, {"source": "power_w"}).add(
		HudSpec.READOUT, HudSpec.TOP_LEFT, {"source": "cadence_rpm"}
	)
	_hud.build(spec, _ctx)
	_hud.relayout()
	var br := _hud.anchor_box(HudSpec.BOTTOM_RIGHT)
	var tl := _hud.anchor_box(HudSpec.TOP_LEFT)
	var before := br.position
	var tl_before := tl.position
	var wide := _hud.center_width(HudSpec.BOTTOM, Vector2(1920, 1080))
	_hud.reserve_corner(HudSpec.BOTTOM_RIGHT, Vector2(380, 100))
	_hud.reserve_corner(HudSpec.TOP_LEFT, Vector2(200, 50))
	_hud.relayout()
	assert_eq(_hud.reserved_corner(HudSpec.BOTTOM_RIGHT), Vector2(380, 100))
	assert_eq(
		br.position,
		before - Vector2(0, 100 + WlTheme.GAP_PX),
		"the bottom-right stack sits above it"
	)
	assert_eq(tl.position, tl_before + Vector2(0, 50 + WlTheme.GAP_PX), "a top corner moves down")
	assert_true(
		br.get_global_rect().end.y <= 1080 - WlTheme.MARGIN_PX - 100,
		"nothing under the reserved area"
	)
	assert_true(
		_hud.center_width(HudSpec.BOTTOM, Vector2(1920, 1080)) <= wide,
		"the bottom centre keeps clear"
	)
	_hud.reserve_corner(HudSpec.BOTTOM_RIGHT, Vector2.ZERO)
	_hud.relayout()
	assert_eq(br.position, before, "released")
	_hud.reserve_corner(HudSpec.BOTTOM, Vector2(10, 10))
	assert_push_error("corner anchor")


## The real world-kits PixelViewport (not the double): rects map through its
## art_rect_to_screen(), and a pixel_base change, which moves the scale without a resize,
## re-lays the HUD out through `layout_changed`.
func test_rect_positions_follow_the_real_pixel_viewport() -> void:
	var holder := Control.new()
	holder.size = Vector2(1920, 1080)
	add_child_autofree(holder)
	var pv := PixelViewport.new()
	pv.pixel_base = Vector2i(640, 360)
	holder.add_child(pv)
	pv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pv.refresh_layout()
	assert_eq(pv.size, Vector2(1920, 1080))
	assert_eq(pv.integer_scale(), 3)
	_hud.build(_fishing_spec(Control.new()), _ctx, pv)
	assert_true(
		pv.layout_changed.is_connected(_hud._queue_relayout), "HudLayer follows layout_changed"
	)
	var gauge := _hud.widget(HudSpec.POWER_GAUGE)
	assert_eq(_hud.slot_screen_rect(gauge), pv.art_rect_to_screen(Rect2i(427, 0, 213, 42)))
	assert_eq(_hud.slot_screen_rect(gauge), Rect2(1281, 0, 639, 126))
	pv.pixel_base = Vector2i(480, 270)
	assert_eq(pv.integer_scale(), 4)
	await wait_process_frames(2)
	assert_eq(
		_hud.slot_screen_rect(gauge),
		pv.art_rect_to_screen(Rect2i(427, 0, 213, 42)),
		"re-laid out on the real layout_changed"
	)
	assert_eq(_hud.slot_screen_rect(gauge), Rect2(1708, 0, 852, 168))


## world-kits' PixelViewport re-lays out on a stretch-factor change without resizing and
## emits only `layout_changed`; the HUD follows it, and a rebuild with another PixelViewport
## stops following the old one.
func test_rect_positions_follow_layout_changed() -> void:
	var pv: FakePV = add_child_autofree(FakePV.new())
	pv.fake_scale = 3
	var card := Control.new()
	_hud.build(_fishing_spec(card), _ctx, pv)
	var gauge := _hud.widget(HudSpec.POWER_GAUGE)
	assert_eq(_hud.slot_screen_rect(gauge), Rect2(1281, 0, 639, 126))
	pv.set_fake_layout(2, Vector2(0, 90))
	await wait_process_frames(2)
	assert_eq(
		_hud.slot_screen_rect(gauge), Rect2(854, 90, 426, 84), "re-laid out on layout_changed"
	)
	var pv2: FakePV = add_child_autofree(FakePV.new())
	pv2.fake_scale = 1
	_hud.build(_fishing_spec(Control.new()), _ctx, pv2)
	assert_false(
		pv.is_connected("layout_changed", _hud._queue_relayout), "the old PixelViewport is let go"
	)
	assert_false(pv.resized.is_connected(_hud._queue_relayout))
	assert_true(pv2.is_connected("layout_changed", _hud._queue_relayout))
	assert_eq(_hud.slot_screen_rect(_hud.widget(HudSpec.POWER_GAUGE)), Rect2(427, 0, 213, 42))


func test_widgets_sharing_a_rect_stack_and_share_it() -> void:
	var pv: FakePV = add_child_autofree(FakePV.new())
	pv.fake_scale = 3
	var rect := Rect2i(0, 0, 160, 90)
	var spec := HudSpec.new().add(HudSpec.POWER_GAUGE, rect).add(HudSpec.WBAL, rect)
	_hud.build(spec, _ctx, pv)
	var g := _hud.widget(HudSpec.POWER_GAUGE)
	var w := _hud.widget(HudSpec.WBAL)
	assert_eq(_hud.rect_of(g), rect)
	assert_eq(_hud.rect_of(w), rect)
	assert_lt(g.get_index(), w.get_index(), "stacked in the order added")
	await wait_process_frames(2)
	var total := g.get_combined_minimum_size().y + w.get_combined_minimum_size().y + 4.0
	assert_lte(total, 270.0, "they share the 480 x 270 px rect")


## Fishing's local-lane HUD zone at 4 lanes (x 427-639, 84 art px tall; 639 x 252 px at
## scale 3), split the way docs/GAME_SDK.md recommends: timeline on top, power gauge and
## cadence side by side, W' and gear below. Every widget fits its rect and W and rpm stay
## >= 48 px (F3.5).
func test_fishing_zone_layout_fits_with_48_px_numbers() -> void:
	var pv: FakePV = add_child_autofree(FakePV.new())
	pv.fake_scale = 3
	var rects := {
		HudSpec.TIMELINE: Rect2i(427, 0, 213, 34),
		HudSpec.POWER_GAUGE: Rect2i(427, 34, 107, 36),
		HudSpec.CADENCE: Rect2i(534, 34, 106, 36),
		HudSpec.WBAL: Rect2i(427, 70, 133, 14),
		HudSpec.GEAR: Rect2i(560, 70, 80, 14),
	}
	var spec := HudSpec.new()
	for id: String in rects.keys():
		spec.add(id, rects[id])
	_hud.build(spec, _ctx, pv)
	var t := _tele(Wl.SIM, 1000.0)
	t.ftp_pct = 150.0
	t.cadence_rpm = 120.0
	_hud.update(t, null, null)
	_hud.apply_cadence_band(LOCAL, 100.0, 120.0)
	_hud.relayout()
	await wait_process_frames(2)
	assert_true(_hud.widget(HudSpec.GEAR).visible, "Landing is SIM: the gear shows")
	for id: String in rects.keys():
		var wd := _hud.widget(id)
		var screen := _hud.slot_screen_rect(wd)
		var got := wd.get_combined_minimum_size()
		assert_true(
			got.x <= screen.size.x + 1.0 and got.y <= screen.size.y + 1.0,
			"%s %s fits %s" % [id, got, screen.size]
		)
	assert_gte(
		HudWidget.font_px((_hud.widget(HudSpec.POWER_GAUGE) as HudPowerGauge).watts_label()),
		48,
		"W >= 48 px"
	)
	assert_gte(
		HudWidget.font_px((_hud.widget(HudSpec.CADENCE) as HudCadence).rpm_label()),
		48,
		"rpm >= 48 px"
	)


func test_rect_without_pixel_viewport_is_1080p_pixels() -> void:
	_hud.build(HudSpec.new().add(HudSpec.POWER_GAUGE, Rect2i(100, 100, 420, 150)), _ctx)
	assert_push_warning("without a PixelViewport")
	assert_eq(_hud.slot_screen_rect(_hud.widget(HudSpec.POWER_GAUGE)), Rect2(100, 100, 420, 150))


# --- the session bus ----------------------------------------------------------------------------


func test_bus_power_band_reaches_the_local_gauge_only() -> void:
	_hud.build(_spec(), _ctx)
	var g := _hud.widget(HudSpec.POWER_GAUGE) as HudPowerGauge
	_bus.power_band_changed.emit(7, 100.0, 200.0)
	_hud.update(_tele(Wl.SIM, 150.0), null, null)
	assert_eq(g.band(), Vector2.ZERO, "another peer's band")
	_bus.power_band_changed.emit(LOCAL, 190.0, 262.0)
	assert_eq(g.band(), Vector2(190, 262))
	_hud.update(_tele(Wl.SIM, 200.0), null, null)
	assert_true(g.in_band())
	_bus.power_band_changed.emit(LOCAL, 0.0, 0.0)
	assert_eq(g.band(), Vector2.ZERO, "cleared")


func test_gauge_peer_option() -> void:
	_hud.build(HudSpec.new().add(HudSpec.POWER_GAUGE, HudSpec.TOP, {"peer": 4}), _ctx)
	var g := _hud.widget(HudSpec.POWER_GAUGE) as HudPowerGauge
	assert_eq(g.peer, 4)
	_bus.power_band_changed.emit(4, 100.0, 120.0)
	g.set_telemetry(_tele(Wl.SIM, 110.0))
	assert_true(g.in_band())


func test_bus_cadence_band() -> void:
	_hud.build(_spec(), _ctx)
	var c := _hud.widget(HudSpec.CADENCE) as HudCadence
	_bus.cadence_band_changed.emit(LOCAL, 80.0, 95.0)
	assert_eq(c.band(), Vector2(80, 95))
	_hud.update(_tele(Wl.ERG, 200.0, 200), null, null)
	assert_true(c.in_band())
	_bus.cadence_band_changed.emit(2, 50.0, 60.0)
	assert_eq(c.band(), Vector2(80, 95), "another peer's band")
	_bus.cadence_band_changed.emit(LOCAL, 0.0, 0.0)
	assert_eq(c.band(), Vector2.ZERO)


func test_bus_roster_fills_the_teammate_strip() -> void:
	_hud.build(_spec(), _ctx)
	var tm := _hud.widget(HudSpec.TEAMMATES) as HudTeammates
	(
		_bus
		. roster_changed
		. emit(
			{
				LOCAL: {"name": "Ada", "slot_index": 0, "raw_w": 200.0, "ftp_pct": 80.0},
				2: {"name": "Bo", "slot_index": 4, "raw_w": 150.0, "ftp_pct": 60.0, "afk": true},
			}
		)
	)
	assert_eq(tm.peers(), [LOCAL, 2])
	assert_true(tm.card(2).chip().hollow, "slot 4: hollow circle")
	assert_eq(tm.card(2).chip().shape, "circle")
	assert_eq(tm.card(2).status_text(), tr("UI_HUD_AFK"))


func test_ctx_roster_at_build() -> void:
	_ctx.roster = {LOCAL: {"name": "Ada", "slot_index": 0}, 3: {"name": "Cy", "slot_index": 2}}
	_hud.build(_spec(), _ctx)
	assert_eq((_hud.widget(HudSpec.TEAMMATES) as HudTeammates).peers(), [LOCAL, 3])


func test_bus_toasts_and_banners() -> void:
	_hud.build(_spec(), _ctx)
	_bus.toast_requested.emit("UI_HUD_PCT_FTP", [42])
	assert_eq(_hud.toasts().texts().size(), 1)
	assert_string_contains(_hud.toasts().texts()[0], "42", "args fill the key's placeholders")
	_bus.toast_requested.emit("Plain text passes through", [])
	assert_eq(_hud.toasts().texts()[1], "Plain text passes through")
	_bus.banner_requested.emit("WAVE {0}", [3], 2.0)
	assert_eq(_hud.banner().game_text(), "WAVE 3")
	_hud.tick(2.1)
	assert_eq(_hud.banner().game_text(), "")
	_hud.tick(3.0)
	assert_eq(_hud.toasts().texts().size(), 0)


## Toasts and banners run on the session's platform time (update()'s telemetry), not on
## frames: a fast-forwarded run (tools/screenshot) or --sim-speed never leaves a stale message
## up, and frames don't shorten them while the session time moves slowly.
func test_toasts_and_banners_follow_the_session_time() -> void:
	_hud.build(_spec(), _ctx)
	var tel := _tele(Wl.ERG, 200.0, 200)
	tel.t = 9.95
	_hud.update(tel, null, null)
	tel.t = 10.0
	_hud.update(tel, null, null)
	_bus.toast_requested.emit("Sprint in 10 s", [])
	_bus.banner_requested.emit("Endurance: 65% FTP", [], 4.0)
	for i in 30:
		tel.t += 0.05
		_hud.update(tel, null, null)
		_hud._process(0.1)
	assert_eq(_hud.toasts().texts().size(), 1, "3 s of frames but 1.5 s of session time: still up")
	assert_eq(_hud.banner().game_text(), "Endurance: 65% FTP")
	for i in 31:
		tel.t += 0.05
		_hud.update(tel, null, null)
	assert_eq(_hud.toasts().texts().size(), 0, "the toast's 3 s of session time are over")
	assert_eq(_hud.banner().game_text(), "Endurance: 65% FTP", "the banner's 4 s are not")
	tel.t = 100.0
	_hud.update(tel, null, null)
	assert_eq(_hud.banner().game_text(), "", "a fast forward ends the banner too")


func test_frames_drive_messages_without_session_time() -> void:
	_hud.build(_spec(), _ctx)
	_bus.toast_requested.emit("Hello", [])
	_hud._process(3.1)
	assert_eq(_hud.toasts().texts().size(), 0, "no telemetry yet: frame time")
	var tel := _tele(Wl.ERG, 200.0, 200)
	tel.t = 5.0
	_hud.update(tel, null, null)
	tel.t = 5.05
	_hud.update(tel, null, null)
	_bus.toast_requested.emit("Again", [])
	_hud._process(0.3)
	assert_eq(_hud.toasts().texts().size(), 1, "the session clock runs: frames don't count")
	_hud._process(0.3)
	_hud._process(3.0)
	assert_eq(_hud.toasts().texts().size(), 0, "no session time for over 0.5 s: frames count again")


func test_corner_toasts_and_banners_line_up_with_their_side() -> void:
	var spec := (
		HudSpec
		. new()
		. add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT)
		. toasts_at(HudSpec.TOP_LEFT)
		. banners_at(HudSpec.TOP_RIGHT)
	)
	_hud.build(spec, _ctx)
	_bus.toast_requested.emit("Sprint in 10 s", [])
	_bus.toast_requested.emit("Endurance 1 done: 100% in band", [])
	_bus.banner_requested.emit("Wave 3", [], 3.0)
	assert_eq(_hud.toasts().side, -1)
	for p: Node in _hud.toasts().get_children():
		assert_eq(
			(p as Control).size_flags_horizontal,
			Control.SIZE_SHRINK_BEGIN,
			"left corner: toasts line up left"
		)
		assert_eq(
			((p as Control).get_child(0) as Label).horizontal_alignment, HORIZONTAL_ALIGNMENT_LEFT
		)
	assert_eq(_hud.banner().side, 1)
	assert_eq(_hud.banner().game_label().horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT)
	_hud.build(HudSpec.new().add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT), _ctx)
	assert_eq(_hud.toasts().side, 0, "the default top-centre area centres them again")
	assert_eq(_hud.banner().side, 0)
	for p: Node in _hud.toasts().get_children():
		assert_eq((p as Control).size_flags_horizontal, Control.SIZE_SHRINK_CENTER)


## A band or status published before build() (a game's configure() runs first) or before a
## rebuild still shows on the widgets built afterwards; a cleared band stays cleared.
func test_bands_and_statuses_before_build_and_across_rebuilds() -> void:
	var feed := _hud.local_feed()
	feed.power_band(LOCAL, 190.0, 262.0)
	_hud.apply_cadence_band(LOCAL, 80.0, 95.0)
	feed.teammate_status(2, {"in_band": true, "icon": "", "text": "Diesel"})
	_hud.build(_spec(), _ctx)
	for round_i in 2:
		_hud.update(_tele(Wl.SIM, 200.0), null, null)
		var g := _hud.widget(HudSpec.POWER_GAUGE) as HudPowerGauge
		assert_eq(g.band(), Vector2(190, 262), "power band (build %d)" % round_i)
		assert_eq(
			(_hud.widget(HudSpec.CADENCE) as HudCadence).band(),
			Vector2(80, 95),
			"cadence band (build %d)" % round_i
		)
		assert_eq(
			(_hud.widget(HudSpec.TEAMMATES) as HudTeammates).card(2).status_text(),
			"Diesel",
			"status (build %d)" % round_i
		)
		_hud.build(_spec(), _ctx)
	assert_eq(_hud.power_band_of(LOCAL), Vector2(190, 262))
	_bus.power_band_changed.emit(LOCAL, 0.0, 0.0)
	_bus.cadence_band_changed.emit(LOCAL, 0.0, 0.0)
	assert_eq(_hud.power_band_of(LOCAL), Vector2.ZERO)
	assert_eq(_hud.cadence_band_of(LOCAL), Vector2.ZERO)
	_hud.build(_spec(), _ctx)
	_hud.update(_tele(Wl.SIM, 200.0), null, null)
	assert_eq(
		(_hud.widget(HudSpec.POWER_GAUGE) as HudPowerGauge).band(),
		Vector2.ZERO,
		"cleared stays cleared"
	)
	assert_eq((_hud.widget(HudSpec.CADENCE) as HudCadence).band(), Vector2.ZERO)


## A status the roster has replaced since is not brought back by a rebuild.
func test_rebuild_drops_statuses_the_roster_replaced() -> void:
	_hud.build(_spec(), _ctx)
	_bus.roster_changed.emit({2: {"name": "Bo", "slot_index": 1, "status": {}}})
	_hud.local_feed().teammate_status(2, {"text": "Diesel"})
	_bus.roster_changed.emit({2: {"name": "Bo", "slot_index": 1, "status": {}}})
	var tm := _hud.widget(HudSpec.TEAMMATES) as HudTeammates
	assert_eq(
		tm.card(2).status_text(), "Diesel", "a client's local status outlives the 2 Hz roster"
	)
	_bus.roster_changed.emit({2: {"name": "Bo", "slot_index": 1, "status": {"text": "Steam"}}})
	assert_eq(tm.card(2).status_text(), "Steam")
	_ctx.roster = {2: {"name": "Bo", "slot_index": 1, "status": {"text": "Steam"}}}
	_hud.build(_spec(), _ctx)
	assert_eq((_hud.widget(HudSpec.TEAMMATES) as HudTeammates).card(2).status_text(), "Steam")


func test_toast_args_fill_named_placeholders() -> void:
	_hud.build(_spec(), _ctx)
	_bus.toast_requested.emit("{name} joined", {"name": "Bo"})
	assert_eq(_hud.toasts().texts(), ["Bo joined"])
	_hud.local_feed().banner("{0} of {1}", [2, 5], 3.0)
	assert_eq(_hud.banner().game_text(), "2 of 5")
	_hud.show_toast("Score {0}", 7)
	assert_eq(_hud.toasts().texts()[1], "Score 7", "a single non-array arg is wrapped")


## PL11: the timeline shows ctx.strings.t(label): a strings key is translated, plain text
## passes through.
func test_timeline_label_goes_through_the_string_table() -> void:
	_hud.build(_spec(), _ctx)
	var plan := EffortPlan.of(
		[
			PlanPhase.erg(Wl.RECOVERY, 55, 120, "UI_KIND_RECOVERY"),
			PlanPhase.erg(Wl.WORK, 90, 60, "Wave 2")
		]
	)
	var ph := PhaseState.new()
	ph.index = 0
	ph.kind = Wl.RECOVERY
	ph.mode = Wl.ERG
	ph.label = "UI_KIND_RECOVERY"
	ph.duration_s = 120.0
	ph.remaining_s = 100.0
	_hud.update(_tele(Wl.ERG, 140.0, 137), ph, plan)
	var tl := _hud.widget(HudSpec.TIMELINE) as HudTimeline
	assert_eq(tl.phase_text(), _ctx.strings.t("UI_KIND_RECOVERY"))
	assert_ne(tl.phase_text(), "UI_KIND_RECOVERY", "translated")
	assert_string_contains(tl.next_text(), "Wave 2", "plain text passes through")


## BRIEF 3.3: W/kg shows only when the rider opted in (RiderProfile.show_wkg).
func test_wkg_follows_the_profile_opt_in() -> void:
	var settings := get_tree().root.get_node_or_null("Settings") as WlSettings
	assert_not_null(settings, "the Settings autoload")
	if settings == null:
		return
	var prof := settings.profile
	var old_show := prof.show_wkg
	var old_weight := prof.weight_kg
	_hud.wkg_weight_kg = -1.0
	prof.show_wkg = false
	prof.weight_kg = 80.0
	_hud.build(_spec(), _ctx)
	var t := _tele(Wl.SIM, 240.0)
	var g := _hud.widget(HudSpec.POWER_GAUGE) as HudPowerGauge
	g.set_telemetry(t)
	assert_false(g.wkg_label().visible, "no W/kg without the opt-in")
	prof.show_wkg = true
	_hud.build(_spec(), _ctx)
	g = _hud.widget(HudSpec.POWER_GAUGE) as HudPowerGauge
	g.set_telemetry(t)
	assert_true(g.wkg_label().visible, "opted in")
	assert_string_contains(g.wkg_label().text, "3.0")
	prof.show_wkg = old_show
	prof.weight_kg = old_weight


func test_bus_readout_and_late_readouts() -> void:
	_hud.build(_spec(), _ctx)
	_bus.readout_changed.emit("gate_hp", "1250")
	var r := _hud.widget(HudSpec.READOUT) as HudReadout
	assert_eq(r.value_text(), "1250")
	_bus.readout_changed.emit("other", "9")
	assert_eq(r.value_text(), "1250")
	_hud.build(_spec(), _ctx)
	assert_eq(
		(_hud.widget(HudSpec.READOUT) as HudReadout).value_text(), "1250", "kept across rebuilds"
	)


func test_bus_rescue_pause_and_warmup_banners() -> void:
	_hud.build(_spec(), _ctx)
	var b := _hud.banner()
	_bus.governor_status.emit(LOCAL, {"warmup": true, "rescue": false})
	assert_eq(b.safety_state(), HudBanner.SAFETY_WARMUP)
	_bus.rescue_changed.emit(2, true)
	assert_eq(b.safety_state(), HudBanner.SAFETY_WARMUP, "another rider's rescue")
	_bus.rescue_changed.emit(LOCAL, true)
	assert_eq(b.safety_state(), HudBanner.SAFETY_RESCUE)
	_bus.paused_changed.emit(true, "coasting")
	assert_eq(b.safety_state(), HudBanner.SAFETY_RESCUE, "pause has its own symbol")
	assert_true(_hud.pause_badge().visible, "the pause symbol")
	_bus.paused_changed.emit(false, "")
	assert_false(_hud.pause_badge().visible)
	_bus.rescue_changed.emit(LOCAL, false)
	_bus.governor_status.emit(LOCAL, {"warmup": false})
	assert_eq(b.safety_state(), HudBanner.SAFETY_NONE)


## BRIEF 4.6.3 says show "rescue": show_safety_banners = false hides only the warm-up banner;
## the local rider's rescue banner and the pause symbol still show, from every source.
func test_show_safety_banners_off_hides_only_warmup() -> void:
	assert_true(HudSpec.new().show_safety_banners, "on by default")
	var spec := _spec()
	spec.show_safety_banners = false
	_hud.build(spec, _ctx)
	var b := _hud.banner()
	assert_false(b.show_safety)
	_hud.set_safety_state(true, false, false)
	assert_eq(b.safety_state(), HudBanner.SAFETY_NONE, "warm-up hidden")
	assert_eq(b.safety_text(), "")
	_hud.set_safety_state(false, false, true)
	assert_eq(b.safety_state(), HudBanner.SAFETY_NONE, "no pause banner")
	assert_true(_hud.pause_badge().visible, "the pause symbol shows whatever the spec says")
	_hud.set_safety_state(true, true, false)
	assert_eq(b.safety_state(), HudBanner.SAFETY_RESCUE, "rescue still shows")
	assert_eq(b.safety_text(), tr("UI_BANNER_RESCUE"))
	assert_eq(HudWidget.font_px(b.safety_label()), WlTheme.BANNER_PX, "full size")
	_hud.set_safety_state(true, true, true)
	assert_eq(b.safety_state(), HudBanner.SAFETY_RESCUE, "rescue while paused")
	_hud.set_safety_state(false, false, false)
	assert_eq(b.safety_state(), HudBanner.SAFETY_NONE)
	var t := _tele(Wl.ERG, 100.0, 125)
	t.rescue = true
	_hud.update(t, null, null)
	assert_eq(b.safety_state(), HudBanner.SAFETY_RESCUE, "telemetry rescue")
	t.rescue = false
	_hud.update(t, null, null)
	assert_eq(b.safety_state(), HudBanner.SAFETY_NONE)
	_bus.rescue_changed.emit(LOCAL, true)
	assert_eq(b.safety_state(), HudBanner.SAFETY_RESCUE, "bus rescue_changed")
	_bus.governor_status.emit(LOCAL, {"rescue": false, "warmup": true})
	assert_eq(b.safety_state(), HudBanner.SAFETY_NONE, "warm-up stays hidden")
	_bus.governor_status.emit(LOCAL, {"rescue": true})
	assert_eq(b.safety_state(), HudBanner.SAFETY_RESCUE, "bus governor_status rescue")
	_bus.rescue_changed.emit(2, false)
	assert_eq(b.safety_state(), HudBanner.SAFETY_RESCUE, "another rider's rescue changes nothing")


## The default spec shows warm-up and rescue (rescue over warm-up) and the pause symbol.
func test_default_spec_shows_warmup_rescue_and_pause() -> void:
	_hud.build(_spec(), _ctx)
	var b := _hud.banner()
	assert_true(b.show_safety)
	_hud.set_safety_state(true, false, false)
	assert_eq(b.safety_state(), HudBanner.SAFETY_WARMUP)
	assert_eq(b.safety_text(), tr("UI_BANNER_WARMUP"))
	_hud.set_safety_state(true, true, false)
	assert_eq(b.safety_state(), HudBanner.SAFETY_RESCUE)
	_hud.set_safety_state(true, true, true)
	assert_eq(b.safety_state(), HudBanner.SAFETY_RESCUE)
	assert_true(_hud.pause_badge().visible)


## Telemetry.paused (the rider's own pause on not pedaling, also in multiplayer) shows the
## pause symbol above every game (BRIEF 3.5).
func test_telemetry_paused_shows_pause_symbol() -> void:
	_hud.build(_spec(), _ctx)
	var t := _tele(Wl.ERG, 0.0, 125)
	_hud.update(t, null, null)
	assert_false(_hud.pause_badge().visible)
	t.paused = true
	_hud.update(t, null, null)
	assert_true(_hud.pause_badge().visible)
	assert_eq(_hud.pause_badge().get_index(), _hud.pause_badge().get_parent().get_child_count() - 1)
	t.paused = false
	_hud.update(t, null, null)
	assert_false(_hud.pause_badge().visible)


func test_set_safety_state_and_telemetry_rescue() -> void:
	_hud.build(_spec(), _ctx)
	_hud.set_safety_state(true, false, false)
	assert_eq(_hud.banner().safety_state(), HudBanner.SAFETY_WARMUP)
	var t := _tele(Wl.ERG, 100.0, 125)
	t.rescue = true
	_hud.update(t, null, null)
	assert_eq(_hud.banner().safety_state(), HudBanner.SAFETY_RESCUE)
	t.rescue = false
	_hud.update(t, null, null)
	assert_eq(_hud.banner().safety_state(), HudBanner.SAFETY_WARMUP)


# --- trainer control lost (BRIEF 4.4) ------------------------------------------------------------


func _sfx() -> WlSfx:
	return get_tree().root.get_node_or_null("Sfx") as WlSfx


## Request Control 0x05 or Machine Status 0xFF mid-ride (TrainerService emits
## trainer_status_changed("control_lost") then trainer_control_lost): the HUD tells the
## player another app (Zwift, the Wahoo app) may hold control, once per loss, until the
## trainer is ready again.
func test_trainer_control_lost_shows_the_notice_once_until_ready() -> void:
	var sfx := _sfx()
	assert_not_null(sfx, "the Sfx autoload")
	if sfx == null:
		return
	var was_muted := sfx.muted
	sfx.muted = true
	_hud.sounds = true
	_hud.build(_spec(), _ctx)
	var b := _hud.banner()
	var panel := b.trainer_label().get_parent() as Control
	assert_eq(b.trainer_text(), "")
	assert_false(panel.visible)
	var plays := sfx.play_count
	_bus.trainer_status_changed.emit(TrainerDevice.STATUS_CONTROL_LOST, "held")
	_bus.trainer_control_lost.emit("held")
	assert_eq(b.trainer_text(), tr("TRAINER_ANOTHER_APP_CONTROL"))
	assert_string_contains(b.trainer_text(), "Zwift")
	assert_string_contains(b.trainer_text(), "Wahoo")
	assert_true(panel.visible)
	assert_eq(b.trainer_label().text, tr("TRAINER_ANOTHER_APP_CONTROL"))
	assert_eq(_hud.anchor_of(b), HudSpec.TOP, "in the banner area")
	assert_eq(sfx.play_count, plays + 1, "one sound")
	assert_eq(sfx.last_played, "warning")
	_bus.trainer_control_lost.emit("held again")
	_bus.trainer_status_changed.emit(TrainerDevice.STATUS_CONNECTED, "retrying")
	_bus.trainer_status_changed.emit(TrainerDevice.STATUS_CONTROL_LOST, "held")
	_bus.trainer_control_lost.emit("held")
	assert_eq(sfx.play_count, plays + 1, "once per loss: a failed retry adds nothing")
	assert_eq(b.trainer_text(), tr("TRAINER_ANOTHER_APP_CONTROL"), "still up while retrying")
	_bus.trainer_status_changed.emit(TrainerDevice.STATUS_READY, "Trainer ready")
	assert_eq(b.trainer_text(), "", "cleared when control comes back")
	assert_false(panel.visible)
	_bus.trainer_control_lost.emit("held")
	assert_eq(b.trainer_text(), tr("TRAINER_ANOTHER_APP_CONTROL"), "a new loss shows it again")
	assert_eq(sfx.play_count, plays + 2)
	sfx.muted = was_muted


## The notice is not a safety banner: it shows with show_safety_banners off, next to the
## rescue banner, and stays up across a rebuild.
func test_trainer_notice_ignores_show_safety_banners_and_survives_a_rebuild() -> void:
	var spec := _spec()
	spec.show_safety_banners = false
	spec.banners_at(HudSpec.TOP_RIGHT)
	_hud.build(spec, _ctx)
	_hud.set_safety_state(false, true, false)
	_bus.trainer_control_lost.emit("held")
	var b := _hud.banner()
	assert_eq(b.trainer_text(), tr("TRAINER_ANOTHER_APP_CONTROL"))
	assert_eq(b.safety_state(), HudBanner.SAFETY_RESCUE, "both show")
	assert_eq(_hud.anchor_of(b), HudSpec.TOP_RIGHT)
	_hud.build(_spec(), _ctx)
	assert_eq(b.trainer_text(), tr("TRAINER_ANOTHER_APP_CONTROL"), "kept across a rebuild")
	_bus.trainer_status_changed.emit(TrainerDevice.STATUS_READY, "")
	assert_eq(b.trainer_text(), "", "the rebuilt layer still clears it")


## Only this layer's bus drives the notice (a rebuild onto another bus drops the old one).
func test_trainer_control_lost_on_an_old_bus_is_ignored() -> void:
	_hud.build(_spec(), _ctx)
	var other := GameContext.new()
	var other_bus: WlEventBus = autofree(WlEventBus.new())
	other.events = other_bus
	other.local_peer = LOCAL
	_hud.build(_spec(), other)
	_bus.trainer_control_lost.emit("held")
	assert_eq(_hud.banner().trainer_text(), "")
	other_bus.trainer_control_lost.emit("held")
	assert_eq(_hud.banner().trainer_text(), tr("TRAINER_ANOTHER_APP_CONTROL"))


func _app_bus() -> WlEventBus:
	return get_tree().root.get_node_or_null("EventBus") as WlEventBus


## Puts `stand_in` (null: no node at all) at /root/TrainerService, the real autoload renamed
## out of the way; _restore_trainer_service (after_each) undoes it.
func _swap_trainer_service(stand_in: Node) -> void:
	_restore_trainer_service()
	var root := get_tree().root
	_real_ts = root.get_node_or_null("TrainerService")
	if _real_ts != null:
		_real_ts.name = "TrainerServiceSwappedOut"
	_stand_in = stand_in
	if stand_in != null:
		stand_in.name = "TrainerService"
		root.add_child(stand_in)


func _restore_trainer_service() -> void:
	if _stand_in != null and is_instance_valid(_stand_in):
		if _stand_in.get_parent() != null:
			_stand_in.get_parent().remove_child(_stand_in)
		_stand_in.free()
	_stand_in = null
	if _real_ts != null and is_instance_valid(_real_ts):
		_real_ts.name = "TrainerService"
	_real_ts = null


## Control lost before the session (a connect-time 0x05 in the lobby, or a loss in an earlier
## session never regained): no trainer_control_lost reaches this layer, so build() on the app's
## bus (the autoload EventBus) reads TrainerService.status() and shows the notice with one
## sound, as the signal would have; a later ready clears it.
func test_control_lost_before_build_shows_the_notice_on_the_app_bus() -> void:
	var sfx := _sfx()
	var app_bus := _app_bus()
	assert_not_null(sfx, "the Sfx autoload")
	assert_not_null(app_bus, "the EventBus autoload")
	if sfx == null or app_bus == null:
		return
	var ts := FakeTrainerService.new()
	ts.st = TrainerDevice.STATUS_CONTROL_LOST
	_swap_trainer_service(ts)
	var was_muted := sfx.muted
	sfx.muted = true
	_hud.sounds = true
	_ctx.events = app_bus
	var plays := sfx.play_count
	_hud.build(_spec(), _ctx)
	var b := _hud.banner()
	var panel := b.trainer_label().get_parent() as Control
	assert_eq(b.trainer_text(), tr("TRAINER_ANOTHER_APP_CONTROL"), "shown at build")
	assert_true(panel.visible)
	assert_eq(_hud.anchor_of(b), HudSpec.TOP, "in the banner area")
	assert_eq(sfx.play_count, plays + 1, "one sound")
	assert_eq(sfx.last_played, "warning")
	_hud.build(_spec(), _ctx)
	assert_eq(b.trainer_text(), tr("TRAINER_ANOTHER_APP_CONTROL"), "kept across a rebuild")
	assert_eq(sfx.play_count, plays + 1, "once: a rebuild while still lost adds nothing")
	app_bus.trainer_control_lost.emit("held")
	assert_eq(sfx.play_count, plays + 1, "nor does a signal for the same loss")
	ts.st = TrainerDevice.STATUS_READY
	app_bus.trainer_status_changed.emit(TrainerDevice.STATUS_READY, "Trainer ready")
	assert_eq(b.trainer_text(), "", "a later ready clears it")
	assert_false(panel.visible)
	_hud.build(_spec(), _ctx)
	assert_eq(b.trainer_text(), "", "a rebuild with the trainer ready keeps it clear")
	assert_eq(sfx.play_count, plays + 1)
	sfx.muted = was_muted


## Without a ctx the layer falls back to the autoload EventBus, so it seeds there too.
func test_control_lost_before_build_without_ctx_events() -> void:
	var ts := FakeTrainerService.new()
	ts.st = TrainerDevice.STATUS_CONTROL_LOST
	_swap_trainer_service(ts)
	_hud.build(_spec(), null)
	assert_eq(_hud.banner().trainer_text(), tr("TRAINER_ANOTHER_APP_CONTROL"))


## A private bus (a test, an in-process sim) is not this machine's trainer: no seed from it.
func test_a_private_bus_is_not_seeded_from_the_trainer_service() -> void:
	var ts := FakeTrainerService.new()
	ts.st = TrainerDevice.STATUS_CONTROL_LOST
	_swap_trainer_service(ts)
	_hud.build(_spec(), _ctx)
	assert_eq(_hud.banner().trainer_text(), "")
	_bus.trainer_control_lost.emit("held")
	assert_eq(
		_hud.banner().trainer_text(),
		tr("TRAINER_ANOTHER_APP_CONTROL"),
		"its own signal still works"
	)


## Any other status seeds nothing, and neither does a missing TrainerService node or a node
## without status(); the signal path still works then.
func test_no_seed_without_a_control_lost_trainer_service() -> void:
	var app_bus := _app_bus()
	assert_not_null(app_bus, "the EventBus autoload")
	if app_bus == null:
		return
	var real := get_tree().root.get_node_or_null("TrainerService")
	assert_true(real is WlTrainerService, "the real autoload")
	assert_true(real != null and real.has_method("status"), "has the status() the HUD reads")
	_ctx.events = app_bus
	for st: String in [
		TrainerDevice.STATUS_DISCONNECTED,
		TrainerDevice.STATUS_CONNECTED,
		TrainerDevice.STATUS_READY,
		TrainerDevice.STATUS_ERROR,
	]:
		var ts := FakeTrainerService.new()
		ts.st = st
		_swap_trainer_service(ts)
		_hud.build(_spec(), _ctx)
		assert_eq(_hud.banner().trainer_text(), "", st)
	_swap_trainer_service(null)
	assert_null(get_tree().root.get_node_or_null("TrainerService"), "no TrainerService node")
	_hud.build(_spec(), _ctx)
	assert_eq(_hud.banner().trainer_text(), "", "no node")
	_swap_trainer_service(Node.new())
	_hud.build(_spec(), _ctx)
	assert_eq(_hud.banner().trainer_text(), "", "a node without status()")
	app_bus.trainer_control_lost.emit("held")
	assert_eq(_hud.banner().trainer_text(), tr("TRAINER_ANOTHER_APP_CONTROL"), "signal still works")
	app_bus.trainer_status_changed.emit(TrainerDevice.STATUS_READY, "")
	assert_eq(_hud.banner().trainer_text(), "")


func test_phase_started_is_harmless() -> void:
	_hud.sounds = true
	_hud.build(_spec(), _ctx)
	_bus.phase_started.emit(LOCAL, 2)
	_bus.phase_started.emit(5, 1)
	pass_test("no error")


func test_rebuild_disconnects_the_old_bus() -> void:
	_hud.build(_spec(), _ctx)
	var other := GameContext.new()
	var other_bus: WlEventBus = autofree(WlEventBus.new())
	other.events = other_bus
	other.local_peer = LOCAL
	_hud.build(_spec(), other)
	_bus.toast_requested.emit("old bus", [])
	assert_eq(_hud.toasts().texts().size(), 0)
	other_bus.toast_requested.emit("new bus", [])
	assert_eq(_hud.toasts().texts(), ["new bus"])


# --- local feed and update --------------------------------------------------------------------


func test_local_feed_draws_on_this_layer() -> void:
	_hud.build(_spec(), _ctx)
	var feed := _hud.local_feed()
	assert_true(feed is HudLocalFeed)
	assert_same(feed, _hud.local_feed())
	feed.toast("Line snapped", [], 3)
	assert_eq(_hud.toasts().texts(), ["Line snapped"], "a client draws whatever peer says")
	feed.banner("Boss!", [], 4.0, 0)
	assert_eq(_hud.banner().game_text(), "Boss!")
	feed.power_band(LOCAL, 190.0, 260.0)
	assert_eq(
		(_hud.widget(HudSpec.POWER_GAUGE) as HudPowerGauge).band(),
		Vector2.ZERO,
		"ERG/OFF shows no SIM band"
	)
	_hud.update(_tele(Wl.SIM, 200.0), null, null)
	assert_eq((_hud.widget(HudSpec.POWER_GAUGE) as HudPowerGauge).band(), Vector2(190, 260))
	feed.teammate_status(2, {"in_band": true, "icon": "", "text": "Diesel"})
	var tm := _hud.widget(HudSpec.TEAMMATES) as HudTeammates
	assert_eq(tm.card(2).status_text(), "Diesel")
	feed.readout("gate_hp", "900")
	assert_eq((_hud.widget(HudSpec.READOUT) as HudReadout).value_text(), "900")


func test_local_feed_outlives_the_layer_safely() -> void:
	var hud := HudLayer.new()
	hud.sounds = false
	var feed := hud.local_feed()
	hud.free()
	feed.toast("nobody", [])
	feed.power_band(1, 1.0, 2.0)
	pass_test("no crash after the layer is gone")


func test_update_feeds_every_widget() -> void:
	_hud.build(_spec(), _ctx)
	var plan := EffortPlan.of(
		[
			PlanPhase.erg(Wl.WARMUP, 50, 300, "Warm-up"),
			PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 30, "Sprint")
		]
	)
	var ph := PhaseState.new()
	ph.index = 1
	ph.kind = Wl.FREE
	ph.mode = Wl.SIM
	ph.label = "Sprint"
	ph.duration_s = 30.0
	ph.elapsed_s = 10.0
	ph.remaining_s = 20.0
	var t := _tele(Wl.SIM, 412.0)
	t.gear = 15
	_hud.update(t, ph, plan)
	assert_eq((_hud.widget(HudSpec.POWER_GAUGE) as HudPowerGauge).watts_label().text, "412")
	assert_eq((_hud.widget(HudSpec.CADENCE) as HudCadence).rpm_label().text, "90")
	assert_almost_eq((_hud.widget(HudSpec.WBAL) as HudWbal).fraction(), 0.5, 1e-6)
	assert_eq((_hud.widget(HudSpec.TIMELINE) as HudTimeline).phase_text(), "Sprint")
	assert_eq((_hud.widget(HudSpec.TIMELINE) as HudTimeline).time_text(), "0:20")
	var gear := _hud.widget(HudSpec.GEAR) as HudGear
	assert_true(gear.visible, "gear shows in SIM")
	assert_eq(gear.gear(), 15)
	_hud.update(_tele(Wl.ERG, 200.0, 200), null, null)
	assert_false(gear.visible, "and hides in ERG")


func test_ftp_and_wkg_from_the_rider() -> void:
	_hud.wkg_weight_kg = 80.0
	_hud.build(_spec(), _ctx)
	var g := _hud.widget(HudSpec.POWER_GAUGE) as HudPowerGauge
	assert_eq(g.ftp_w, 250.0, "the local slot's FTP")
	var t := _tele(Wl.SIM, 240.0)
	t.ftp_pct = 0.0
	g.set_telemetry(t)
	assert_string_contains(g.pct_label().text, "96")
	assert_true(g.wkg_label().visible)
	assert_string_contains(g.wkg_label().text, "3.0")


func test_key_numbers_on_the_layer_are_at_least_48_px() -> void:
	_hud.build(_spec().add(HudSpec.READOUT, HudSpec.TOP_RIGHT, {"source": "power_w"}), _ctx)
	assert_gte(
		HudWidget.font_px((_hud.widget(HudSpec.POWER_GAUGE) as HudPowerGauge).watts_label()), 48
	)
	assert_gte(HudWidget.font_px((_hud.widget(HudSpec.CADENCE) as HudCadence).rpm_label()), 48)
	assert_gte(HudWidget.font_px((_hud.widget(HudSpec.GEAR) as HudGear).gear_label()), 48)
	for r in _hud.widgets_of(HudSpec.READOUT):
		assert_gte(HudWidget.font_px((r as HudReadout).value_label()), 48)


func test_build_without_ctx_uses_defaults() -> void:
	_hud.build(HudSpec.new().add(HudSpec.POWER_GAUGE, HudSpec.TOP), null)
	assert_eq(_hud.local_peer(), 0)
	assert_not_null(_hud.widget(HudSpec.POWER_GAUGE))


func test_hud_runs_in_a_paused_tree_settings() -> void:
	_hud.build(_spec(), _ctx)
	for w in _hud.widgets_of(HudSpec.POWER_GAUGE):
		assert_eq(w.process_mode, Node.PROCESS_MODE_ALWAYS)


# --- centre stacks keep clear of the corners ----------------------------------------------------


func _eight_riders() -> Dictionary:
	var r := {}
	for i in 8:
		var peer := i + 1 if i < 6 else -(i - 5)
		r[peer] = {"name": "Rider %d" % i, "slot_index": i, "raw_w": 1000.0, "ftp_pct": 150.0}
	return r


func test_bottom_strip_wraps_and_never_runs_under_the_corners() -> void:
	var shop := PanelContainer.new()
	shop.custom_minimum_size = Vector2(470, 300)
	var spec := (
		HudSpec
		. new()
		. add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT)
		. add(HudSpec.TEAMMATES, HudSpec.BOTTOM)
		. add_control(shop, HudSpec.BOTTOM_RIGHT)
	)
	_hud.build(spec, _ctx)
	_bus.roster_changed.emit(_eight_riders())
	_hud.relayout()
	await wait_process_frames(3)
	var tm := _hud.widget(HudSpec.TEAMMATES) as HudTeammates
	assert_eq(tm.columns(), 4, "8 riders wrap into 2 rows of 4")
	var b := _hud.anchor_box(HudSpec.BOTTOM)
	var bl := _hud.anchor_box(HudSpec.BOTTOM_LEFT)
	var br := _hud.anchor_box(HudSpec.BOTTOM_RIGHT)
	var center := Rect2(b.position, b.size)
	assert_false(
		center.intersects(Rect2(bl.position, bl.size)),
		"clear of bottom_left: %s vs %s" % [center, Rect2(bl.position, bl.size)]
	)
	assert_false(
		center.intersects(Rect2(br.position, br.size)),
		"clear of bottom_right: %s vs %s" % [center, Rect2(br.position, br.size)]
	)
	assert_lte(center.size.x, _hud.center_width(HudSpec.BOTTOM, Vector2(1920, 1080)) + 1.0)


func test_long_toasts_and_banners_wrap_between_the_corners() -> void:
	var spec := (
		HudSpec
		. new()
		. add(HudSpec.TIMELINE, HudSpec.TOP_LEFT)
		. add(HudSpec.READOUT, HudSpec.TOP_RIGHT, {"source": "power_w"})
		. add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT)
	)
	_hud.build(spec, _ctx)
	(
		_hud
		. show_toast(
			"A very long toast that would otherwise run all the way across the top of the screen and under the timeline",
			[]
		)
	)
	_hud.show_banner(
		"An equally long banner text that has to wrap onto a second line to stay readable", [], 5.0
	)
	_hud.relayout()
	await wait_process_frames(3)
	var top := _hud.anchor_box(HudSpec.TOP)
	var tl := _hud.anchor_box(HudSpec.TOP_LEFT)
	var tr_box := _hud.anchor_box(HudSpec.TOP_RIGHT)
	var center := Rect2(top.position, top.size)
	assert_false(center.intersects(Rect2(tl.position, tl.size)), "clear of the timeline")
	assert_false(center.intersects(Rect2(tr_box.position, tr_box.size)), "clear of the readout")
	assert_gt(center.size.y, 150.0, "wrapped onto more lines")


## Workout's layout: the timeline in the top centre, toasts at top_left. A long toast wraps
## within a third of the screen, so it never runs under the timeline and never squeezes it.
func test_corner_toasts_wrap_and_leave_the_centre_its_room() -> void:
	var spec := (
		HudSpec
		. new()
		. add(HudSpec.TIMELINE, HudSpec.TOP)
		. add(HudSpec.READOUT, HudSpec.TOP_RIGHT, {"source": "power_w"})
		. add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT)
		. toasts_at(HudSpec.TOP_LEFT)
		. banners_at(HudSpec.BOTTOM_RIGHT)
	)
	_hud.build(spec, _ctx)
	_hud.show_toast(
		"Interval 3 done: 96% in band, the best of the session so far, keep it going", []
	)
	_hud.show_banner(
		"A very long banner in a corner that must wrap instead of crossing the screen", [], 5.0
	)
	_hud.relayout()
	await wait_process_frames(3)
	_hud.relayout()
	await wait_process_frames(2)
	var tl := _hud.anchor_box(HudSpec.TOP_LEFT)
	var top := _hud.anchor_box(HudSpec.TOP)
	var br := _hud.anchor_box(HudSpec.BOTTOM_RIGHT)
	var third := HudLayer.corner_text_width(Vector2(1920, 1080))
	assert_lte(tl.size.x, third + 1.0, "the toast wraps within a third: %s" % tl.size)
	assert_lte(br.size.x, third + 1.0, "so does a corner banner: %s" % br.size)
	assert_false(
		Rect2(tl.position, tl.size).intersects(Rect2(top.position, top.size)),
		"clear of the timeline"
	)
	assert_gt(
		_hud.widget(HudSpec.TIMELINE).ui_scale, 0.9, "the timeline keeps (nearly) its full size"
	)


func test_demo_scene_builds_headless() -> void:
	var scene := load("res://addons/wattlands/ui/hud/hud_demo.tscn") as PackedScene
	assert_not_null(scene)
	var demo: Node = add_child_autofree(scene.instantiate())
	await wait_process_frames(3)
	var hud: HudLayer = null
	for c in demo.get_children():
		if c is HudLayer:
			hud = c
	assert_not_null(hud)
	for id: String in HudSpec.KIT_WIDGETS:
		assert_not_null(hud.widget(id), id)
	assert_true(hud.widget(HudSpec.GEAR).visible, "the demo rides in SIM")
