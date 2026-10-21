class_name HudBar
extends Control
## A horizontal gauge bar for the HUD kit: background, an optional target band, the value
## fill, an optional target marker, and a glow (bright outline and band) while the value is
## in the band. The glow is a brightness change plus an outline, so it reads without color.
## Owned by ui-hud.

var max_value: float = 1.0
var value: float = 0.0
## The band [band_lo, band_hi]; no band while band_hi <= band_lo.
var band_lo: float = 0.0
var band_hi: float = 0.0
## A target marker (< 0: none).
var marker: float = -1.0
var glow: bool = false
## Dim everything (stale data).
var dim: bool = false
var fill_color: Color = WlTheme.BAR_FILL
## Draw tick segments (the gear indicator); 0 = none.
var segments: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(
	p_value: float,
	p_max: float,
	p_band_lo: float = 0.0,
	p_band_hi: float = 0.0,
	p_marker: float = -1.0,
	p_glow: bool = false
) -> void:
	value = p_value
	max_value = maxf(p_max, 1e-6)
	band_lo = p_band_lo
	band_hi = p_band_hi
	marker = p_marker
	glow = p_glow
	queue_redraw()


func has_band() -> bool:
	return band_hi > band_lo


func frac(v: float) -> float:
	return clampf(v / maxf(max_value, 1e-6), 0.0, 1.0)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var a := 0.45 if dim else 1.0
	draw_rect(r, Color(WlTheme.BAR_BG, WlTheme.BAR_BG.a * a))
	if segments > 0:
		var seg_w := r.size.x / float(segments)
		var lit := roundi(frac(value) * segments)
		for i in segments:
			var sr := Rect2(
				r.position.x + i * seg_w + 1.0, r.position.y, maxf(1.0, seg_w - 2.0), r.size.y
			)
			var c := WlTheme.ACCENT if i < lit else Color(1, 1, 1, 0.18)
			draw_rect(sr, Color(c, c.a * a))
		return
	if has_band():
		var x0 := frac(band_lo) * r.size.x
		var x1 := frac(band_hi) * r.size.x
		var bc := WlTheme.BAND_IN if glow else WlTheme.BAND
		draw_rect(Rect2(x0, 0.0, maxf(2.0, x1 - x0), r.size.y), Color(bc, bc.a * a))
		draw_line(Vector2(x0, 0.0), Vector2(x0, r.size.y), Color(WlTheme.ACCENT, a), 2.0)
		draw_line(Vector2(x1, 0.0), Vector2(x1, r.size.y), Color(WlTheme.ACCENT, a), 2.0)
	var fw := frac(value) * r.size.x
	var inset := r.size.y * 0.25
	draw_rect(Rect2(0.0, inset, fw, r.size.y - 2.0 * inset), Color(fill_color, fill_color.a * a))
	if marker >= 0.0:
		var mx := frac(marker) * r.size.x
		draw_line(Vector2(mx, -2.0), Vector2(mx, r.size.y + 2.0), Color(WlTheme.TEXT, a), 4.0)
	if glow:
		draw_rect(r.grow(2.0), WlTheme.GLOW, false, 4.0)
