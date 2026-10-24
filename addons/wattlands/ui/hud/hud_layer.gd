class_name HudLayer
extends CanvasLayer
## The in-session HUD (BRIEF 3.9): builds the kit widgets and the game's Controls from a
## HudSpec, at native resolution above the game view. Owned by ui-hud; public API frozen
## after W0. Readable from 3 m: key numbers >= 48 px at 1080p.
## It reads from the session's WlEventBus (power_band_changed, cadence_band_changed,
## roster_changed, toast_requested, banner_requested, readout_changed, rescue_changed,
## phase_started, paused_changed, governor_status, trainer_control_lost,
## trainer_status_changed) and from update() calls the GameHost makes every tick for the local
## rider. local_feed() draws here directly.
##
## Layout (sizes in 1080p pixels, the window's base size):
## - Anchors: one stack per anchor, WlTheme.MARGIN_PX (32 px) from the screen edges. Entries
##   at one anchor stack in the order added: top anchors downward, bottom anchors upward
##   (the first entry sits nearest the edge). Kit widgets come first, then the game's
##   Controls, then the banner area and the toast area if they share that anchor. The top and
##   bottom centre stacks keep clear of the corner stacks on their edge (center_width()):
##   a teammate strip wraps into two rows and then shrinks, other kit widgets shrink, and
##   toast and banner text wraps. Toasts and banners in a corner wrap within a third of the
##   screen (corner_text_width()).
## - Rect2i positions are art pixels mapped through PixelViewport.art_rect_to_screen()
##   (integer scale plus letterbox) and re-laid out when the PixelViewport or the window
##   resizes, or the PixelViewport emits `layout_changed`. Kit widgets in a rect shrink to
##   fit it (several in one rect stack and share it; a teammate strip prefers one row scaled
##   to the rect's width and height, wrapping only below its minimum scale); key numbers
##   stay >= 48 px, so a rect below a widget's min_rect() overflows. Game Controls in a rect are sized to it. Without
##   a PixelViewport (3D games) a Rect2i is taken as 1080p pixels.
## - The CanvasLayer `layer` is LAYER (10): a game view's own CanvasLayer with a lower
##   layer draws under the HUD (vignettes), a higher one above it.
## - Raw W and %FTP always show: if the spec has no power gauge (and not both a power_w and
##   an ftp_pct readout), a power gauge is added at bottom_left (ensure_power_visible).
##   W/kg shows only if the rider opted in (profile `show_wkg`; or wkg_weight_kg).
## - Safety banners: rescue (4.6.3) and warm-up (4.6.8), from set_safety_state(), update()'s
##   telemetry (rescue) and the bus (rescue_changed, governor_status {warmup, rescue}) for the
##   local rider. The rescue banner always shows; spec.show_safety_banners = false hides only
##   the warm-up banner (W4).
## - Pause (BRIEF 3.5): the HudPauseBadge (two bars, UI_PAUSE_TITLE and the resume hint) shows
##   above the game, centred near the top, whenever the local rider is paused:
##   set_safety_state(paused), update()'s Telemetry.paused (the rider's own pause on not
##   pedaling, also in multiplayer), paused_changed and governor_status {paused}. No HudSpec
##   hides it.
## - Mock keyboard readout: while the TrainerService's device is a MockTrainer with keyboard
##   control on, a small HudMockKeys line (power, cadence, keys) sits in the bottom-right corner,
##   in the game's palette; no HudSpec hides it.
## - Heart rate: the power gauge shows Telemetry.heart_rate_bpm while it is above 0 (a paired
##   sensor or a MockTrainer `hr` profile) and hides it otherwise.
## - Trainer control lost (BRIEF 4.4, W4): EventBus.trainer_control_lost (Request Control
##   0x05 or Machine Status 0xFF on this machine's trainer) puts up the trainer notice
##   TRAINER_ANOTHER_APP_CONTROL in the banner area, with the "warning" sound, once per loss;
##   it stays up (also across a rebuild) until trainer_status_changed reports the trainer
##   ready again. build() on the autoload EventBus (the app's session bus) also seeds it from
##   the TrainerService autoload's status(), looked up like Settings: a session that starts
##   while control is already lost (in the lobby, or in an earlier session and never
##   regained) shows the notice and plays the sound as the signal would have, once.
##   Only a rendering GameHost builds a HudLayer, so headless peers show nothing.
## - The latest power and cadence bands per peer, local teammate statuses and custom readout
##   texts are kept, so a band published before build() (in configure()) or across a rebuild
##   still shows.
## - Toasts and game banners run on the session's platform time: update() advances them by
##   how far the telemetry's time moved (at most MAX_MESSAGE_STEP_S per call), so a fast
##   forward (tools/screenshot), --sim-speed or a slow frame never leaves a stale message up.
##   _process advances them by frame time only while no telemetry time moves (a HUD used on
##   its own, before the first tick, or after FRAME_FALLBACK_S without one).
## - Toasts and banners in a corner anchor line up with that side of the screen (set_side).

