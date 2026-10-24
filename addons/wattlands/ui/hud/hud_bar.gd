class_name HudBar
extends Control
## A horizontal gauge bar for the HUD kit: background, an optional target band, the value
## fill, an optional target marker, and a glow (bright outline and band) while the value is
## in the band. The glow is a brightness change plus an outline, so it reads without color.
## A palette's band, glow and bar_fg keys recolor the band (flat, without edge lines), the glow
## outline and the lit gear ticks (unlit ticks then take bar_bg on the panel); with grid_px the
## whole bar is drawn in the game's pixels and the gear ticks become one solid fill (HudPalette).
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
## The game's colors (HudWidget.set_palette): bar_bg, bar_fg, accent, text.
var palette: HudPalette = HudPalette.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Use `p` for the background, fill, band and marker colors (null = the kit look).
func set_palette(p: HudPalette) -> void:
	palette = p if p != null else HudPalette.new()
	fill_color = palette.pick(HudPalette.BAR_FG, WlTheme.BAR_FILL)
	update_minimum_size()
	queue_redraw()


## The gear bar on the grid shows every gear as at least one whole pixel (grid_px).
func _get_minimum_size() -> Vector2:
	var grid := palette.grid_px()
	if segments > 0 and grid > 0:
		return Vector2(float(segments * grid), 4.0 * grid)
	return Vector2.ZERO


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
	var bg := palette.pick(HudPalette.BAR_BG, WlTheme.BAR_BG)
	var accent := palette.pick(HudPalette.ACCENT, WlTheme.ACCENT)
	var tick_colors := palette.has_key(HudPalette.BAR_FG)
	var grid := palette.grid_px()
	if grid > 0 and segments == 0:
		_draw_grid(grid, a)
		return
	if segments > 0 and grid > 0:
		var gw := floorf(r.size.x / grid) * grid
		var top := floorf((r.size.y - 4.0 * grid) / 2.0 / grid) * grid
		var fw := HudPalette.snap(frac(value) * gw, grid)
		draw_rect(Rect2(0.0, top, gw, 4.0 * grid), Color(bg, bg.a * a))
		var on := palette.pick(HudPalette.BAR_FG, accent)
		draw_rect(Rect2(0.0, top, fw, 4.0 * grid), Color(on, on.a * a))
		return
	if segments == 0 or not tick_colors:
		draw_rect(r, Color(bg, bg.a * a))
	if segments > 0:
		var seg_w := r.size.x / float(segments)
		var lit := roundi(frac(value) * segments)
		var on := palette.pick(HudPalette.BAR_FG, accent)
		var off := bg if tick_colors else Color(1, 1, 1, 0.18)
		for i in segments:
			var sr := Rect2(
				r.position.x + i * seg_w + 1.0, r.position.y, maxf(1.0, seg_w - 2.0), r.size.y
			)
			var c := on if i < lit else off
			draw_rect(sr, Color(c, c.a * a))
		return
	if has_band():
		var x0 := frac(band_lo) * r.size.x
		var x1 := frac(band_hi) * r.size.x
		var bc := WlTheme.BAND_IN if glow else WlTheme.BAND
		if palette.has_key(HudPalette.BAND):
			bc = palette.pick(HudPalette.BAND, bc)
		elif palette.has_key(HudPalette.ACCENT):
			bc = Color(accent.lightened(0.5) if glow else accent, bc.a)
		draw_rect(Rect2(x0, 0.0, maxf(2.0, x1 - x0), r.size.y), Color(bc, bc.a * a))
		if not palette.has_key(HudPalette.BAND):
			draw_line(Vector2(x0, 0.0), Vector2(x0, r.size.y), Color(accent, a), 2.0)
			draw_line(Vector2(x1, 0.0), Vector2(x1, r.size.y), Color(accent, a), 2.0)
	var fw := frac(value) * r.size.x
	var inset := r.size.y * 0.25
	draw_rect(Rect2(0.0, inset, fw, r.size.y - 2.0 * inset), Color(fill_color, fill_color.a * a))
	if marker >= 0.0:
		var mx := frac(marker) * r.size.x
		draw_line(
			Vector2(mx, -2.0),
			Vector2(mx, r.size.y + 2.0),
			Color(palette.pick(HudPalette.TEXT, WlTheme.TEXT), a),
			4.0
		)
	if glow:
		draw_rect(r.grow(2.0), palette.pick(HudPalette.GLOW, WlTheme.GLOW), false, 4.0)


## The bar on the game's pixel grid (grid_px): a track whole pixels tall, the band and the fill
## in whole pixels (the fill one pixel in from the track's top and bottom when it is at least
## four tall), a one-pixel target marker and, in band, a one-pixel glow frame on the track.
func _draw_grid(g: int, a: float) -> void:
	var gf := float(g)
	var w := floorf(size.x / gf) * gf
	var h := floorf(size.y / gf) * gf
	if w <= 0.0 or h <= 0.0:
		return
	var bg := palette.pick(HudPalette.BAR_BG, WlTheme.BAR_BG)
	draw_rect(Rect2(0.0, 0.0, w, h), Color(bg, bg.a * a))
	if has_band():
		var x0 := HudPalette.snap(frac(band_lo) * w, g)
		var x1 := maxf(x0 + gf, HudPalette.snap(frac(band_hi) * w, g))
		var bc := palette.pick(HudPalette.BAND, palette.pick(HudPalette.ACCENT, WlTheme.BAND))
		draw_rect(Rect2(x0, 0.0, x1 - x0, h), Color(bc, bc.a * a))
	var inset := gf if h >= 4.0 * gf else 0.0
	var fw := HudPalette.snap(frac(value) * w, g)
	draw_rect(Rect2(0.0, inset, fw, h - 2.0 * inset), Color(fill_color, fill_color.a * a))
	if marker >= 0.0:
		var mx := minf(HudPalette.snap(frac(marker) * w, g), w - gf)
		var mc := palette.pick(HudPalette.TEXT, WlTheme.TEXT)
		draw_rect(Rect2(mx, 0.0, gf, h), Color(mc, mc.a * a))
	if glow:
		var gc := palette.pick(HudPalette.GLOW, WlTheme.GLOW)
		for edge in [
			Rect2(0.0, 0.0, w, gf),
			Rect2(0.0, h - gf, w, gf),
			Rect2(0.0, 0.0, gf, h),
			Rect2(w - gf, 0.0, gf, h)
		]:
			draw_rect(edge, gc)
