class_name SiegeHudWorld
extends SiegeHudCtl
## What the HUD pins to the world: a red tag over a live ram or tower closing in ("TOWER 110 M",
## placed with SiegePath.to_art), and while the gate is failing in a wave, the oxblood banner with
## a leader to the gate. It covers the whole canvas under the plates and draws only these.

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


func build() -> Dictionary:
	var s := st()
	var tx := SiegeHudModel.strings_of(game)
	var out := {"tags": SiegeHudModel.world_tags(s, tx), "banner": ""}
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


func _tag(at: Vector2i, text: String) -> void:
	var w := SiegeHudType.width(text, "LABEL") + 8
	var lx := clampi(at.x - w / 2, 2, RECT.size.x - w - 2)
	# near the road's east end it stops at the cockpit, which would hide it
	if at.y + TAG_H > SiegeHudCockpit.RECT.position.y:
		lx = mini(lx, SiegeHudCockpit.RECT.position.x - w - 2)
	D.rect(self, lx, at.y, w, TAG_H, D.ALARM)
	SiegeHudType.draw(self, text, lx + 4, at.y + 3, "LABEL", D.TEXT)
	D.rect(self, at.x, at.y + TAG_H, 1, TAG_LEADER, D.ALARM)


func _banner(text: String, gate: Vector2i) -> void:
	var w := SiegeHudType.width(text, "LINE") + 20
	var x := BANNER_AT.x
	var y := BANNER_AT.y
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