const LAYER := 10
const BASE_SIZE := Vector2(1920, 1080)
## The PixelViewport signal for layout changes without a resize (connected by name before
## world-kits merged; now PixelViewport.layout_changed directly).
const PV_LAYOUT_SIGNAL := &"layout_changed"
## Longest step one update() advances toasts and banners (a rejoin's time jump).
const MAX_MESSAGE_STEP_S := 1.0
## Frame time without a telemetry time step after which frames advance the messages again.
const FRAME_FALLBACK_S := 0.5

## Screen size for layout (tests); ZERO uses the viewport's visible rect.
var screen_size_override: Vector2 = Vector2.ZERO
## Add a power gauge when the spec shows no raw W and %FTP (BRIEF 3.3, 3.1 pillar 2).
var ensure_power_visible: bool = true
## Play Sfx cues (toast, banner warning, rescue start, phase start).
var sounds: bool = true
## >= 0 overrides the W/kg weight (0 hides W/kg); < 0 reads the profile opt-in.
var wkg_weight_kg: float = -1.0

var _spec: HudSpec = null
## HudSpec.palette for the kit widgets, toasts and game banner.
var _palette: HudPalette = HudPalette.new()
var _ctx: GameContext = null
var _pv: PixelViewport = null
var _bus: WlEventBus = null
var _root: Control = null
var _boxes: Dictionary = {}
## [{"rect": Rect2i, "node": Control (holder, exactly the mapped rect), "stack": VBoxContainer}]
var _slots: Array[Dictionary] = []
var _widgets: Array[HudWidget] = []
var _game_controls: Array[Control] = []
var _toasts: HudToasts = null
var _banner: HudBanner = null
var _feed: HudLocalFeed = null
var _pause_badge: HudPauseBadge = null
var _mock_keys: HudMockKeys = null
var _local_peer: int = 0
var _readouts: Dictionary = {}
## The latest power and cadence bands per peer (Vector2(lo, hi)) and the local teammate
## statuses, kept so widgets built later (a band published in configure(), before build) or
## rebuilt show them.
var _power_bands: Dictionary = {}
var _cadence_bands: Dictionary = {}
var _statuses: Dictionary = {}
var _bus_links: Array[Dictionary] = []
var _relayout_queued: bool = false
## anchor -> Vector2 kept clear at that corner (reserve_corner).
var _reserved: Dictionary = {}
var _warned_no_pv: bool = false
var _ftp: float = 200.0
var _wprime: float = 20000.0
var _weight: float = 0.0
var _ext_warmup: bool = false
var _ext_rescue: bool = false
var _ext_paused: bool = false
var _tele_rescue: bool = false
var _tele_paused: bool = false
var _rescue_shown: bool = false
## True from trainer_control_lost until the trainer reports ready again.
var _control_lost: bool = false
## The telemetry time update() last saw (-1 before the first), whether it ever moved, and
## frame time since it last moved.
var _tel_t: float = -1.0
var _tel_clocked: bool = false
var _frames_since_tel: float = 0.0


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = WlTheme.get_theme()
	add_child(_root)
	_toasts = HudToasts.new()
	_banner = HudBanner.new()
	_feed = HudLocalFeed.new(self)
	_pause_badge = HudPauseBadge.new()
	_root.add_child(_pause_badge)
	_mock_keys = HudMockKeys.new()
	_root.add_child(_mock_keys)


func _ready() -> void:
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_queue_relayout):
		vp.size_changed.connect(_queue_relayout)
	relayout()


