class_name TankCrew
extends RefCounted
## The crewmen (docs/games/tank.md 3.3): 20 px figures from the kit's crew sheet, posed by the state.
##   engineer  works the diesel with a wrench, on the diesel rider's cadence
##   stoker    shovels coal at the firebox on the steam rider's cadence (the Bulwark: at the diesel)
##   loader    carries a shell from the rack to the hoist and climbs it, one trip every four of the
##             steam engine's revolutions
##   gunner    at the breech in the turret-drive room; steps back with each shot
##   tech      at the dynamo's panel, and the arc tech at the arc generator's switchboard
##   commander on the turret roof at the searchlight, a spotter behind him; idle crew in quarters
## In a breakdown everyone at a machine works the repair with a wrench. Frame phases advance with
## the frame time; nothing here feeds the rules.

## Frames are drawn with their feet at this cell pixel (kit.json crew: cell 30 x 24, feet row 23).
const FEET := Vector2(10, 23)
## Lamp-lit tints: the room crews, the spotter and the commander out in the night.
const ROOM_TINT := Color(0.82, 0.74, 0.64)
const SPOTTER_TINT := Color(0.62, 0.6, 0.58)
const COMMANDER_TINT := Color(0.7, 0.68, 0.64)
const IDLE_FPS := 0.35

var _anim: Dictionary = {}


## Animation frame counter of actor `key`, advanced by `dt` at `fps`.
func _phase(key: String, fps: float, dt: float) -> float:
	var p := float(_anim.get(key, float(posmod(key.hash(), 97)) * 0.37))
	p += dt * fps
	_anim[key] = p
	return p


## Frames a second for an action that repeats `per_rev` times a crank revolution.
static func cad_fps(rpm: float, per_rev: float) -> float:
	var c := rpm if rpm > 1.0 else 0.0
	return maxf(c / 60.0 * per_rev, 0.4) if c > 0.0 else 0.0


