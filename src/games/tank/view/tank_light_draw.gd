class_name TankLightDraw
extends RefCounted
## The two additive light layers (docs/games/tank.md v3 "Lights", 3.1). Lights are the only
## near-saturated pixels.
##   draw()        the tank's own lights, on the Light layer over the tank and rotated with the hull:
##                 the rooms' incandescent lamps (warm; the seat's slot colour mixed in while its
##                 rider is in band; the Lights room cold while its arc burns; Repairs a pinker
##                 copper while manned; dark in a breakdown),
##                 falling back to the backup lighting while the Lights seat is unpowered
##                 (TankView.backup_level: the warm blooms down to BACKUP_GAIN, a small red emergency
##                 lamp in each room; TankBody dims the rooms), the turret windows' lamps, the
##                 headlight (always on), the turret searchlight (forward about 11 degrees down) and
##                 the rear searchlight (aft about 13 degrees down), both on only while the Lights
##                 seat is powered (TankView.lights_powered), fading in and out with
##                 TankView.search_level, a dim standby glow on their lenses while off; the red and
##                 green position lights, the main gun's scene flash, the bow rounds' tracers and
##                 muzzle flashes, shells, flashes, the wash
##   draw_world()  every world light, on the WorldLight layer behind the tank: the tank's pools on
##                 the road (the headlight's; each searchlight's where its cone's lower edge meets
##                 the road, kept on screen, with a faint spill along the road out to where its
##                 axis lands, beam_pool(); the rooms' spill; the shot's flash), the little bases'
##                 lamps, the halt line's and the turning places' lamps, burning wrecks, the beams'
##                 light on near threats and wrecks, the near threats' slits; the far panel has its
##                 own (TankFarPanel)

const WARM := Color(1.0, 0.64, 0.32)
const COLD := Color(0.66, 0.82, 1.0)
const RED := Color(1.0, 0.15, 0.1)
const GREEN := Color(0.2, 1.0, 0.35)
const AMBER := Color(1.0, 0.68, 0.3)
const SEARCH := Color(1.0, 0.94, 0.78)
## The beams' warm light on what they cross.
const BEAM_LIT := Color(1.0, 0.8, 0.52)
const BEAM_LIT_A := 0.16
## A live near threat takes only this of it: its dark plates and cold rim stay.
const THREAT_LIT := 0.4
## The headlight stops on a near threat: its cone fades out this far into the sprite.
const HEAD_INTO_THREAT := 14.0
## The headlight's beam: degrees below the hull's line, length, half spread (degrees).
const HEAD_DEG := 9.0
const HEAD_LEN := 210.0
const HEAD_HALF := 12.0
## The searchlights' slow sway (degrees) and its rate.
const SWAY_DEG := 1.0
const SWAY_HZ := 0.45
## A searchlight's pool on the road: its half width, and how far inside the canvas' edges its
## centre stays (px).
const POOL_R := 46.0
const POOL_EDGE := 20.0
## The searchlights' lenses while off: a dim standby glow.
const STANDBY := Color(1.0, 0.62, 0.34, 0.55)
## The backup lighting: what is left of the warm lamps' bloom, and the emergency lamps' red.
const BACKUP_GAIN := 0.3
const EMERGENCY := Color(1.0, 0.2, 0.08)
## The Repairs room's lamp (SPEC_TANK 5.3): a pinker copper than the diesel's, no other seat's.
const REPAIR_LAMP := Color(1.0, 0.7, 0.48)
## The room the Repairs seat works in.
const REPAIR_ROOM := "turret_drive"
## The rooms that glow (kit rooms).
const GLOW_ROOMS: Array[String] = [
	"drive", "loader", "gun", "lights", "sec", "quarters", "turret_drive", "upper_front"
]


static func draw(ci: CanvasItem, v: TankView, state: TankState) -> void:
	if not state.hull.breakdown:
		_rooms(ci, v, state)
	_beams(ci, v, state)
	_running_lights(ci, v)
	_scene_flash(ci, v)
	_bow_rounds(ci, v)
	_near_lights(ci, v, state)
	_shells(ci, v, state)
	v.fx.draw_light(ci)
	if v.fx.wash > 0.0:
		var c := v.fx.wash_color
		TankDraw.glow_at(ci, v.fx.wash_pos, 320.0, Color(c.r, c.g, c.b, 0.16 * v.fx.wash))


