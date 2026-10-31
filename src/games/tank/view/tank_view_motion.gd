class_name TankViewMotion
extends TankViewBase
## TankView's motion layer: free roam's direction and map place, the relief under the wheels and the hull's pose.

# --- Free roam -----------------------------------------------------------------------------------------


func _roam_frame(state: TankState) -> void:
	var r := state.roam
	var dir := state.hull.dir if r.active else TankIds.DIR_RIGHT
	if r.active and _dir_seen != 0 and dir != _dir_seen:
		_mirror_wrecks(state)
	_dir_seen = dir
	mirrored = r.active and dir < 0
	if r.active and state.roam_map != null:
		map_m = r.map_m + (hull_x - state.hull.x_px) / TankConst.PX_PER_M * float(dir)
		plane_x = map_m * TankConst.PX_PER_M
	else:
		plane_x = cam_x
	for n: String in MIRROR_LAYERS:
		var l: Node2D = _layers.get(n, null)
		if l != null:
			l.scale = Vector2(-1, 1) if mirrored else Vector2.ONE
			l.position = Vector2(canvas.x, 0) if mirrored else Vector2.ZERO


## The travel-frame x (rules px) of map metre `m` as drawn this frame.
func travel_x(state: TankState, m: float) -> float:
	var cx := hull_x + float(state.hull.hull_w) * 0.5
	return cx + (m - map_m) * float(state.hull.dir) * TankConst.PX_PER_M


func _mirror_wrecks(state: TankState) -> void:
	var cx := state.hull.x_px + float(state.hull.hull_w) * 0.5
	for w in wrecks:
		w["x"] = 2.0 * cx - float(w["x"])
		w["side"] = -int(w.get("side", 1))


## How thick the turn's dust cloud is (0..1).
func turn_dust(state: TankState) -> float:
	var r := state.roam
	if not r.active or r.turn_s <= 0.0:
		return 0.0
	var half := 0.5 * (state.content.num("valley", "turn.stop_s", 8.0) if state.content else 8.0)
	var k := 1.0 - absf(r.turn_s - half) / maxf(half, 0.01)
	return clampf(k * TURN_DUST_GAIN, 0.0, 1.0)


func _hud_x(x: float) -> float:
	return canvas.x - x if mirrored else x


func _hud_rect(r: Rect2) -> Rect2:
	if not mirrored or r.size == Vector2.ZERO:
		return r
	return Rect2(Vector2(canvas.x - r.end.x, r.position.y), r.size)


# --- The relief and the pose ------------------------------------------------------------------------------


func _relief(state: TankState) -> void:
	var hull_cx := tank_pos.x + rig.size.x * 0.5
	var key := ""
	var points: Array = []
	var hm := 0.0
	if state.roam.active and state.roam_map != null:
		key = "roam %d" % state.roam.map_seed
		hm = map_m
		points = state.roam_map.terrain
	elif state.content != null:
		key = "seg %d" % state.seg.phase_index
		var t: Variant = state.content.segment(state.seg.phase_index).get("terrain", [])
		points = t if t is Array else []
		hm = hull_x / TankConst.PX_PER_M
	if mirrored:
		hull_cx = canvas.x - hull_cx
	ground.frame(plane_x * S, hull_cx, hm, key, points)


## The tank's pose: the fit of the relief under the wheels and their springs' lift (the targets),
## the hull's angle and lift following them on a damped spring (the bob), the shot's rock and jolt,
## the evade lurch and the hit shake; then each wheel on its arm within its travel.
func _pose(step_dt: float) -> void:
	var cx := tank_pos.x + rig.size.x * 0.5
	var gfn := Callable(self, "ground_y")
	var fit := TankSuspension.fit(rig.wheels, rig.size, cx, gfn)
	var trot := float(fit["rot"])
	var at: Vector2 = fit["at"]
	var g := rig.gear
	var t_track := float(g.get("T", 5.0))
	var up := float(g.get("up", 7.0))
	var droop := float(g.get("droop", 5.0))
	var x0 := TankSuspension.xform(rig.size, rig.ground, at, trot, 0.0)
	var c0 := TankSuspension.wheel_centres(rig.wheels, x0, gfn, t_track, up, droop)
	var tlift := TankSuspension.lift_of(rig.wheels, c0)
	if not _pose_primed or step_dt <= 0.0:
		hull_rot = trot
		hull_lift = tlift
		_pose_primed = true
	else:
		var n := maxi(ceili(step_dt / 0.01), 1)
		var h := step_dt / float(n)
		for i in n:
			_rot_v += (SPRING_K * (trot - hull_rot) - SPRING_D * _rot_v) * h
			hull_rot += _rot_v * h
			_lift_v += (SPRING_K * (tlift - hull_lift) - SPRING_D * _lift_v) * h
			hull_lift += _lift_v * h
	var rot := hull_rot + deg_to_rad(firing.rock())
	shake = maxf(shake - step_dt * 3.0, 0.0)
	var off := Vector2.ZERO
	if shake > 0.0:
		off = Vector2(roundf(sin(time * 61.0) * 2.0 * shake), roundf(cos(time * 47.0) * shake))
	if lurch_s >= 0.0:
		lurch_s += step_dt
		off.x += roundf(sin(minf(lurch_s / 1.2, 1.0) * PI) * 6.0)
		if lurch_s > 1.2:
			lurch_s = -1.0
	if screen_s >= 0.0:
		screen_s += step_dt
		if screen_s > 6.0:
			screen_s = -1.0
	off -= Vector2(firing.jolt(), 0).rotated(rot)
	off.x -= tow_px
	xf = TankSuspension.xform(rig.size, rig.ground, at + off, rot, hull_lift)
	wheel_centres = TankSuspension.wheel_centres(rig.wheels, xf, gfn, t_track, up, droop)


## The road under wheel `i` (stage px): where its track touches the road.
func wheel_contact(i: int) -> Vector2:
	var w := rig.wheels[i]
	var c := xf * wheel_centres[i]
	var down := xf.basis_xform(Vector2.DOWN).normalized()
	return c + down * (w.z + float(rig.gear.get("T", 5.0)))
