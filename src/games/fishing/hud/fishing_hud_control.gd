class_name FishingHudControl
extends Control
## Base of Fishing's own HUD Controls: each sits alone in a Rect2i of the HudSpec (`art_rect`,
## art px of the current art size), so the HUD sizes it to that rect mapped to the screen (art
## px x 3 at 1080p); it fills it, ignores the mouse, refreshes its model every frame and draws
## scaled to its size (`k()` = 1 at 1080p, `ap()` HUD px per art px). The HudLayer hands it the
## local rider's telemetry every tick (set_telemetry; `tm` stays null without a HUD, and then
## the rider state stands in).

## The rect's height in 1080p canvas px at scale 3 (set by each subclass).
var design_h: float = 72.0
var game: FishingGame = null
## The rect the spec placed it in (art px).
var art_rect: Rect2i = Rect2i(0, 0, FishingScenery.W, FishingScenery.H)
## The local rider's latest telemetry (null until the HUD sends one).
var tm: Telemetry = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	theme = WlTheme.get_theme()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(_delta: float) -> void:
	refresh()
	queue_redraw()


## The HudLayer's per-tick local telemetry (heart rate included).
func set_telemetry(t: Telemetry) -> void:
	tm = t


## Sets the rect the spec places the control in (art px) and its design height.
func place_at(rect: Rect2i) -> void:
	art_rect = rect
	design_h = float(rect.size.y * 3)


## Recomputes what the Control shows (subclasses).
func refresh() -> void:
	pass


## Draw scale: the Control's height over its design height (1 at 1080p).
func k() -> float:
	return size.y / design_h if size.y > 0.0 else 1.0


## HUD px per art px (3 at 1080p).
func ap() -> float:
	if size.x <= 0.0 or art_rect.size.x <= 0:
		return 3.0
	return size.x / float(art_rect.size.x)


func px(base: int) -> int:
	return maxi(roundi(float(base) * k()), WlTheme.MIN_TEXT_PX)


## The view (null before it exists).
func view() -> FishingView:
	if game == null or not game.has_meta(FishingView.META):
		return null
	var v: Variant = game.get_meta(FishingView.META)
	return v as FishingView if v is FishingView else null


## The local rider's power (W), cadence (rpm), %FTP, heart rate (bpm, 0 without a sensor), the
## applied ERG target (W) (the telemetry when there is one, else the rider state) and the game
## time (s; the graphs' clock).
func local_numbers(r: FishingRiderState) -> Dictionary:
	var t := game.state.t if game != null and game.state != null else 0.0
	if tm != null:
		var pct := tm.ftp_pct
		if pct <= 0.0 and r != null and r.ftp > 0.0:
			pct = 100.0 * tm.power_w / r.ftp
		var target := float(tm.applied_target_w)
		if target <= 0.0 and r != null:
			target = r.applied_target_w
		return {
			"power": tm.power_w,
			"cadence": tm.cadence_rpm,
			"pct": pct,
			"hr": tm.heart_rate_bpm,
			"target": target,
			"t": t,
		}
	if r == null:
		return {"power": 0.0, "cadence": 0.0, "pct": 0.0, "hr": 0, "target": 0.0, "t": t}
	return {
		"power": r.power_w,
		"cadence": r.cadence_ema,
		"pct": 100.0 * r.power_w / r.ftp if r.ftp > 0.0 else 0.0,
		"hr": 0,
		"target": r.applied_target_w,
		"t": t,
	}