## The near threats' own lights and what the beams leave on them, over their sprites (TankWorldDraw.draw_near_threats).
static func _near_lights(ci: CanvasItem, v: TankView, state: TankState) -> void:
	for id: int in v.enemy_feet:
		var e := state.enemy(id)
		if e == null:
			continue
		var kind := v.enemy_kind(e)
		if v.lanes.has(id):
			_beam_lit(ci, v, state, kind, v.enemy_rects[id], int(v.lanes[id]), THREAT_LIT)
		TankEnemyDraw.draw_light(ci, v.enemy_kit, kind, v.enemy_feet[id], v.near_pose(e))


static func draw_world(ci: CanvasItem, v: TankView, state: TankState) -> void:
	_ground_pools(ci, v, state)
	_world_lamps(ci, v, state)
	for bx in TankForest.bases(v, state):
		TankForest.draw_base_light(ci, v, bx)
	_fires(ci, v)
	_lit_by_beams(ci, v)


## The tank's beams this frame: [{p (the lens, stage px), ang, half (radians), len, k, head}].
static func beams(v: TankView, state: TankState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var hk := 1.0
	if state.hull.breakdown:
		hk = 0.25 + 0.2 * TankDraw.hash01(floorf(v.time * 12.0))
	var hd := v.rig.detail("headlight")
	if not hd.is_empty():
		(
			out
			. append(
				{
					"p": v.at_sprite((hd["at"] as Vector2) + Vector2(3.5, 0)),
					"ang": v.hull_rot + deg_to_rad(HEAD_DEG),
					"half": deg_to_rad(HEAD_HALF),
					"len": head_len(v, v.at_sprite((hd["at"] as Vector2) + Vector2(3.5, 0))),
					"k": hk,
					"head": true,
				}
			)
		)
	var sway := deg_to_rad(SWAY_DEG * sin(v.time * SWAY_HZ))
	var ts := v.rig.detail("searchlight")
	if not ts.is_empty() and v.search_level > 0.0:
		var a := deg_to_rad(float(ts.get("ang", 11.0)))
		(
			out
			. append(
				{
					"p": v.at_sprite(TankRig.lens_of(ts)),
					"ang": v.hull_rot + a + sway,
					"half": deg_to_rad(float(ts.get("half", 6.0))),
					"len": float(ts.get("len", 560.0)),
					"k": v.search_level,
					"head": false,
				}
			)
		)
	var rs := v.rig.detail("searchlight_rear")
	if not rs.is_empty() and v.search_level > 0.0:
		(
			out
			. append(
				{
					"p": v.at_sprite(TankRig.lens_of(rs)),
					"ang": v.hull_rot + deg_to_rad(float(rs.get("ang", 167.0))) + sway,
					"half": deg_to_rad(float(rs.get("half", 8.0))),
					"len": float(rs.get("len", 220.0)),
					"k": v.search_level,
					"head": false,
				}
			)
		)
	return out


## The headlight's reach from lens `p`: it ends on the nearest near threat ahead, so its cone does not flatten the
## sprite with its warm wash.
static func head_len(v: TankView, p: Vector2) -> float:
	var out := HEAD_LEN
	for id: int in v.enemy_rects:
		var r: Rect2 = v.enemy_rects[id]
		var d := r.position.x - p.x + HEAD_INTO_THREAT
		if d > 0.0:
			out = minf(out, d)
	return out


## How much of the tank's beams falls on stage point `p` (0..1): each beam by how near `p` lies to
## its cone's axis and how far down its reach.
static func beam_light(v: TankView, state: TankState, p: Vector2) -> float:
	var k := 0.0
	for b in beams(v, state):
		var d: Vector2 = p - (b["p"] as Vector2)
		var dist := d.length()
		if dist < 1.0:
			continue
		var off := absf(angle_difference(d.angle(), float(b["ang"])))
		var cone := clampf(1.0 - off / (float(b["half"]) * 2.2), 0.0, 1.0)
		var reach := clampf(1.0 - dist / (float(b["len"]) * 1.4), 0.0, 1.0)
		k += cone * cone * sqrt(reach) * minf(float(b["k"]), 1.0)
	return clampf(k, 0.0, 1.0)


## The rooms' lamps: a bloom over each lit room, a lamp at its ceiling, the turret windows' lamps;
## under the backup lighting (backup_level) the blooms and lamps dim to BACKUP_GAIN and each room's
## emergency lamp glows red in its ceiling's corner.
static func _rooms(ci: CanvasItem, v: TankView, state: TankState) -> void:
	var arc_on := v.turret_search_on(state)
	var bk := v.backup_level
	var warm := lerpf(1.0, BACKUP_GAIN, bk)
	for id in GLOW_ROOMS:
		var r: Rect2 = v.rig.rooms.get(id, Rect2())
		if r.size == Vector2.ZERO:
			continue
		var c := v.at_sprite(r.get_center())
		var lamp := v.at_sprite(Vector2(r.get_center().x, r.position.y + 3.0))
		var gain := 1.0
		var rd := room_rider(v, id)
		var col := REPAIR_LAMP if id == REPAIR_ROOM and rd != null else WARM
		if id == "lights" and arc_on:
			col = COLD
			gain = 1.4
		elif rd != null and rd.in_band:
			col = col.lerp(slot_color(rd), 0.15)
			gain = 1.25
		var fl := 0.92 + 0.08 * sin(v.time * 3.0 + r.position.x)
		gain *= warm
		TankDraw.glow_at(ci, c, r.size.x * 0.75, Color(col.r, col.g, col.b, 0.1 * fl * gain))
		TankDraw.glow_at(ci, c, r.size.x * 0.35, Color(col.r, col.g, col.b, 0.08 * fl * gain))
		TankDraw.glow_at(ci, lamp, 4.0, Color(1.0, 0.85, 0.6, 0.45 * warm))
		if bk > 0.0:
			var e := v.at_sprite(emergency_lamp(r))
			var pulse := 0.85 + 0.15 * sin(v.time * 1.6 + r.position.x * 0.1)
			TankDraw.glow_at(ci, e, 2.5, Color(EMERGENCY, 0.9 * bk))
			TankDraw.glow_at(ci, e, r.size.x * 0.45, Color(EMERGENCY, 0.1 * bk * pulse))
	for wl in v.rig.window_lamps:
		var p := v.at_sprite(wl)
		TankDraw.glow_at(ci, p + Vector2(0, 4), 12.0, Color(WARM.r, WARM.g, WARM.b, 0.14 * warm))


## The rider of the seat a room belongs to, or null.
static func room_rider(v: TankView, id: String) -> TankRiderState:
	if id == REPAIR_ROOM:
		return v.rider_on("repair")
	return v.rider_on(id) if id in TankRig.SEATS else null


## A room's emergency lamp (sprite px): in its ceiling's left corner.
static func emergency_lamp(r: Rect2) -> Vector2:
	return r.position + Vector2(3.5, 2.5)


## A rider's slot colour (the caps TankInterior paints).
static func slot_color(r: TankRiderState) -> Color:
	if r == null:
		return WARM
	return TankInterior.SLOT[posmod(r.slot, TankInterior.SLOT.size())]


static func _beams(ci: CanvasItem, v: TankView, state: TankState) -> void:
	for b in beams(v, state):
		var p: Vector2 = b["p"]
		var k := float(b["k"])
		var ang := float(b["ang"])
		var half := float(b["half"])
		if bool(b["head"]):
			TankDraw.beam(ci, p, ang, float(b["len"]), half, Color(1.0, 0.82, 0.52), 0.5 * k)
			TankDraw.glow_at(ci, p, 6.0, Color(1.0, 0.95, 0.8, k))
			TankDraw.glow_at(ci, p, 22.0, Color(1.0, 0.8, 0.5, 0.35 * k))
			continue
		TankDraw.beam(ci, p, ang, float(b["len"]), half, SEARCH, 0.45 * k)
		TankDraw.glow_at(ci, p, 9.0, Color(1.0, 0.95, 0.8, 0.9 * maxf(k, 0.3)))
		TankDraw.glow_at(ci, p, 24.0, Color(1.0, 0.85, 0.6, 0.2 * k))
	if v.search_level >= 1.0:
		return
	var off := 1.0 - v.search_level
	for lens in standby_lenses(v):
		TankDraw.glow_at(ci, lens, 3.5, Color(STANDBY, STANDBY.a * off))
		TankDraw.glow_at(ci, lens, 9.0, Color(STANDBY, STANDBY.a * 0.3 * off))


## Both searchlights' lenses as drawn (stage px): the turret's, the rear's.
static func standby_lenses(v: TankView) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var ts := v.rig.detail("searchlight")
	if not ts.is_empty():
		out.append(v.at_sprite(TankRig.lens_of(ts)))
	var rs := v.rig.detail("searchlight_rear")
	if not rs.is_empty():
		out.append(v.at_sprite(TankRig.lens_of(rs)))
	return out


## The bow rounds' light: a glow on each tracer's head and, while it burns, the muzzle flash.
static func _bow_rounds(ci: CanvasItem, v: TankView) -> void:
	for t in v.firing.tracers(v):
		TankDraw.glow_at(ci, t["p"], 5.0, Color(1.0, 0.7, 0.35, 0.4))
		var fl := float(t["flash"])
		if fl > 0.0:
			TankDraw.glow_at(ci, t["muzzle"], 12.0, Color(1.0, 0.75, 0.4, 0.7 * fl))
			TankDraw.glow_at(ci, t["muzzle"], 4.0, Color(1.0, 0.95, 0.8, 0.9 * fl))


## The red and green position lights (the rear red one and the green one blinking slowly).
static func _running_lights(ci: CanvasItem, v: TankView) -> void:
	var blink := 0.75 + 0.25 * sin(v.time * 2.2)
	var reds := v.rig.details_of("lamp_red")
	for i in reds.size():
		var p := v.at_sprite((reds[i]["at"] as Vector2) + Vector2(0.5, 0.5))
		TankDraw.lamp(ci, p, RED, blink if i == 0 else 0.9)
	for g in v.rig.details_of("lamp_green"):
		TankDraw.lamp(ci, v.at_sprite((g["at"] as Vector2) + Vector2(0.5, 0.5)), GREEN, blink)


## The main gun's flash on the scene for its first frames: a wide warm halo at the muzzle, the
## tank's own hull and the road lit, a white core.
static func _scene_flash(ci: CanvasItem, v: TankView) -> void:
	var k := v.firing.flash_k()
	if k <= 0.0:
		return
	var m := v.muzzle()
	TankDraw.glow_at(ci, m, 240.0, Color(1.0, 0.75, 0.44, 0.5 * k))
	TankDraw.glow_at(ci, m + Vector2(-120, 50), 220.0, Color(1.0, 0.69, 0.38, 0.28 * k))
	TankDraw.glow_at(ci, m + Vector2(10, 90), 160.0, Color(1.0, 0.69, 0.38, 0.25 * k))
	TankDraw.glow_at(ci, m, 26.0, Color(1.0, 0.96, 0.82, 0.9 * k))


## The tank's pools on the road (behind the tank): the headlight's long pool, the searchlights'
## pools where their axes meet the road, the shot's flash, the rooms' spill beside the tracks.
static func _ground_pools(ci: CanvasItem, v: TankView, state: TankState) -> void:
	for b in beams(v, state):
		var p: Vector2 = b["p"]
		var k := minf(float(b["k"]), 1.0)
		if bool(b["head"]):
			var x1 := p.x + 160.0
			var x2 := p.x + 45.0
			ground_glow(
				ci, Vector2(x1, v.ground_y(x1) + 6.0), 125.0, Color(1.0, 0.75, 0.45, 0.4 * k)
			)
			ground_glow(
				ci, Vector2(x2, v.ground_y(x2) + 3.0), 70.0, Color(1.0, 0.72, 0.42, 0.22 * k)
			)
			continue
		var pool := beam_pool(v, b)
		if pool.is_empty():
			continue
		var spill: Vector2 = pool["spill"]
		if spill.y > 0.0:
			var sc := Vector2(spill.x, v.ground_y(spill.x) + 4.0)
			ground_glow(ci, sc, spill.y, Color(1.0, 0.9, 0.72, 0.09 * k))
		ground_glow(
			ci, pool["at"], float(pool["r"]), Color(1.0, 0.9, 0.72, 0.32 * k * float(pool["a"]))
		)
	var fk := v.firing.flash_k()
	if fk > 0.0:
		var m := v.muzzle()
		ground_glow(
			ci, Vector2(m.x, v.ground_y(m.x) + 4.0), 220.0, Color(1.0, 0.72, 0.38, 0.5 * fk)
		)
	if state.hull.breakdown:
		return
	for id in GLOW_ROOMS:
		var r: Rect2 = v.rig.rooms.get(id, Rect2())
		if r.size == Vector2.ZERO or r.position.y < 140.0:
			continue
		var lit := 0.08
		var rd := room_rider(v, id)
		if rd != null:
			lit = 0.12 if rd.in_band else 0.07
		var x := v.at_sprite(r.get_center()).x
		var c := Color(1.0, 0.66, 0.36, lit * lerpf(1.0, BACKUP_GAIN, v.backup_level))
		if id == "lights" and v.turret_search_on(state):
			c = Color(COLD.r, COLD.g, COLD.b, 0.07)
		ground_glow(ci, Vector2(x, v.ground_y(x) + 6.0), r.size.x * 0.8 + 20.0, c)


## A searchlight's pool on the road (beam `b` of beams()): {at (where its cone's lower edge meets the
## road, its x kept POOL_EDGE inside the canvas), r, a (0.35..1: dimmer the further the light
## travelled and when the true pool lies off screen), spill (Vector2(centre x, half width) of the
## faint light along the road from the pool out to where the axis lands, kept on the canvas; y 0
## for none)}; {} for a beam pointing up.
static func beam_pool(v: TankView, b: Dictionary) -> Dictionary:
	var p: Vector2 = b["p"]
	var ang := float(b["ang"])
	var half := float(b["half"])
	var lo := ang + half if sin(ang + half) > sin(ang - half) else ang - half
	var e := Vector2.from_angle(lo)
	if e.y <= 0.01:
		return {}
	var hit := road_hit(v, p, e)
	var dist := hit.distance_to(p)
	var a := clampf(1.2 - dist / (float(b["len"]) * 1.6), 0.35, 1.0)
	var lim := Vector2(POOL_EDGE, v.canvas.x - POOL_EDGE)
	var x := clampf(hit.x, lim.x, lim.y)
	if x != hit.x:
		a *= 0.7
	var at := Vector2(x, v.ground_y(x) + 4.0)
	var spill := Vector2.ZERO
	var dv := Vector2.from_angle(ang)
	if dv.y > 0.01:
		var far := clampf(road_hit(v, p, dv).x, 0.0, v.canvas.x)
		if absf(far - x) > 8.0:
			spill = Vector2((far + x) * 0.5, absf(far - x) * 0.5 + POOL_R * 0.5)
	return {"at": at, "r": POOL_R, "a": a, "spill": spill}


## Where the ray from `p` along `d` (pointing down) meets the road (stage px).
static func road_hit(v: TankView, p: Vector2, d: Vector2) -> Vector2:
	var hit := p + d * ((v.ground_y(p.x) - p.y) / d.y)
	hit = p + d * ((v.ground_y(hit.x) - p.y) / d.y)
	hit.y = v.ground_y(hit.x)
	return hit


## A flat glow lying on the road (an ellipse 0.14 as tall as wide) at `p`, `r` px wide each side.
static func ground_glow(ci: CanvasItem, p: Vector2, r: float, c: Color) -> void:
	ci.draw_set_transform(p, 0.0, Vector2(1.0, 0.14))
	ci.draw_texture_rect(TankDraw.glow_tex(), Rect2(Vector2(-r, -r), Vector2(r, r) * 2.0), false, c)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _world_lamps(ci: CanvasItem, v: TankView, state: TankState) -> void:
	var hl := TankWorldDraw.halt_lamp(v, state)
	if not is_nan(hl.x):
		TankDraw.glow_at(ci, hl, 6.0, Color(1.0, 0.85, 0.6, 0.7))
		TankDraw.glow_at(ci, hl + Vector2(0, 14), 30.0, Color(AMBER.r, AMBER.g, AMBER.b, 0.3))
	for tl in TankWorldDraw.turn_lamps(v, state):
		TankDraw.glow_at(ci, tl, 5.0, Color(1.0, 0.85, 0.6, 0.7))
		TankDraw.glow_at(ci, tl + Vector2(0, 16), 34.0, Color(AMBER.r, AMBER.g, AMBER.b, 0.26))


## The beams' warm light on the wrecks they cross: over the kit's silhouette; the back lane less (haze). The kit's stub
## has no silhouette, so nothing shows until its art.
static func _lit_by_beams(ci: CanvasItem, v: TankView) -> void:
	var state := v.game.state
	for w in v.wrecks:
		if v.wreck_collapse(w) < 1.0:
			var wr := TankWorldDraw.wreck_rect(v, w)
			_beam_lit(ci, v, state, str(w["kind"]), wr, int(w.get("lane", 0)), 0.7)


static func _beam_lit(
	ci: CanvasItem,
	v: TankView,
	state: TankState,
	kind: String,
	r: Rect2,
	lane: int,
	gain: float = 1.0
) -> void:
	var tex := v.enemy_kit.texture()
	var row := v.enemy_kit.kind(kind)
	if tex == null or not row.has("sil") or r.end.x < 0.0 or r.position.x > v.canvas.x:
		return
	var k := beam_light(v, state, r.get_center()) * gain * (1.0 - TankWorldDraw.lane_fog(lane))
	if k >= 0.02:
		ci.draw_texture_rect_region(tex, r, row["sil"], Color(BEAM_LIT, BEAM_LIT_A * k))


static func _fires(ci: CanvasItem, v: TankView) -> void:
	for w in v.wrecks:
		var k := v.wreck_fire(w)
		if k <= 0.0:
			# The heap's embers: one slit glowing a while longer.
			if v.wreck_age(w) < TankView.WRECK_BURN_S * 2.0:
				var hr := TankWorldDraw.heap_rect(v, w)
				TankDraw.glow_at(
					ci, hr.get_center() + Vector2(2, 1), 3.0, Color(1.0, 0.35, 0.1, 0.35)
				)
			continue
		var r := TankWorldDraw.wreck_rect(v, w)
		if r.position.x > v.canvas.x + 10.0 or r.end.x < -10.0:
			continue
		var c := TankWorldDraw.wreck_hatch(v, w) + Vector2(0, -2)
		var fl := 0.75 + 0.25 * sin(v.time * 9.0 + r.position.x) * sin(v.time * 5.3)
		TankDraw.glow_at(ci, c, 14.0 * k, Color(1.0, 0.42, 0.12, 0.45 * fl * k))
		TankDraw.glow_at(ci, c, 4.0, Color(1.0, 0.75, 0.35, 0.7 * fl * k))


static func _shells(ci: CanvasItem, v: TankView, state: TankState) -> void:
	for s in v.shells_drawn(state):
		var at: Vector2 = s["at"]
		var d: Vector2 = s["dir"]
		var bow := int(s["type"]) == TankIds.SHELL_BOW
		var col := Color(1.0, 0.75, 0.35) if bool(s["friendly"]) else Color(1.0, 0.35, 0.2)
		var tail := 8.0 if bow else 14.0
		ci.draw_line(at - d * tail, at, Color(col.r, col.g, col.b, 0.35), 1.0 if bow else 2.0)
		ci.draw_line(at - d * tail * 0.45, at, Color(1, 0.95, 0.8, 0.9), 1.0)
		TankDraw.glow_at(ci, at, 3.0 if bow else 5.0, Color(col.r, col.g, col.b, 0.6))