func _process(delta: float) -> void:
	_mock_keys.refresh()
	_frames_since_tel += delta
	if not _tel_clocked or _frames_since_tel > FRAME_FALLBACK_S:
		tick(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_disconnect_bus()
		for n: Node in [_toasts, _banner]:
			if n != null and is_instance_valid(n) and n.get_parent() == null:
				n.free()


## Build widgets for `spec`. `pixel_viewport` maps 2D Rect2i positions (art pixels) through
## its integer scale and letterbox offset; null for 3D games.
func build(spec: HudSpec, ctx: GameContext, pixel_viewport: PixelViewport = null) -> void:
	var old_controls := _game_controls.duplicate()
	_clear()
	_spec = spec if spec != null else HudSpec.new()
	_ctx = ctx
	_set_pixel_viewport(pixel_viewport)
	_local_peer = ctx.local_peer if ctx != null else 0
	_bus = ctx.events if ctx != null and ctx.events != null else _autoload_bus()
	_read_rider_data()
	_banner.show_safety = _spec.show_safety_banners
	_palette = HudPalette.from_dict(_spec.palette)
	_banner.set_palette(_palette)
	_toasts.set_palette(_palette)
	_mock_keys.set_palette(_palette)
	for entry: Dictionary in _spec.widgets:
		var id := str(entry.get("widget", ""))
		var at: Variant = entry.get("at", null)
		if not HudSpec.is_valid_position(at):
			push_error("HudLayer: widget '%s' has an invalid position %s" % [id, at])
			continue
		var opts: Variant = entry.get("options", {})
		var w := make_widget(id, opts if opts is Dictionary else {})
		if w != null:
			_widgets.append(w)
			_place(w, at)
	if ensure_power_visible and not _shows_power():
		var g := make_widget(HudSpec.POWER_GAUGE, {})
		_widgets.append(g)
		_place(g, HudSpec.BOTTOM_LEFT)
	for entry: Dictionary in _spec.controls:
		var c := entry.get("control", null) as Control
		var at: Variant = entry.get("at", null)
		if c == null:
			push_error("HudLayer: a game control entry has no Control")
			continue
		if not HudSpec.is_valid_position(at):
			push_error("HudLayer: control '%s' has an invalid position %s" % [c.name, at])
			continue
		if c.get_parent() != null:
			c.get_parent().remove_child(c)
		_game_controls.append(c)
		_place(c, at)
	_place(
		_banner, _spec.banner_area if HudSpec.is_valid_position(_spec.banner_area) else HudSpec.TOP
	)
	_place(
		_toasts, _spec.toast_area if HudSpec.is_valid_position(_spec.toast_area) else HudSpec.TOP
	)
	for c: Control in old_controls:
		if is_instance_valid(c) and c.get_parent() == null and not _game_controls.has(c):
			c.free()
	if ctx != null and not ctx.roster.is_empty():
		set_roster(ctx.roster)
	for peer: int in _statuses.keys():
		for w in _widgets:
			if w is HudTeammates:
				(w as HudTeammates).set_status(peer, _statuses[peer])
	for id: String in _readouts.keys():
		set_readout(id, _readouts[id])
	_connect_bus()
	_seed_trainer_notice()
	_refresh_safety()
	relayout()


## Per-tick local data: the local rider's telemetry, current phase, and plan (timeline).
func update(telemetry: Telemetry, phase: PhaseState, plan: EffortPlan) -> void:
	if telemetry != null:
		_advance_messages(telemetry.t)
		for w in _widgets:
			w.set_telemetry(telemetry)
		_tele_rescue = telemetry.rescue
		_tele_paused = telemetry.paused
		_refresh_safety()
	if phase != null:
		for w in _widgets:
			w.set_phase(phase, plan)


## Toasts and banners follow the session's platform time (see the class doc).
func _advance_messages(t: float) -> void:
	if _tel_t >= 0.0 and t > _tel_t + 1e-9:
		tick(minf(t - _tel_t, MAX_MESSAGE_STEP_S))
		_tel_clocked = true
		_frames_since_tel = 0.0
	_tel_t = t


## The pause symbol (shown while the local rider is paused).
func pause_badge() -> HudPauseBadge:
	return _pause_badge


## The mock-trainer keyboard readout (hidden unless a MockTrainer's keyboard control is on).
func mock_keys() -> HudMockKeys:
	return _mock_keys


## A HudFeed that draws on this layer only (the GameHost wraps it with network routing).
func local_feed() -> HudFeed:
	return _feed


## Show the kit's warm-up or rescue banner state.
func set_safety_state(warmup_active: bool, rescue: bool, paused: bool) -> void:
	_ext_warmup = warmup_active
	_ext_rescue = rescue
	_ext_paused = paused
	_refresh_safety()


# --- drawing API (the local feed and the bus handlers use it) --------------------------------


## A toast from a string key (game or platform) with {0}/{name} args.
func show_toast(key: String, args: Variant = []) -> void:
	_toasts.push(_text(key, args))
	_play("toast")


## A banner from a string key for `seconds`.
func show_banner(key: String, args: Variant = [], seconds: float = 3.0) -> void:
	_banner.show_game_banner(_text(key, args), seconds)
	_play("warning")


## The power band of `peer`'s gauges (SIM band; 0, 0 clears). Kept for gauges built later.
func apply_power_band(peer: int, lo_w: float, hi_w: float) -> void:
	if hi_w <= 0.0 or hi_w < lo_w:
		_power_bands.erase(peer)
	else:
		_power_bands[peer] = Vector2(lo_w, hi_w)
	for w in _widgets:
		if w is HudPowerGauge and (w as HudPowerGauge).peer == peer:
			(w as HudPowerGauge).set_power_band(lo_w, hi_w)


## The cadence band of `peer`'s cadence widgets (0, 0 clears). Kept for widgets built later.
func apply_cadence_band(peer: int, lo_rpm: float, hi_rpm: float) -> void:
	if hi_rpm <= 0.0 or hi_rpm < lo_rpm:
		_cadence_bands.erase(peer)
	else:
		_cadence_bands[peer] = Vector2(lo_rpm, hi_rpm)
	for w in _widgets:
		if w is HudCadence and (w as HudCadence).peer == peer:
			(w as HudCadence).set_cadence_band(lo_rpm, hi_rpm)


## One rider's teammate_status (local only; the host's statuses arrive in the roster). It
## stays on the strip until the roster's own status for that rider changes, and is kept for a
## strip built later.
func apply_teammate_status(peer: int, status: Dictionary) -> void:
	_statuses[peer] = status.duplicate(true)
	for w in _widgets:
		if w is HudTeammates:
			(w as HudTeammates).set_status(peer, status)


## The latest power band of `peer` (Vector2(lo, hi); ZERO when none).
func power_band_of(peer: int) -> Vector2:
	return _power_bands.get(peer, Vector2.ZERO)


## The latest cadence band of `peer` (Vector2(lo, hi); ZERO when none).
func cadence_band_of(peer: int) -> Vector2:
	return _cadence_bands.get(peer, Vector2.ZERO)


func set_roster(roster: Dictionary) -> void:
	for w in _widgets:
		if w is HudTeammates:
			(w as HudTeammates).set_roster(roster)


## The text of custom readouts with this id (kept for readouts built later).
func set_readout(id: String, text: String) -> void:
	_readouts[id] = text
	for w in _widgets:
		if (
			w is HudReadout
			and (w as HudReadout).source == "custom"
			and (w as HudReadout).readout_id == id
		):
			(w as HudReadout).set_text(text)


## Advance toasts and banners by dt seconds (update() with the session's platform time;
## _process with the frame delta while no session time arrives).
func tick(dt: float) -> void:
	_toasts.tick(dt)
	_banner.tick(dt)


## A kit widget for `id` configured for this layer's rider (null and push_error if unknown).
func make_widget(id: String, options: Dictionary = {}) -> HudWidget:
	var w: HudWidget = null
	match id:
		HudSpec.POWER_GAUGE:
			var g := HudPowerGauge.new()
			g.peer = int(options.get("peer", _local_peer))
			w = g
		HudSpec.CADENCE:
			var c := HudCadence.new()
			c.peer = int(options.get("peer", _local_peer))
			w = c
		HudSpec.WBAL:
			var wb := HudWbal.new()
			wb.wprime_j = _wprime
			w = wb
		HudSpec.TIMELINE:
			w = HudTimeline.new()
		HudSpec.TEAMMATES:
			var tm := HudTeammates.new()
			tm.local_peer = _local_peer
			w = tm
		HudSpec.READOUT:
			w = HudReadout.new()
		HudSpec.GEAR:
			w = HudGear.new()
		_:
			push_error(
				"HudLayer: unknown kit widget '%s' (use %s)" % [id, ", ".join(HudSpec.KIT_WIDGETS)]
			)
			return null
	w.name = "%s_%d" % [id, _widgets.size()]
	w.ftp_w = _ftp
	w.weight_kg = _weight
	w.configure(options)
	w.set_palette(_palette)
	if w is HudPowerGauge and _power_bands.has((w as HudPowerGauge).peer):
		var pb: Vector2 = _power_bands[(w as HudPowerGauge).peer]
		(w as HudPowerGauge).set_power_band(pb.x, pb.y)
	elif w is HudCadence and _cadence_bands.has((w as HudCadence).peer):
		var cb: Vector2 = _cadence_bands[(w as HudCadence).peer]
		(w as HudCadence).set_cadence_band(cb.x, cb.y)
	return w


# --- layout --------------------------------------------------------------------------------


func relayout() -> void:
	_relayout_queued = false
	var ss := screen_size()
	_root.position = Vector2.ZERO
	_root.size = ss
	_pause_badge.layout(ss)
	_root.move_child(_pause_badge, -1)
	_mock_keys.layout(ss)
	_fit_centers(ss)
	for anchor: String in _boxes.keys():
		var box: VBoxContainer = _boxes[anchor]
		var sz := box.get_combined_minimum_size()
		box.size = sz
		box.position = anchor_position(anchor, sz, ss) + _reserve_shift(anchor)
	for slot in _slots:
		var r := map_rect(slot["rect"])
		var holder: Control = slot["node"]
		holder.position = r.position
		holder.size = r.size
		var stack: VBoxContainer = slot["stack"]
		_fit_slot(stack, r.size)
		stack.position = Vector2.ZERO
		stack.size = r.size


func screen_size() -> Vector2:
	if screen_size_override != Vector2.ZERO:
		return screen_size_override
	if is_inside_tree():
		var vp := get_viewport()
		if vp != null:
			return vp.get_visible_rect().size
	return BASE_SIZE


## Width the top (or bottom) centre stack may use without running under the corner stacks
## of the same edge.
func center_width(center: String, ss: Vector2) -> float:
	var corners: Array[String] = [HudSpec.TOP_LEFT, HudSpec.TOP_RIGHT]
	if center == HudSpec.BOTTOM:
		corners = [HudSpec.BOTTOM_LEFT, HudSpec.BOTTOM_RIGHT]
	var side := 0.0
	for corner in corners:
		if _boxes.has(corner):
			side = maxf(
				side, (_boxes[corner] as Control).get_combined_minimum_size().x + WlTheme.GAP_PX
			)
		if _reserved.has(corner):
			side = maxf(side, (_reserved[corner] as Vector2).x + WlTheme.GAP_PX)
	return maxf(120.0, ss.x - 2.0 * (WlTheme.MARGIN_PX + side))


## Keep `size` (1080p pixels, measured from the screen corner's margin) clear at a corner
## anchor (HudSpec.TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT or BOTTOM_RIGHT) for something the host
## draws there, such as the app shell's on-screen panic button (BRIEF 4.6.5): that corner's
## stack moves inward by the reserved height plus a gap (bottom corners up, top corners down)
## and the centre stack of the same edge keeps clear of the reserved width. Vector2.ZERO
## releases the corner. Additive (W2).
func reserve_corner(anchor: String, size: Vector2) -> void:
	if not [HudSpec.TOP_LEFT, HudSpec.TOP_RIGHT, HudSpec.BOTTOM_LEFT, HudSpec.BOTTOM_RIGHT].has(
		anchor
	):
		push_error("HudLayer: reserve_corner needs a corner anchor, not '%s'" % anchor)
		return
	if size.x <= 0.0 or size.y <= 0.0:
		_reserved.erase(anchor)
	else:
		_reserved[anchor] = size
	_queue_relayout()


## The size kept clear at `anchor` (Vector2.ZERO if none).
func reserved_corner(anchor: String) -> Vector2:
	return _reserved.get(anchor, Vector2.ZERO)


func _reserve_shift(anchor: String) -> Vector2:
	if not _reserved.has(anchor):
		return Vector2.ZERO
	var dy := (_reserved[anchor] as Vector2).y + WlTheme.GAP_PX
	if anchor == HudSpec.BOTTOM_LEFT or anchor == HudSpec.BOTTOM_RIGHT:
		return Vector2(0.0, -dy)
	return Vector2(0.0, dy)


## Top-left of an anchor stack of size `sz` on a screen of size `ss`.
static func anchor_position(anchor: String, sz: Vector2, ss: Vector2) -> Vector2:
	var m := float(WlTheme.MARGIN_PX)
	match anchor:
		HudSpec.TOP_LEFT:
			return Vector2(m, m)
		HudSpec.TOP:
			return Vector2(roundf((ss.x - sz.x) * 0.5), m)
		HudSpec.TOP_RIGHT:
			return Vector2(ss.x - sz.x - m, m)
		HudSpec.BOTTOM_LEFT:
			return Vector2(m, ss.y - sz.y - m)
		HudSpec.BOTTOM:
			return Vector2(roundf((ss.x - sz.x) * 0.5), ss.y - sz.y - m)
		HudSpec.BOTTOM_RIGHT:
			return Vector2(ss.x - sz.x - m, ss.y - sz.y - m)
	return Vector2(m, m)


## An art-pixel rect in screen pixels (through the PixelViewport; 1:1 without one).
func map_rect(r: Rect2i) -> Rect2:
	if _pv != null and is_instance_valid(_pv):
		return _pv.art_rect_to_screen(r)
	if not _warned_no_pv:
		_warned_no_pv = true
		push_warning("HudLayer: a Rect2i position without a PixelViewport is taken as 1080p pixels")
	return Rect2(r)


# --- queries (tests, the GameHost, games) ----------------------------------------------------


func root() -> Control:
	return _root


func spec() -> HudSpec:
	return _spec


func local_peer() -> int:
	return _local_peer


func toasts() -> HudToasts:
	return _toasts


func banner() -> HudBanner:
	return _banner


## Every kit widget of `id` (HudSpec.POWER_GAUGE, ...) in build order.
func widgets_of(id: String) -> Array[HudWidget]:
	var out: Array[HudWidget] = []
	for w in _widgets:
		if w.widget_id == id:
			out.append(w)
	return out


## The first kit widget of `id`, or null.
func widget(id: String) -> HudWidget:
	var all := widgets_of(id)
	return all[0] if not all.is_empty() else null


## The stack Control of an anchor (null if nothing sits there).
func anchor_box(anchor: String) -> Control:
	return _boxes.get(anchor, null)


## The anchor a node sits at ("" if it sits in a rect or nowhere).
func anchor_of(node: Node) -> String:
	for anchor: String in _boxes.keys():
		if node.get_parent() == _boxes[anchor]:
			return anchor
	return ""


## The art-pixel rect a node sits in (Rect2i() if none).
func rect_of(node: Node) -> Rect2i:
	for slot in _slots:
		if node.get_parent() == slot["stack"]:
			return slot["rect"]
	return Rect2i()


## The screen rect of the rect slot holding `node` (Rect2() if none).
func slot_screen_rect(node: Node) -> Rect2:
	for slot in _slots:
		if node.get_parent() == slot["stack"]:
			var n: Control = slot["node"]
			return Rect2(n.position, n.size)
	return Rect2()


# --- internals -------------------------------------------------------------------------------


func _clear() -> void:
	_disconnect_bus()
	for w in _widgets:
		if w is HudTeammates and is_instance_valid(w):
			# Statuses the roster has replaced since are dropped (HudTeammates.set_status).
			_statuses = (w as HudTeammates).local_statuses()
			break
	for n: Node in [_toasts, _banner]:
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
	for c: Control in _game_controls:
		if is_instance_valid(c) and c.get_parent() != null:
			c.get_parent().remove_child(c)
	_game_controls.clear()
	for anchor: String in _boxes.keys():
		var box: Node = _boxes[anchor]
		_root.remove_child(box)
		box.free()
	_boxes.clear()
	for slot in _slots:
		var node: Node = slot["node"]
		_root.remove_child(node)
		node.free()
	_slots.clear()
	_widgets.clear()
	_toasts.clear()


func _place(node: Control, at: Variant) -> void:
	if at is Rect2i:
		var slot := _slot_for(at)
		slot.add_child(node)
		_set_side(node, 0)
		return
	var anchor := str(at)
	var box := _box(anchor)
	box.add_child(node)
	if anchor.begins_with("bottom"):
		box.move_child(node, 0)
	if anchor.ends_with("left"):
		node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_set_side(node, -1)
	elif anchor.ends_with("right"):
		node.size_flags_horizontal = Control.SIZE_SHRINK_END
		_set_side(node, 1)
	else:
		node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_set_side(node, 0)


## Toasts and banners line up with their anchor's side.
static func _set_side(node: Control, side: int) -> void:
	if node is HudToasts:
		(node as HudToasts).set_side(side)
	elif node is HudBanner:
		(node as HudBanner).set_side(side)


func _box(anchor: String) -> VBoxContainer:
	if _boxes.has(anchor):
		return _boxes[anchor]
	var box := VBoxContainer.new()
	box.name = "Anchor_" + anchor
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", WlTheme.GAP_PX)
	if anchor.begins_with("bottom"):
		box.alignment = BoxContainer.ALIGNMENT_END
	box.minimum_size_changed.connect(_queue_relayout)
	_root.add_child(box)
	_boxes[anchor] = box
	return box


## The stack inside the holder of `rect` (the holder keeps exactly the mapped rect; content
## below a widget's min_rect overflows it).
func _slot_for(rect: Rect2i) -> VBoxContainer:
	for slot in _slots:
		if slot["rect"] == rect:
			return slot["stack"]
	var holder := Control.new()
	holder.name = "Rect_%d_%d_%d_%d" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stack := VBoxContainer.new()
	stack.name = "Stack"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 4)
	holder.add_child(stack)
	_root.add_child(holder)
	_slots.append({"rect": rect, "node": holder, "stack": stack})
	return stack