## The actors of variant `vspec` (kit.json): [{pose, at (variant px of the feet), flip, frame, mod}];
## the commander and the spotter also carry roof: true (they turn with the turret).
## `info`: {cad: {engine: rpm}, steam_phase: float, solo: bool, breakdown: bool, recoil: 0..1,
## dt: float}.
func actors(vspec: Dictionary, info: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cad: Dictionary = info.get("cad", {})
	var dt := float(info.get("dt", 0.0))
	var broken := bool(info.get("breakdown", false))
	var solo := bool(info.get("solo", false))
	for room: Dictionary in vspec.get("rooms", []):
		var r := TankKit.rect_of(room)
		var fy := float(room["floor_y"])
		var id := str(room["id"])
		match id:
			"diesel":
				var c := float(cad.get("diesel", 0.0))
				out.append(
					_act("engineer", Vector2(r.end.x - 12, fy), true, cad_fps(c, 1.5), id, dt)
				)
				if solo:
					var stoker := "engineer" if broken else "stoker"
					out.append(
						_act(
							stoker, Vector2(r.position.x + 8, fy), false, cad_fps(c, 2.0), "ds", dt
						)
					)
			"steam":
				var cs := float(cad.get("steam", 0.0))
				var pose := "engineer" if broken else "stoker"
				out.append(_act(pose, Vector2(r.end.x - 22, fy), false, cad_fps(cs, 2.0), id, dt))
				out.append_array(_loader(r, fy, float(info.get("steam_phase", 0.0)), cs, dt))
			"dynamo":
				var cy := float(cad.get("dynamo", 0.0))
				var p2 := "engineer" if broken else "tech"
				out.append(_act(p2, Vector2(r.position.x + 9, fy), false, cad_fps(cy, 1.0), id, dt))
			"arc":
				var ca := float(cad.get("arc", 0.0))
				var p3 := "engineer" if broken else "tech"
				out.append(_act(p3, Vector2(r.end.x - 10, fy), true, cad_fps(ca, 1.0), id, dt))
			"turret_drive":
				var g := _act("gunner", Vector2(r.position.x + 24, fy), false, 0.0, id, dt)
				var rec := float(info.get("recoil", 0.0))
				g["frame"] = 2 if rec > 0.5 else (1 if rec > 0.05 else 0)
				g["at"] = (g["at"] as Vector2) + Vector2(-roundf(rec * 2.0), 0)
				out.append(g)
			"quarters":
				var n := int(r.size.x / 30.0)
				for i in n:
					var fps := 3.0 if broken and i == 0 else IDLE_FPS
					var pose2 := "engineer" if broken and i == 0 else "idle"
					var a := _act(
						pose2,
						Vector2(r.position.x + 14 + i * 30, fy),
						i % 3 == 1,
						fps,
						"%s%d" % [id, i],
						dt
					)
					out.append(a)
			"upper_front":
				out.append(_act("idle", Vector2(r.position.x + 12, fy), false, 0.3, id, dt))
			"front_machinery":
				var fps2 := 3.0 if broken else 0.8
				out.append(_act("engineer", Vector2(r.position.x + 14, fy), false, fps2, id, dt))
	var feet := TankKit.vec(vspec.get("anchors", {}).get("turret_roof_commander_feet", [0, 0]))
	var spot := _act("spotter", feet + Vector2(-34, 0), false, 0.4, "spot", dt)
	spot["mod"] = SPOTTER_TINT
	spot["roof"] = true
	out.append(spot)
	var cmd := _act("commander", feet, false, 0.0, "cmd", dt)
	cmd["frame"] = 0
	cmd["mod"] = COMMANDER_TINT
	cmd["roof"] = true
	out.append(cmd)
	return out


func _act(pose: String, at: Vector2, flip: bool, fps: float, key: String, dt: float) -> Dictionary:
	return {
		"pose": pose,
		"at": at,
		"flip": flip,
		"frame": int(_phase(key + pose, fps, dt)),
		"mod": ROOM_TINT,
	}


## The loader: carries a shell from the rack to the hoist's ladder, then climbs it (one trip every
## four revolutions of the steam engine, so in step with the hoist).
func _loader(r: Rect2, fy: float, steam_phase: float, rpm: float, dt: float) -> Array[Dictionary]:
	var ladder := r.position.x + 17.0
	var rack := r.position.x + 46.0
	var cyc := fposmod(steam_phase * 0.25, 1.0)
	if cyc < 0.5:
		var a := _act(
			"loader",
			Vector2(lerpf(rack, ladder + 4.0, cyc / 0.5), fy),
			true,
			cad_fps(rpm, 2.0),
			"ld",
			dt
		)
		return [a]
	if cyc < 0.85:
		var k := (cyc - 0.5) / 0.35
		var a2 := _act("loader_climb", Vector2(ladder - 2.0, fy - 26.0 * k), false, 0.0, "lc", dt)
		a2["frame"] = int(k * 8.0) % 2
		return [a2]
	return []


## Draws actor `a` of the kit's crew frames with the variant at `origin`.
static func draw_actor(ci: CanvasItem, kit: TankKit, a: Dictionary, origin: Vector2) -> void:
	var frames: Array = kit.crew.get(a["pose"], [])
	if frames.is_empty():
		return
	var tex: Texture2D = frames[posmod(int(a["frame"]), frames.size())]
	var feet: Vector2 = origin + (a["at"] as Vector2)
	var mod: Color = a.get("mod", Color.WHITE)
	if bool(a["flip"]):
		var fx := (feet + Vector2(FEET.x, -FEET.y - 1)).round()
		ci.draw_set_transform(fx, 0.0, Vector2(-1, 1))
		ci.draw_texture(tex, Vector2.ZERO, mod)
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	else:
		ci.draw_texture(tex, (feet - FEET - Vector2(0, 1)).round(), mod)
