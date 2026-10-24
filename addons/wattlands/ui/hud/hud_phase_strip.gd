class_name HudPhaseStrip
extends Control
## The block strip of the phase timeline: one block per plan phase, width by length, height
## by intensity (ERG peak %FTP; SIM phases at 75% with diagonal hatching, so mode reads
## without color), the current block outlined and a progress marker. With a palette's grid_px
## everything is drawn in the game's whole pixels (the hatching as pixel diagonals). Owned by
## ui-hud. A palette's strip_low, strip_mid and strip_high draw the blocks in flat intensity
## colours instead of the kind colours (HudPalette).

## [{"len": float, "kind": String, "mode": String, "pct": float}]
var blocks: Array[Dictionary] = []
var current: int = -1
## 0..1 through the current block.
var progress: float = 0.0
## The game's colors (HudWidget.set_palette): bar_bg, accent (work blocks), text.
var palette: HudPalette = HudPalette.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Use `p` for the background, the work blocks and the current-block outline (null = the kit
## look). Warm-up, free and recovery colors stay.
func set_palette(p: HudPalette) -> void:
	palette = p if p != null else HudPalette.new()
	queue_redraw()


func set_blocks(p_blocks: Array[Dictionary], p_current: int, p_progress: float) -> void:
	blocks = p_blocks
	current = p_current
	progress = clampf(p_progress, 0.0, 1.0)
	queue_redraw()


func total_length() -> float:
	var t := 0.0
	for b in blocks:
		t += float(b.get("len", 0.0))
	return t


## True when the palette sets the strip's intensity colours (strip_low, strip_mid, strip_high).
func has_levels() -> bool:
	return (
		palette.has_key(HudPalette.STRIP_LOW)
		or palette.has_key(HudPalette.STRIP_MID)
		or palette.has_key(HudPalette.STRIP_HIGH)
	)


## The palette's flat colour for a block at `pct` %FTP: low under 60, mid under 90, else high.
func level_color(pct: float) -> Color:
	var mid := palette.pick(HudPalette.STRIP_MID, WlTheme.TEXT_DIM)
	if pct < 60.0:
		return palette.pick(HudPalette.STRIP_LOW, mid)
	if pct < 90.0:
		return mid
	return palette.pick(HudPalette.STRIP_HIGH, mid)


## Color per phase kind (always paired with height and hatching).
static func kind_color(kind: String) -> Color:
	match kind:
		Wl.WARMUP:
			return WlTheme.WARMUP
		Wl.WORK:
			return WlTheme.ACCENT
		Wl.RECOVERY:
			return Color("#7F8C99")
		Wl.FREE:
			return WlTheme.WARN
		Wl.COOLDOWN:
			return Color("#6C7A89")
	return WlTheme.TEXT_DIM


func _draw() -> void:
	var w := size.x
	var h := size.y
	var total := total_length()
	if w <= 0.0 or h <= 0.0 or total <= 0.0:
		return
	if palette.grid_px() > 0:
		_draw_grid(palette.grid_px(), total)
		return
	var flat := has_levels()
	if not flat:
		draw_rect(Rect2(0, 0, w, h), palette.pick(HudPalette.BAR_BG, WlTheme.BAR_BG))
	var x := 0.0
	for i in blocks.size():
		var b := blocks[i]
		var bw := float(b.get("len", 0.0)) / total * w
		var pct := float(b.get("pct", 50.0))
		var sim := str(b.get("mode", Wl.ERG)) == Wl.SIM
		if sim:
			pct = 75.0
		var bh := clampf(pct / 150.0, 0.2, 1.0) * h
		var rect := Rect2(x + 1.0, h - bh, maxf(1.0, bw - 2.0), bh)
		var kind := str(b.get("kind", ""))
		var c := level_color(pct) if flat else kind_color(kind)
		if kind == Wl.WORK and not flat:
			c = palette.pick(HudPalette.ACCENT, c)
		if not flat and i < current:
			c = Color(c, 0.35)
		elif not flat and i > current:
			c = Color(c, 0.7)
		draw_rect(rect, c)
		if sim:
			var step := maxf(6.0, h * 0.3)
			var sx := rect.position.x - h
			while sx < rect.end.x:
				var a := Vector2(
					maxf(sx, rect.position.x), rect.end.y - maxf(0.0, rect.position.x - sx)
				)
				var bpt := Vector2(
					minf(sx + bh, rect.end.x), rect.end.y - minf(bh, rect.end.x - sx)
				)
				if bpt.x > a.x:
					draw_line(
						a,
						bpt,
						(
							palette.pick(HudPalette.PANEL, Color(0, 0, 0))
							if flat
							else Color(0, 0, 0, 0.45)
						),
						2.0
					)
				sx += step
		if i == current:
			draw_rect(rect.grow(1.0), palette.pick(HudPalette.TEXT, WlTheme.TEXT), false, 3.0)
			var mx := rect.position.x + rect.size.x * progress
			draw_line(
				Vector2(mx, 0.0), Vector2(mx, h), palette.pick(HudPalette.GLOW, WlTheme.GLOW), 3.0
			)
		x += bw


## The strip on the game's pixel grid: block edges, heights, the hatching, the outline and the
## marker in whole pixels of `g`.
func _draw_grid(g: int, total: float) -> void:
	var gf := float(g)
	var w := floorf(size.x / gf) * gf
	var h := floorf(size.y / gf) * gf
	var bg := palette.pick(HudPalette.BAR_BG, WlTheme.BAR_BG)
	var flat := has_levels()
	if not flat:
		draw_rect(Rect2(0, 0, w, h), bg)
	var at := 0.0
	for i in blocks.size():
		var b := blocks[i]
		var x0 := HudPalette.snap(at / total * w, g)
		at += float(b.get("len", 0.0))
		var x1 := HudPalette.snap(at / total * w, g)
		if x1 - x0 >= 2.0 * gf:
			x1 -= gf
		if x1 <= x0:
			continue
		var sim := str(b.get("mode", Wl.ERG)) == Wl.SIM
		var pct := 75.0 if sim else float(b.get("pct", 50.0))
		var bh := maxf(gf, HudPalette.snap(clampf(pct / 150.0, 0.2, 1.0) * h, g))
		var rect := Rect2(x0, h - bh, x1 - x0, bh)
		var kind := str(b.get("kind", ""))
		var c := level_color(pct) if flat else kind_color(kind)
		if kind == Wl.WORK and not flat:
			c = palette.pick(HudPalette.ACCENT, c)
		if not flat and i < current:
			c = Color(c, 0.35)
		elif not flat and i > current:
			c = Color(c, 0.7)
		draw_rect(rect, c)
		if sim:
			var hatch := palette.pick(HudPalette.PANEL, bg) if flat else Color(0, 0, 0, 0.45)
			for cy in int(bh / gf):
				for cx in int(rect.size.x / gf):
					if (cx + cy) % 3 == 0:
						var cell := Rect2(x0 + cx * gf, h - bh + cy * gf, gf, gf)
						draw_rect(cell, hatch)
		if i == current:
			var tc := palette.pick(HudPalette.TEXT, WlTheme.TEXT)
			for edge in [
				Rect2(x0, h - bh, rect.size.x, gf),
				Rect2(x0, h - gf, rect.size.x, gf),
				Rect2(x0, h - bh, gf, bh),
				Rect2(x1 - gf, h - bh, gf, bh)
			]:
				draw_rect(edge, tc)
			var mx := minf(HudPalette.snap(x0 + (x1 - x0) * progress, g), w - gf)
			draw_rect(Rect2(mx, 0.0, gf, h), palette.pick(HudPalette.GLOW, WlTheme.GLOW))