## Widest a toast or banner gets in a corner anchor: a third of the usable width, so corner
## messages wrap instead of running under (or squeezing) the centre stacks.
static func corner_text_width(ss: Vector2) -> float:
	return maxf(240.0, floorf((ss.x - 2.0 * WlTheme.MARGIN_PX - 2.0 * WlTheme.GAP_PX) / 3.0))


## Corner toasts and banners wrap within corner_text_width(); then the top and bottom centre
## stacks are kept between the corner stacks: teammate strips wrap and shrink, other kit
## widgets shrink, toast and banner text wraps.
func _fit_centers(ss: Vector2) -> void:
	var corner_w := corner_text_width(ss)
	for corner: String in [
		HudSpec.TOP_LEFT, HudSpec.TOP_RIGHT, HudSpec.BOTTOM_LEFT, HudSpec.BOTTOM_RIGHT
	]:
		if not _boxes.has(corner):
			continue
		for c in (_boxes[corner] as Control).get_children():
			if c is HudToasts:
				(c as HudToasts).set_max_width(corner_w)
			elif c is HudBanner:
				(c as HudBanner).set_max_width(corner_w)
	for center: String in [HudSpec.TOP, HudSpec.BOTTOM]:
		if not _boxes.has(center):
			continue
		var avail := center_width(center, ss)
		for c in (_boxes[center] as Control).get_children():
			if c is HudTeammates:
				(c as HudTeammates).set_max_width(avail)
			elif c is HudWidget:
				(c as HudWidget).fit_to(Vector2(avail, 100000.0))
			elif c is HudToasts:
				(c as HudToasts).set_max_width(avail)
			elif c is HudBanner:
				(c as HudBanner).set_max_width(avail)


