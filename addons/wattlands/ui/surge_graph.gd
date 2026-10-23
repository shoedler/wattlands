class_name WlSurgeGraph
extends Control
## Surge feedback for pedal navigation (BRIEF 3.5): the last WINDOW_S seconds of the local
## rider's power as a line, and a horizontal line at the power a surge needs right now
## (GestureRecognizer.surge_threshold_w()), so the rider sees how hard to pedal to pick.
## Shown only while `enabled` (the owner sets it from pedal navigation being on), a rider is
## attached and its trainer is not in ERG (inside ERG power is held and the surge reads
## flywheel speed). Owned by ui-hud.
## The rider is `rider`, else the router's attached rider; power is read SAMPLE_S apart from
## _process (real_time) or through tick(dt) in headless tests. Colors and text size come from
## WlTheme.

const WINDOW_S := 5.0
## Seconds between samples: 10 Hz, well above the 1 Hz the surge rule sees.
const SAMPLE_S := 0.1
const MIN_SCALE_W := 150.0
const PAD_PX := 12.0

## Draw the graph (the owner turns it on with pedal navigation).
var enabled: bool = true:
	set(value):
		enabled = value
		_refresh_visibility()
var real_time: bool = true
## The rider to read; null means the router's attached rider.
var rider: LocalRider = null
## The router whose attached rider is read when `rider` is null; null means the InputRouter
## autoload.
var router: WlInputRouter = null
## Latest power in W (0 without a rider) and the surge threshold in W (-1 while unknown).
var power_w: float = 0.0
var threshold_w: float = -1.0

var _samples: PackedFloat32Array = PackedFloat32Array()
var _clock: float = 0.0
var _in_erg: bool = false
var _has_rider: bool = false


func _init() -> void:
	name = "SurgeGraph"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, 132.0)
	_refresh_visibility()


func _process(delta: float) -> void:
	if real_time and enabled:
		tick(delta)


## Advance by dt seconds: samples the rider every SAMPLE_S and redraws.
func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	_read_source()
	_clock += dt
	var n := 0
	while _clock >= SAMPLE_S - 1e-6 and n < 100:
		_clock -= SAMPLE_S
		_push(power_w)
		n += 1
	queue_redraw()


## Add one power sample by hand (tests, a game that has no LocalRider) and set the threshold.
func push_sample(p_power_w: float, p_threshold_w: float = -1.0) -> void:
	power_w = p_power_w
	threshold_w = p_threshold_w
	_push(p_power_w)
	queue_redraw()


## The power samples of the window, oldest first.
func samples() -> PackedFloat32Array:
	return _samples


func clear() -> void:
	_samples = PackedFloat32Array()
	_clock = 0.0
	queue_redraw()


## True while the graph is on screen: enabled, a rider attached, not in ERG.
func shows_graph() -> bool:
	return enabled and _has_rider and not _in_erg


## The y range top in W: room for the threshold line and the highest sample.
func scale_max_w() -> float:
	var top := maxf(MIN_SCALE_W, threshold_w * 1.15)
	for v in _samples:
		top = maxf(top, v * 1.1)
	return top


func _read_source() -> void:
	var r := rider
	if r == null:
		var rt := router
		if rt == null and is_inside_tree():
			rt = get_node_or_null("/root/InputRouter") as WlInputRouter
		if rt != null:
			r = rt.attached_rider()
	_has_rider = r != null and is_instance_valid(r)
	if _has_rider:
		var t := r.telemetry()
		power_w = t.power_w
		_in_erg = t.mode == Wl.ERG
		threshold_w = r.gestures.surge_threshold_w() if r.gestures != null else -1.0
	else:
		power_w = 0.0
		threshold_w = -1.0
	_refresh_visibility()


func _refresh_visibility() -> void:
	visible = shows_graph()


func _push(v: float) -> void:
	_samples.append(v)
	var cap := roundi(WINDOW_S / SAMPLE_S)
	if _samples.size() > cap:
		_samples = _samples.slice(_samples.size() - cap)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	WlTheme.panel_style().draw(get_canvas_item(), rect)
	var font := WlTheme.font()
	var px := WlTheme.SMALL_PX
	var plot := Rect2(
		Vector2(PAD_PX, PAD_PX + px + 4.0), size - Vector2(PAD_PX * 2.0, PAD_PX * 2.0 + px + 4.0)
	)
	if plot.size.x <= 0.0 or plot.size.y <= 0.0:
		return
	var top := scale_max_w()
	var armed := threshold_w >= 0.0
	var title := (
		tr("UI_SURGE_GRAPH_NOW").format([roundi(threshold_w)])
		if armed
		else tr("UI_SURGE_GRAPH_WAIT")
	)
	draw_string(
		font,
		Vector2(PAD_PX, PAD_PX + px),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		size.x - PAD_PX * 2.0,
		px,
		WlTheme.TEXT_DIM
	)
	draw_rect(plot, WlTheme.BAR_BG, true)
	if armed:
		var y := plot.position.y + plot.size.y * (1.0 - clampf(threshold_w / top, 0.0, 1.0))
		draw_dashed_line(
			Vector2(plot.position.x, y), Vector2(plot.end.x, y), WlTheme.WARN, 3.0, 10.0
		)
	var n := _samples.size()
	if n < 2:
		return
	var step := plot.size.x / float(roundi(WINDOW_S / SAMPLE_S) - 1)
	var x0 := plot.end.x - step * float(n - 1)
	var pts := PackedVector2Array()
	for i in n:
		var v := clampf(_samples[i] / top, 0.0, 1.0)
		pts.append(Vector2(x0 + step * float(i), plot.position.y + plot.size.y * (1.0 - v)))
	var over := armed and power_w >= threshold_w
	draw_polyline(pts, WlTheme.GLOW if over else WlTheme.ACCENT, 4.0 if over else 3.0, true)
