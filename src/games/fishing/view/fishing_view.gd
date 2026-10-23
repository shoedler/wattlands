class_name FishingView
extends Node2D
## The 640 x 360 view (brief 3.5): the deck bar's planks (the HUD draws the deck bar's text on
## top) plus one FishingLaneView per slot, lane order = slot order from the top, and an overlay
## for the gold Double Hookup link between lanes. It only reads `game.state`; on clients the
## other lanes are drawn between snapshots from `game.history` with a render clock behind the
## newest snapshot by the history's mean spacing (Workout's pattern, GAME_SDK 12), never past
## the newest and never backwards; the local lane uses the state directly (its cadence is
## predicted by the module). Effects and sounds come from FishingCues: the module's fx_event
## signal when it has one, else edges in the state. FishingAudio is a child.

const INTERP_DELAY_S := 0.1
const CLOCK_RESYNC_S := 1.5
const INTERP_DELAY_MAX_S := CLOCK_RESYNC_S - 0.1
const CLOCK_CATCHUP_TAU_S := 0.25
const LINK_S := 1.6

var game: FishingGame = null
var lanes: Array[FishingLaneView] = []
var cues: FishingCues = FishingCues.new()
var audio: FishingAudio = null
## Client: the host time (s) other lanes are drawn at.
var render_t: float = 0.0
## True when cues come from the module's fx_event signal.
var events_connected: bool = false
## Every cue handled so far this session, newest last (tests read and clear it; capped).
var cue_log: Array[Dictionary] = []

var _overlay: FishingDrawLayer = null
var _pending: Array[Dictionary] = []
var _clock_set: bool = false
var _built: bool = false
var _local_slot: int = -1
var _applied_cos: Array[PackedInt32Array] = []
var _link_lanes: Array = []
var _link_t: float = -1.0


func _ready() -> void:
	name = "FishingView"
	_build()


func _process(delta: float) -> void:
	advance(delta)


## One frame of `delta` seconds: builds the lanes once the state exists, moves the client's
## render clock, feeds every lane its shown values and hands out the cues.
func advance(delta: float) -> void:
	if not _built:
		_build()
	if not _built:
		return
	var st := game.state
	if _is_client():
		_advance_clock(delta)
	for lv in lanes:
		var l := st.lane(lv.slot)
		lv.lane = l
		if l == null:
			continue
		_check_cosmetics(lv, l)
		lv.game_t = st.t
		lv.total_s = st.trip_total_s
		if _is_client() and lv.slot != _local_slot and _clock_set:
			lv.shown_d = game.history.value_at(lv.slot, "d", render_t, l.fish.d)
			lv.shown_z = game.history.value_at(lv.slot, "z", render_t, l.fish.z)
			lv.shown_cad = game.history.value_at(lv.slot, "cad", render_t, l.cadence_ema)
			lv.shown_w = game.history.value_at(lv.slot, "w", render_t, l.power_w)
		else:
			lv.shown_d = l.fish.d
			lv.shown_z = l.fish.z
			lv.shown_cad = l.cadence_ema
			lv.shown_w = l.power_w
		lv.advance(delta)
	if not events_connected:
		for c in cues.diff(st):
			_pending.append(c)
	for c in _pending:
		_handle(c)
	_pending.clear()
	if _link_t >= 0.0:
		_link_t = _link_t + delta if _link_t + delta < LINK_S else -1.0
	_overlay.queue_redraw()
	if audio != null:
		var local := st.lane(_local_slot)
		var lv_local := lane_view(_local_slot)
		audio.update(delta, local, lv_local.line_mps if lv_local != null else 0.0)
	queue_redraw()


## The lane view of `slot` (null when there is none).
func lane_view(slot: int) -> FishingLaneView:
	for lv in lanes:
		if lv.slot == slot:
			return lv
	return null


## The local rider's slot (-1 when the local peer rides no lane).
func local_slot() -> int:
	return _local_slot