func _fit_slot(node: VBoxContainer, avail: Vector2) -> void:
	var kit: Array[HudWidget] = []
	var others: Array[Control] = []
	for c in node.get_children():
		if c is HudWidget:
			kit.append(c)
		elif c is Control:
			others.append(c)
	if not kit.is_empty():
		var total_h := 0.0
		var max_w := 0.0
		for w in kit:
			total_h += w.base_size().y
			max_w = maxf(max_w, w.base_size().x)
		var sep := 4.0 * float(node.get_child_count() - 1)
		var s := 1.0
		if total_h > 0.0 and max_w > 0.0:
			s = minf(1.0, minf(avail.x / max_w, maxf(avail.y - sep, 1.0) / total_h))
		for w in kit:
			if w is HudTeammates:
				# The strip's share of the slot's height (all of it when it is alone).
				var share := maxf(avail.y - sep, 1.0) * w.base_size().y / maxf(total_h, 1.0)
				(w as HudTeammates).set_max_size(Vector2(avail.x, share))
			else:
				w.set_ui_scale(maxf(s, 0.25))
			w.size_flags_horizontal = Control.SIZE_FILL
	for c in others:
		if c is HudToasts:
			(c as HudToasts).fit_to(avail)
		elif c is HudBanner:
			(c as HudBanner).fit_to(avail)
		else:
			c.size_flags_horizontal = Control.SIZE_FILL
			c.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _queue_relayout() -> void:
	if _relayout_queued or not is_inside_tree():
		return
	_relayout_queued = true
	relayout.call_deferred()


