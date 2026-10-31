class_name SiegeHudWorld
extends SiegeHudCtl
## What the HUD pins to the world: a red tag over a live ram or tower closing in ("TOWER 110 M",
## placed with SiegePath.to_art), and while the gate is failing in a wave, the oxblood banner with
## a leader to the gate. It covers the whole canvas under the plates and draws only these, in the
## design frame's art px as the view does: its rect's anchoring centres it on a flex canvas, and
## shift() adds what SiegeViewMath.view_offset adds to that. Help points on the world need the same,
## so it wraps the help overlay's art_map.

const RECT := Rect2i(0, 0, 960, 540)
## How far above an engine's feet its tag hangs (art px, the sprites' height).
const TOWER_HEAD_PX := 78
const RAM_HEAD_PX := 30
const TAG_H := 14
const TAG_LEADER := 5
const BANNER_AT := Vector2i(300, 372)
const BANNER_H := 22
const SHADOW := Color(0.0, 0.0, 0.0, 0.4)
const GATE_LIFT := Vector3(0, 2, 3)


func _init() -> void:
	super._init()
	z_index = -1


func _enter_tree() -> void:
	var hl := hud_layer()
	if hl != null and hl.help_overlay() != null:
		hl.help_overlay().art_map = help_point


## The canvas now.
func canvas() -> Vector2i:
	return canvas_or(SiegeHud.BASE)


## From this Control's anchored place to the design frame's top-left on the canvas.
func shift() -> Vector2i:
	var art := canvas()
	var at := PixelViewport.anchor_rect(RECT, SiegeHud.BASE, art).position
	return SiegeViewMath.view_offset(art) - at


## A help point (laid out on the base) on the current canvas: the HudLayer's own mapping, plus
## shift() when it lies on the world.
func help_point(p: Vector2) -> Vector2:
	var hl := hud_layer()
	var q := hl.help_art_point(p) if hl != null else p
	for r in SiegeHud.plate_rects():
		if Rect2(r).has_point(p):
			return q
	return q + Vector2(shift())


func build() -> Dictionary:
	var s := st()
	var tx := SiegeHudModel.strings_of(game)
	var art := canvas()
	var out := {"tags": SiegeHudModel.world_tags(s, tx), "banner": "", "shift": shift(), "art": art}
	if s.in_wave() and SiegeHudModel.gate_low(s) and s.path != null:
		out["banner"] = tx.t("SIEGE_HUD_GATE_FAILING")
		var g := s.path.to_art(s.path.gate_pos + GATE_LIFT)
		out["gate"] = Vector2i(roundi(g.x), roundi(g.y))
	return out


func paint() -> void:
	for tag: Dictionary in model["tags"]:
		_tag(tag["at"], str(tag["text"]))
	if str(model["banner"]) != "":
		_banner(str(model["banner"]), model["gate"])


func _tag(design: Vector2i, text: String) -> void:
	var at: Vector2i = design + (model["shift"] as Vector2i)
	var art: Vector2i = model["art"]
	var here := PixelViewport.anchor_rect(RECT, SiegeHud.BASE, art).position
	var cockpit := (
		PixelViewport.anchor_rect(SiegeHudCockpit.RECT, SiegeHud.BASE, art).position - here
	)
	var w := SiegeHudType.width(text, "LABEL") + 8
	var lx := tag_x(at.x, w, here.x, art.x)
	# near the road's east end it stops at the cockpit, which would hide it
	if at.y + TAG_H > cockpit.y:
		lx = mini(lx, cockpit.x - w - 2)
	D.rect(self, lx, at.y, w, TAG_H, D.ALARM)
	SiegeHudType.draw(self, text, lx + 4, at.y + 3, "LABEL", D.TEXT)
	D.rect(self, at.x, at.y + TAG_H, 1, TAG_LEADER, D.ALARM)


## A tag's left edge in this Control's px: over its engine, kept on the canvas (this Control's
## origin lies at `here` on a canvas `art_w` wide).
static func tag_x(at_x: int, w: int, here: int, art_w: int) -> int:
	return clampi(at_x - w / 2, 2 - here, art_w - here - w - 2)


func _banner(text: String, design_gate: Vector2i) -> void:
	var w := SiegeHudType.width(text, "LINE") + 20
	var at: Vector2i = BANNER_AT + (model["shift"] as Vector2i)
	var gate: Vector2i = design_gate + (model["shift"] as Vector2i)
	var x := at.x
	var y := at.y
	# the leader from the banner's top to the gate, one pixel a row
	var from := x + 80
	var rows := maxi(y - gate.y, 1)
	for j in rows:
		var lx := roundi(lerpf(from, gate.x, float(j) / float(rows)))
		D.rect(self, lx, y - j, 1, 1, D.OXBLOOD)
	D.rect(self, x + 2, y + 2, w, BANNER_H, SHADOW)
	D.rect(self, x, y, w, BANNER_H, D.OXBLOOD)
	D.rect(self, x, y, w, 1, D.ALARM)
	D.rect(self, x, y + BANNER_H - 1, w, 1, D.ALARM)
	SiegeHudType.draw(self, text, x + 10, y + 4, "LINE", D.TEXT, false)