## Client: how far render_t runs behind the newest snapshot: the history's mean spacing,
## clamped to INTERP_DELAY_S..INTERP_DELAY_MAX_S.
func interp_delay() -> float:
	var spacing := game.history.mean_spacing() if game != null and game.history != null else 0.0
	return clampf(spacing, INTERP_DELAY_S, INTERP_DELAY_MAX_S)


## The module's fx_event handler: queues the event's cues for the next frame.
func on_fx_event(event: Dictionary) -> void:
	for c in cues.from_event(event):
		_pending.append(c)


func _is_client() -> bool:
	return game != null and game.ctx != null and game.ctx.role == Wl.CLIENT


func _build() -> void:
	if _built or game == null or game.state == null or game.ctx == null:
		return
	_built = true
	cues.use_content(game.content)
	if game.has_signal("fx_event"):
		game.connect("fx_event", on_fx_event)
		events_connected = true
	var n := game.state.lanes.size()
	_local_slot = -1
	for l in game.state.lanes:
		if l.peer == game.ctx.local_peer:
			_local_slot = l.slot
	for l in game.state.lanes:
		var lv := FishingLaneView.new()
		lv.configure_lane(
			l.slot, n, l.slot == _local_slot, _look(l.slot), game.content, game.ctx.seed
		)
		lanes.append(lv)
		_applied_cos.append(PackedInt32Array([0, 0, 0, 0]))
		add_child(lv)
	_overlay = FishingDrawLayer.make("Overlay", _paint_overlay)
	add_child(_overlay)
	audio = FishingAudio.new()
	add_child(audio)


func _look(slot: int) -> Dictionary:
	var look := Wl.slot_look(slot)
	if slot >= 0 and slot < game.ctx.players.size():
		var p := game.ctx.players[slot]
		look = {"color": p.color, "shape": p.shape, "pattern": p.pattern, "hollow": p.hollow}
	return look


func _check_cosmetics(lv: FishingLaneView, l: FishingLaneState) -> void:
	var k := lanes.find(lv)
	var applied := _applied_cos[k]
	var same := true
	for i in 4:
		var want := l.cosmetics[i] if i < l.cosmetics.size() else 0
		if applied[i] != want:
			same = false
			applied[i] = want
	if not same:
		_applied_cos[k] = applied
		var idx: Array[int] = []
		for i in 4:
			idx.append(applied[i])
		lv.set_cosmetics(idx)


## render_t moves with the frame clock, catches up softly toward newest - interp_delay(), and
## stops at the newest snapshot; it never runs backwards except by a resync jump.
func _advance_clock(delta: float) -> void:
	var history := game.history
	if history == null or history.is_empty():
		return
	var newest := history.newest_t()
	var goal := newest - interp_delay()
	if not _clock_set or absf(goal - render_t) > CLOCK_RESYNC_S:
		render_t = goal
		_clock_set = true
		return
	render_t += maxf(delta, 0.0)
	var behind := goal - render_t
	if behind > 0.0:
		render_t += behind * (1.0 - exp(-maxf(delta, 0.0) / CLOCK_CATCHUP_TAU_S))
	render_t = minf(render_t, newest)


func _handle(c: Dictionary) -> void:
	cue_log.append(c)
	if cue_log.size() > 64:
		cue_log.pop_front()
	var l := int(c.get("l", -1))
	var lv := lane_view(l)
	if lv != null:
		lv.on_cue(c)
	if str(c.get("k", "")) == FishingCues.CUE_DOUBLE_HOOKUP:
		_link_lanes = (c.get("lanes", []) as Array).duplicate()
		_link_t = 0.0
	if audio != null:
		audio.cue(c, l == _local_slot)


func _draw() -> void:
	draw_texture(FishingPalette.deck_texture(), Vector2.ZERO)