## Follow the PixelViewport's `layout_changed` (world-kits emits it whenever the integer
## scale, the letterbox or the image rect change, also without a resize: a window whose
## stretch factor changes while the 1080p canvas keeps its size, a pixel_base change) and its
## `resized`. A relayout is queued once per frame, so both firing costs nothing.
func _set_pixel_viewport(pv: PixelViewport) -> void:
	if _pv != null and is_instance_valid(_pv):
		if _pv.resized.is_connected(_queue_relayout):
			_pv.resized.disconnect(_queue_relayout)
		if _pv.layout_changed.is_connected(_queue_relayout):
			_pv.layout_changed.disconnect(_queue_relayout)
	_pv = pv
	if _pv != null:
		if not _pv.resized.is_connected(_queue_relayout):
			_pv.resized.connect(_queue_relayout)
		if not _pv.layout_changed.is_connected(_queue_relayout):
			_pv.layout_changed.connect(_queue_relayout)


func _shows_power() -> bool:
	var power := false
	var pct := false
	for entry: Dictionary in _spec.widgets:
		var id := str(entry.get("widget", ""))
		if id == HudSpec.POWER_GAUGE:
			return true
		if id == HudSpec.READOUT:
			var opts: Variant = entry.get("options", {})
			var src := (
				str((opts as Dictionary).get("source", "power_w"))
				if opts is Dictionary
				else "power_w"
			)
			power = power or src == "power_w"
			pct = pct or src == "ftp_pct"
	return power and pct