## The gold Double Hookup link: a dashed gold line joining the linked lanes' rod tips and a
## gold box round each boat, blinking for LINK_S.
func _paint_overlay(c: CanvasItem) -> void:
	if _link_t < 0.0 or _link_lanes.size() < 2 or floori(_link_t * 6.0) % 2 == 1:
		return
	var ys: Array[float] = []
	for s: Variant in _link_lanes:
		var lv := lane_view(int(s))
		if lv == null:
			continue
		var tip: Vector2 = lv.position + lv.boat.position + FishingRig.ROD_TIP
		ys.append(tip.y)
		c.draw_rect(
			Rect2(lv.position + lv.boat.position - Vector2(2, 6), Vector2(84, 40)),
			FishingPalette.GOLD,
			false,
			1.0
		)
	if ys.size() < 2:
		return
	ys.sort()
	var x := float(FishingConst.ROD_TIP_X) + 0.5
	var y := ys[0]
	while y < ys[-1]:
		c.draw_line(Vector2(x, y), Vector2(x, minf(y + 3.0, ys[-1])), FishingPalette.GOLD, 1.0)
		y += 5.0


## Polygon of a slot shape (circle, triangle, square, diamond) round `center`, radius `r`.
static func shape_points(shape: String, center: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match shape:
		"triangle":
			pts.append(center + Vector2(0, -r))
			pts.append(center + Vector2(r, r))
			pts.append(center + Vector2(-r, r))
		"square":
			pts.append(center + Vector2(-r, -r))
			pts.append(center + Vector2(r, -r))
			pts.append(center + Vector2(r, r))
			pts.append(center + Vector2(-r, r))
		"diamond":
			pts.append(center + Vector2(0, -r))
			pts.append(center + Vector2(r, 0))
			pts.append(center + Vector2(0, r))
			pts.append(center + Vector2(-r, 0))
		_:
			for i in 8:
				var a := TAU * float(i) / 8.0
				pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts


## A frame `width` px wide inside `r` in `col` and a slot pattern: solid, dashed, dotted or
## double (two 1 px lines with a gap), so the colour never stands alone.
static func draw_pattern_frame(
	c: CanvasItem, r: Rect2, col: Color, pattern: String, width: int
) -> void:
	var w := float(width)
	match pattern:
		"double":
			for k: float in [0.0, w - 1.0]:
				var rr := r.grow(-k)
				c.draw_rect(Rect2(rr.position, Vector2(rr.size.x, 1)), col)
				c.draw_rect(Rect2(rr.position.x, rr.end.y - 1, rr.size.x, 1), col)
				c.draw_rect(Rect2(rr.position, Vector2(1, rr.size.y)), col)
				c.draw_rect(Rect2(rr.end.x - 1, rr.position.y, 1, rr.size.y), col)
		"dashed", "dotted":
			var on := 6.0 if pattern == "dashed" else w
			var period := on + (3.0 if pattern == "dashed" else w)
			var x := r.position.x
			while x < r.end.x:
				var seg := minf(on, r.end.x - x)
				c.draw_rect(Rect2(x, r.position.y, seg, w), col)
				c.draw_rect(Rect2(x, r.end.y - w, seg, w), col)
				x += period
			var y := r.position.y
			while y < r.end.y:
				var seg2 := minf(on, r.end.y - y)
				c.draw_rect(Rect2(r.position.x, y, w, seg2), col)
				c.draw_rect(Rect2(r.end.x - w, y, w, seg2), col)
				y += period
		_:
			c.draw_rect(Rect2(r.position, Vector2(r.size.x, w)), col)
			c.draw_rect(Rect2(r.position.x, r.end.y - w, r.size.x, w), col)
			c.draw_rect(Rect2(r.position, Vector2(w, r.size.y)), col)
			c.draw_rect(Rect2(r.end.x - w, r.position.y, w, r.size.y), col)


## Navy or white, whichever reads on `bg`.
static func text_on(bg: Color) -> Color:
	return FishingPalette.NAVY if bg.get_luminance() > 0.45 else FishingPalette.WHITE