func _read_rider_data() -> void:
	var prof := _profile()
	var slot: PlayerSlot = _ctx.local_player() if _ctx != null else null
	_ftp = slot.ftp if slot != null else (prof.ftp_w if prof != null else 200.0)
	_wprime = prof.wprime_j if prof != null else 20000.0
	_weight = 0.0
	if wkg_weight_kg >= 0.0:
		_weight = wkg_weight_kg
	elif prof != null:
		if prof.show_wkg:
			_weight = prof.weight_kg


func _profile() -> RiderProfile:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var s := tree.root.get_node_or_null("Settings") as WlSettings
	return s.profile if s != null else null


func _autoload_bus() -> WlEventBus:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("EventBus") as WlEventBus


## The TrainerService autoload's status() ("" when there is no such node or it has no
## status()). Read only for the app's own bus (_seed_trainer_notice).
func _trainer_status() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return ""
	var ts := tree.root.get_node_or_null("TrainerService")
	if ts == null or not ts.has_method("status"):
		return ""
	return str(ts.call("status"))


func _text(key: String, args: Variant) -> String:
	var a: Variant = args
	if a == null:
		a = []
	elif not (a is Array or a is Dictionary):
		a = [a]
	if _ctx != null and _ctx.strings != null:
		return _ctx.strings.t(key, a)
	return GameStrings.new().t(key, a)


func _refresh_safety() -> void:
	var rescue := _ext_rescue or _tele_rescue
	if rescue and not _rescue_shown:
		_play("rescue")
	_rescue_shown = rescue
	_banner.set_safety(_ext_warmup, rescue)
	_pause_badge.set_paused(_ext_paused or _tele_paused)


func _play(sound: String) -> void:
	if not sounds or not is_inside_tree():
		return
	var sfx := get_node_or_null("/root/Sfx") as WlSfx
	if sfx != null:
		sfx.play(sound, -4.0)


# --- bus ---------------------------------------------------------------------------------------


func _connect_bus() -> void:
	if _bus == null:
		return
	_link(_bus.power_band_changed, apply_power_band)
	_link(_bus.cadence_band_changed, apply_cadence_band)
	_link(_bus.roster_changed, set_roster)
	_link(_bus.toast_requested, _on_toast)
	_link(_bus.banner_requested, _on_banner)
	_link(_bus.readout_changed, set_readout)
	_link(_bus.rescue_changed, _on_rescue_changed)
	_link(_bus.phase_started, _on_phase_started)
	_link(_bus.paused_changed, _on_paused_changed)
	_link(_bus.governor_status, _on_governor_status)
	_link(_bus.trainer_control_lost, _on_trainer_control_lost)
	_link(_bus.trainer_status_changed, _on_trainer_status_changed)


func _link(sig: Signal, c: Callable) -> void:
	if not sig.is_connected(c):
		sig.connect(c)
	_bus_links.append({"signal": sig, "callable": c})


func _disconnect_bus() -> void:
	for l in _bus_links:
		var sig: Signal = l["signal"]
		var c: Callable = l["callable"]
		if sig.is_null() or not is_instance_valid(sig.get_object()):
			continue
		if sig.is_connected(c):
			sig.disconnect(c)
	_bus_links.clear()


func _on_toast(key: String, args: Variant) -> void:
	show_toast(key, args)


func _on_banner(key: String, args: Variant, seconds: float) -> void:
	show_banner(key, args, seconds)


func _on_rescue_changed(peer: int, active: bool) -> void:
	if peer == _local_peer:
		_ext_rescue = active
		_refresh_safety()


func _on_phase_started(peer: int, _index: int) -> void:
	if peer == _local_peer:
		_play("phase")


func _on_paused_changed(paused: bool, _reason: String) -> void:
	_ext_paused = paused
	_refresh_safety()


func _on_governor_status(peer: int, status: Dictionary) -> void:
	if peer != _local_peer:
		return
	if status.has("warmup"):
		_ext_warmup = bool(status["warmup"])
	if status.has("rescue"):
		_ext_rescue = bool(status["rescue"])
	if status.has("paused"):
		_ext_paused = bool(status["paused"])
	_refresh_safety()


## Another app (Zwift, the Wahoo app) may hold control (BRIEF 4.4): one notice and one sound
## per loss; a repeat while control is still lost changes nothing.
func _on_trainer_control_lost(_detail: String) -> void:
	if _control_lost:
		return
	_control_lost = true
	_banner.set_trainer_notice(_text("TRAINER_ANOTHER_APP_CONTROL", []))
	_play("warning")


## A loss before this layer linked the bus (lobby, an earlier session) emitted no signal here:
## on the autoload EventBus, which TrainerService emits on, its current status stands in for
## it. A private bus (a test, an in-process sim) is not this machine's trainer.
func _seed_trainer_notice() -> void:
	if _bus == null or _bus != _autoload_bus():
		return
	if _trainer_status() == TrainerDevice.STATUS_CONTROL_LOST:
		_on_trainer_control_lost("")


## Control is back once the trainer is ready again (a retry, a reconnect, another trainer).
func _on_trainer_status_changed(status: String, _detail: String) -> void:
	if not _control_lost or status != TrainerDevice.STATUS_READY:
		return
	_control_lost = false
	_banner.set_trainer_notice("")
