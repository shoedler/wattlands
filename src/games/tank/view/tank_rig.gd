class_name TankRig
extends Node2D
## One crew's tank as a cutaway (brief 3): the running gear and track belt, the hull sprite, the
## engine rooms with their machinery, the links between them (the diesel's chain to the drive
## sprocket, the dynamo's or gearbox's shaft to the turret ring, the steam engine's hoist rail to the
## breech), the exhaust stack, the main turret with a code-drawn barrel, the Citadel's secondaries
## and the dozer blade with the mud berm. The node sits on the hull frame (the hull sprite's
## top-left): rear at screen x 16, bottom 10 px above the ground line. It only reads the state.

## The hull's bottom stands this far above the ground line (the skirt over the tracks).
const GROUND_GAP := 10
const SHAKE_DECAY := 8.0
const HIT_FLASH_S := 0.14
const BLADE_EASE_PER_S := 3.0
const BERM_MAX_H := 24.0
const BERM_W := 30.0
const SLEW_HOLD_S := 0.4

var tank: String = ""
var def: Dictionary = {}
var hub: TankRigHub = null
var geometry: TankGeometry = null
var hull_w: int = 192
var hull_h: int = 72
var base_pos: Vector2 = Vector2.ZERO
var _roof: Rect2 = Rect2()
var _roof_done: bool = false
var gear: TankRunningGear = null
var hull_sprite: Sprite2D = null
var rooms: Array[TankRoomView] = []
var diesel_room: TankDieselRoom = null
var dynamo_room: TankDynamoRoom = null
var steam_room: TankSteamRoom = null
var links: Node2D = null
var drive_chain: ScrollingChain = null
var slew_shaft: ScrollingChain = null
## The Rampart's chain from the dynamo's armature to the foot of its hoist rail.
var hoist_chain: ScrollingChain = null
var stack: TankPainter = null
var rails: TankPainter = null
var dozer: TankPainter = null
var turret: TankTurretView = null
var secondaries: Array[TankSecondaryView] = []
## The shake offset (integer art px) and its amplitude.
var shake_amp: float = 0.0
var shake_offset: Vector2 = Vector2.ZERO
## The turret or its elevation moved lately (shafts turn).
var slewing: bool = false
## 0 raised .. 1 lowered, and the berm HP drawn.
var blade: float = 0.0
var berm_hp: float = 0.0

var _stack_pos: Vector2 = Vector2.ZERO
var _flash_s: float = 0.0
var _slew_hold: float = 0.0
var _elev_prev: float = 0.0


## Builds the rig of `p_tank` ("bulwark", "rampart", "citadel") from rigs.json.
func assemble(p_tank: String, p_hub: TankRigHub) -> void:
	tank = p_tank
	hub = p_hub
	name = "Rig_" + tank
	def = TankRigs.tank_def(tank)
	geometry = TankGeometry.load_default()
	var size := TankRigs.vec(def.get("hull_px", [192, 72]))
	hull_w = int(size.x)
	hull_h = int(size.y)
	base_pos = Vector2(TankConst.REAR_SCREEN_X, TankConst.GROUND_Y - GROUND_GAP - hull_h)
	position = base_pos
	gear = TankRunningGear.new()
	gear.assemble(def)
	add_child(gear)
	hull_sprite = Sprite2D.new()
	hull_sprite.name = "Hull"
	hull_sprite.texture = TankSprites.tex(TankSprites.hull_id(tank))
	hull_sprite.centered = false
	add_child(hull_sprite)
	var cutaway := TankPainter.new()
	cutaway.name = "Cutaway"
	cutaway.painter = _paint_cutaway
	add_child(cutaway)
	_build_rooms()
	_build_links()
	_build_stack()
	_build_guns()
	dozer = TankPainter.new()
	dozer.name = "Dozer"
	dozer.painter = _paint_dozer
	add_child(dozer)


## The x-ray cut behind the rooms: one near-black recess spanning every room rect (grown by the
## bulkhead width), with a bevel (a lit lower lip, a shadowed upper edge), so the walls between
## rooms are dark and each room is marked only by its own light.
func _paint_cutaway(item: Node2D) -> void:
	var band := Rect2()
	var first := true
	for rd: Variant in def.get("rooms", []):
		var r := TankRigs.rect((rd as Dictionary).get("rect", [0, 0, 96, 48]))
		band = r if first else band.merge(r)
		first = false
	if first:
		return
	band = band.grow(3.0)
	item.draw_rect(band.grow(1.0), TankPalette.IRON_DARK)
	item.draw_rect(band, TankPalette.SOOT)
	item.draw_rect(Rect2(band.position, Vector2(band.size.x, 1.0)), TankPalette.BLACK)
	item.draw_rect(
		Rect2(Vector2(band.position.x, band.end.y), Vector2(band.size.x, 1.0)), TankPalette.STEEL
	)


func _build_rooms() -> void:
	for rd: Variant in def.get("rooms", []):
		var room_def: Dictionary = rd
		var room: TankRoomView = null
		match str(room_def.get("engine", "")):
			TankIds.ENGINE_DIESEL:
				room = TankDieselRoom.new()
			TankIds.ENGINE_BULWARK:
				room = TankBulwarkRoom.new()
			TankIds.ENGINE_DYNAMO:
				room = TankDynamoRoom.new()
			TankIds.ENGINE_STEAM:
				room = TankSteamRoom.new()
		if room == null:
			continue
		room.assemble(room_def, TankRigs.machinery(), hub)
		add_child(room)
		rooms.append(room)
		if room is TankDieselRoom and diesel_room == null:
			diesel_room = room
		elif room is TankDynamoRoom:
			dynamo_room = room
		elif room is TankSteamRoom:
			steam_room = room


func _build_links() -> void:
	links = Node2D.new()
	links.name = "Links"
	add_child(links)
	var sprocket := TankRigs.vec(def.get("drive_sprocket"))
	if diesel_room != null:
		var from := diesel_room.rect.position + diesel_room.anchor_local("flywheel")
		var r_from := 7.0
		if diesel_room is TankBulwarkRoom:
			from = diesel_room.rect.position + (diesel_room as TankBulwarkRoom).outputs[0]
			r_from = 5.0
		# A heavy 2 px dark chain with moving links, routed like a real drive: down from the
		# flywheel's sprocket to the room floor, along the floor to the rear, then straight down
		# through the belly to the drive sprocket (never a diagonal across the room).
		drive_chain = _chain("DriveChain", 70.0, TankPalette.STEEL_LIGHT, TankPalette.IRON)
		drive_chain.pitch_px = 3.0
		drive_chain.link_px = 2.0
		drive_chain.width_px = 2.0
		drive_chain.closed = false
		var floor_y := maxf(from.y + r_from, diesel_room.rect.end.y - 3.0)
		var route := PackedVector2Array([from + Vector2(0, r_from)])
		for p: Vector2 in [
			Vector2(from.x, floor_y), Vector2(sprocket.x, floor_y), sprocket + Vector2(0, -8.0)
		]:
			if p.distance_to(route[route.size() - 1]) > 0.5:
				route.append(p)
		drive_chain.points = route
	var ring := TankRigs.vec((def.get("turret", {}) as Dictionary).get("ring"))
	var shaft_from := Vector2.ZERO
	var has_shaft := false
	if dynamo_room != null:
		shaft_from = dynamo_room.armature_hull_pos()
		has_shaft = true
	elif diesel_room is TankBulwarkRoom:
		shaft_from = diesel_room.rect.position + (diesel_room as TankBulwarkRoom).outputs[1]
		has_shaft = true
	if has_shaft:
		var top_y := (
			(dynamo_room.rect.position.y if dynamo_room != null else diesel_room.rect.position.y)
			+ 3.0
		)
		# A solid 2 px steel rod (the bed) with a highlight stripe turning along it while slewing.
		slew_shaft = _chain("TurretShaft", 60.0, TankPalette.STEEL_PALE, TankPalette.STEEL_DARK)
		slew_shaft.pitch_px = 7.0
		slew_shaft.link_px = 2.0
		slew_shaft.closed = false
		slew_shaft.points = PackedVector2Array(
			[shaft_from, Vector2(shaft_from.x, top_y), Vector2(ring.x, top_y), ring]
		)
	if dynamo_room != null and steam_room == null:
		dynamo_room.has_hoist = true
		var rail := _rail_points()
		hoist_chain = _chain("HoistChain", 50.0, TankPalette.STEEL_LIGHT, TankPalette.IRON)
		hoist_chain.pitch_px = 3.0
		hoist_chain.link_px = 2.0
		hoist_chain.width_px = 2.0
		hoist_chain.closed = false
		var foot_y := dynamo_room.rect.end.y - 3.0
		hoist_chain.points = PackedVector2Array(
			[
				dynamo_room.armature_hull_pos(),
				Vector2(dynamo_room.armature_hull_pos().x, foot_y),
				Vector2(rail[0].x, foot_y),
				rail[0]
			]
		)
	var beds := TankPainter.new()
	beds.name = "LinkBeds"
	beds.painter = _paint_link_beds
	links.add_child(beds)
	for ch: ScrollingChain in [drive_chain, slew_shaft, hoist_chain]:
		if ch != null:
			links.add_child(ch)
	if steam_room != null or hoist_chain != null:
		rails = TankPainter.new()
		rails.name = "HoistRail"
		rails.painter = _paint_rails
		links.add_child(rails)


## The solid bodies under the moving links: the drive chain coal-dark, the turret shaft a steel rod
## with a lit upper pixel, the hoist chain dark.
func _paint_link_beds(item: Node2D) -> void:
	TankRunningGear.paint_bed(item, drive_chain, 2.0, TankPalette.IRON_DARK)
	TankRunningGear.paint_bed(item, hoist_chain, 2.0, TankPalette.IRON_DARK)
	if slew_shaft != null:
		TankRunningGear.paint_bed(item, slew_shaft, 2.0, TankPalette.STEEL_DARK)
		var pts := slew_shaft.points
		for i in range(pts.size() - 1):
			if absf(pts[i].y - pts[i + 1].y) < 0.5:
				item.draw_line(
					pts[i] + Vector2(0, -1), pts[i + 1] + Vector2(0, -1), TankPalette.STEEL, 1.0
				)


func _chain(chain_name: String, px_s: float, a: Color, b: Color) -> ScrollingChain:
	var c := ScrollingChain.new()
	c.name = chain_name
	c.pitch_px = 4.0
	c.link_px = 2.0
	c.width_px = 1.0
	c.color_a = a
	c.color_b = b
	c.max_px_s = px_s
	c.inertia_s = 0.2
	c.auto_process = false
	return c


func _build_stack() -> void:
	_stack_pos = TankRigs.vec(def.get("exhaust"))
	stack = TankPainter.new()
	stack.name = "Stack"
	stack.painter = _paint_stack
	add_child(stack)


func _build_guns() -> void:
	for sd: Variant in def.get("secondaries", []):
		var s := TankSecondaryView.new()
		s.assemble(sd)
		add_child(s)
		secondaries.append(s)
	turret = TankTurretView.new()
	turret.assemble(tank, def.get("turret", {}))
	add_child(turret)


# --- Per frame -----------------------------------------------------------------------------------


## One frame: the rooms from the riders' `feed` (peer -> Vector2(raw_w, cadence)), the running gear
## from the hull's speed, the turret from the gun's state, links and effects.
func update(state: TankState, feed: Dictionary, dt: float) -> void:
	var hl := state.hull
	_update_shake(dt)
	hub.origin = position
	gear.update(hl.speed_mps * TankConst.PX_PER_M, dt)
	if dynamo_room != null:
		dynamo_room.breech_loaded = hl.loaded != TankIds.SHELL_NONE
	for room in rooms:
		room.feed(_room_input(room, state, feed), dt)
	_update_slew(hl, dt)
	turret.update(hl.facing, hl.elev_deg, hl.traverse_s, dt)
	for s in secondaries:
		s.update(dt)
	_update_links(state, dt)
	_update_blade(state, dt)
	_effects(state, dt)
	if _flash_s > 0.0:
		_flash_s = maxf(0.0, _flash_s - dt)
		var k := _flash_s / HIT_FLASH_S
		hull_sprite.modulate = Color(1.0 + 0.7 * k, 1.0 + 0.5 * k, 1.0 + 0.3 * k)
	stack.queue_redraw()
	dozer.queue_redraw()
	if rails != null:
		rails.queue_redraw()


## The input of `room` this frame (the station, its rider's watts and cadence, the flags).
func _room_input(room: TankRoomView, state: TankState, feed: Dictionary) -> TankRoomInput:
	var inp := TankRoomInput.new()
	var st := state.station(room.engine)
	room.station = st
	if st == null:
		inp.unpowered = true
		return inp
	inp.slot = st.slot
	inp.reserve = st.reserve
	inp.unpowered = st.unpowered or state.all_afk
	inp.in_band = st.in_band and not st.reserve
	var r := state.rider_at(st.slot) if st.slot >= 0 else null
	if r != null and not st.reserve:
		var f: Vector2 = feed.get(r.peer, Vector2(r.raw_w, r.cadence_rpm))
		inp.watts = f.x
		inp.cadence = f.y
		inp.frac = f.x / maxf(r.ftp, 1.0)
		inp.own = r.peer == hub.local_peer
	else:
		# Reserve (brief 2.2): the room runs as if P_eff 60 W under Autopilot.
		inp.watts = 60.0
		inp.cadence = 45.0
		inp.frac = 60.0 / maxf(r.ftp if r != null else 200.0, 1.0)
	inp.look = hub.look(st.slot)
	return inp


func _update_slew(hl: TankHullState, dt: float) -> void:
	var rate := absf(hl.elev_deg - _elev_prev) / maxf(dt, 0.0001)
	_elev_prev = hl.elev_deg
	if hl.traverse_s > 0.0 or rate > 2.0:
		_slew_hold = SLEW_HOLD_S
	else:
		_slew_hold = maxf(0.0, _slew_hold - dt)
	slewing = _slew_hold > 0.0


func _update_links(_state: TankState, dt: float) -> void:
	if drive_chain != null:
		var sp := diesel_room.input.speed()
		if diesel_room is TankBulwarkRoom:
			sp = sp if (diesel_room as TankBulwarkRoom).active_output() == 0 else 0.0
		drive_chain.speed = sp
		drive_chain.tick(dt)
	if slew_shaft != null:
		var turn := 0.0
		if slewing:
			if dynamo_room != null:
				turn = 0.0 if dynamo_room.input.unpowered else 1.0
			elif diesel_room is TankBulwarkRoom:
				turn = 1.0 if (diesel_room as TankBulwarkRoom).active_output() == 1 else 0.0
		slew_shaft.speed = turn
		slew_shaft.tick(dt)
	if hoist_chain != null:
		hoist_chain.speed = 1.0 if dynamo_room.hoisting() else 0.0
		hoist_chain.tick(dt)


func _update_blade(state: TankState, dt: float) -> void:
	var dig := state.gun_line.active and state.hull.holding
	blade = move_toward(blade, 1.0 if dig else 0.0, BLADE_EASE_PER_S * dt)
	berm_hp = state.hull.berm_hp


func _effects(state: TankState, dt: float) -> void:
	var fx := hub.fx
	if fx == null:
		return
	var hl := state.hull
	if diesel_room != null:
		fx.exhaust(
			"stack", hub.to_layer(_stack_pos + Vector2(0, -10)), diesel_room.exhaust_frac(), dt
		)
	var ground_y := float(hull_h + GROUND_GAP)
	fx.track_dust("tracks", hub.to_layer(Vector2(2.0, ground_y)), hl.speed_mps, dt)
	if dynamo_room != null:
		var frac := (
			0.0
			if (dynamo_room.input.unpowered or dynamo_room.stalled())
			else dynamo_room.input.frac
		)
		fx.dynamo_sparks("arc", hub.to_layer(dynamo_room.armature_hull_pos()), frac, dt)
	if steam_room != null:
		if steam_room.take_stroke():
			fx.steam_puff(hub.to_layer(steam_room.chimney_hull()))
		if steam_room.latched_now:
			fx.steam_burst(hub.to_layer(steam_room.chimney_hull()))
	if hl.breakdown:
		fx.fire_and_smoke("hull_down", hub.to_layer(Vector2(hull_w * 0.4, 0)), 0.5, 1.2, dt)
	elif hl.hp_max > 0.0 and hl.hp / hl.hp_max < 0.3:
		fx.fire_and_smoke("hull_low", hub.to_layer(Vector2(hull_w * 0.55, 0)), 0.0, 0.6, dt)


func _update_shake(dt: float) -> void:
	shake_amp *= exp(-SHAKE_DECAY * dt)
	if shake_amp < 0.2:
		shake_amp = 0.0
		shake_offset = Vector2.ZERO
	else:
		var a := shake_amp
		shake_offset = Vector2.ZERO
		if hub != null and hub.fx != null:
			var rng := hub.fx.rng
			shake_offset = Vector2(
				roundf(rng.randf_range(-a, a)), roundf(rng.randf_range(-a, a) * 0.6)
			)
	position = base_pos + shake_offset


# --- Events from the view ----------------------------------------------------------------------------


## The main gun fired: recoil, shake, blast, brass.
func fire_main(strength: float = 0.6) -> void:
	turret.kick(0.5 + strength)
	add_shake(1.2 + 2.0 * strength)
	if hub == null or hub.fx == null:
		return
	hub.fx.muzzle_blast(muzzle_layer(), muzzle_dir(), strength)
	var back := Vector2(-signf(turret.scale.x) * 0.6, -1.0).normalized()
	hub.fx.brass(hub.to_layer(turret.ring + Vector2(-14.0 * signf(turret.scale.x), -22.0)), back)


## Secondary `index` (0 fore, 1 aft) fired.
func fire_secondary(index: int) -> void:
	if index < 0 or index >= secondaries.size():
		return
	var s := secondaries[index]
	s.kick()
	if hub != null and hub.fx != null:
		hub.fx.small_blast(
			hub.to_layer(s.muzzle_hull()), Vector2(float(s.facing), -0.1).normalized()
		)


## A hit landed on the hull: a flash and a shake.
func hit(strength: float = 0.5) -> void:
	_flash_s = HIT_FLASH_S
	add_shake(1.5 + 2.5 * strength)


## The crew changed stations (a checkpoint): every room's lamp flares for a moment.
func flash_rooms() -> void:
	for room in rooms:
		room.flare_s = TankRoomView.FLARE_S


func add_shake(amp: float) -> void:
	shake_amp = minf(maxf(shake_amp, amp), 4.0)


## The main muzzle in layer coordinates and the unit vector it points along.
func muzzle_layer() -> Vector2:
	return hub.to_layer(turret.muzzle_hull())


func muzzle_dir() -> Vector2:
	var a := deg_to_rad(turret.elev)
	return Vector2(cos(a) * signf(turret.scale.x), -sin(a))


## A point on the hull in layer coordinates.
func hull_point(p: Vector2) -> Vector2:
	return base_pos + p


# --- Drawing -------------------------------------------------------------------------------------------


func _paint_stack(item: Node2D) -> void:
	var p := _stack_pos
	item.draw_rect(Rect2(p.x - 3, p.y - 9, 6, 10), TankPalette.STEEL_DARK)
	item.draw_rect(Rect2(p.x - 3, p.y - 9, 6, 1), TankPalette.STEEL_LIGHT)
	item.draw_rect(Rect2(p.x - 4, p.y - 11, 8, 2), TankPalette.STEEL)
	item.draw_rect(Rect2(p.x - 3, p.y - 4, 6, 1), TankPalette.RUST)


## The hoist rail's foot and top in the hull frame: the Citadel's from rigs.json (its steam room),
## the Rampart's `hoist_rail` of the tank def or else a rail in the rear bay behind the dynamo.
func _rail_points() -> Array[Vector2]:
	var rail: Array = []
	if steam_room != null:
		rail = steam_room.def.get("hoist_rail", [])
	elif dynamo_room != null:
		rail = def.get("hoist_rail", [])
		if rail.size() < 2:
			var x := dynamo_room.rect.end.x + 20.0
			rail = [[x, dynamo_room.rect.end.y - 2.0], [x, 10.0]]
	if rail.size() < 2:
		return []
	return [TankRigs.vec(rail[0]), TankRigs.vec(rail[1])]


func _paint_rails(item: Node2D) -> void:
	var pts := _rail_points()
	if pts.size() < 2:
		return
	var a := pts[0]
	var b := pts[1]
	var ring := TankRigs.vec((def.get("turret", {}) as Dictionary).get("ring"))
	var feed_to := Vector2(ring.x + 16.0, b.y)
	for dx in [-2.0, 2.0]:
		item.draw_line(a + Vector2(dx, 0), b + Vector2(dx, 0), TankPalette.STEEL, 1.0)
	var y := a.y
	while y > b.y:
		item.draw_line(Vector2(a.x - 2, y), Vector2(a.x + 2, y), TankPalette.IRON, 1.0)
		y -= 6.0
	item.draw_line(b, feed_to, TankPalette.STEEL_DARK, 2.0)
	item.draw_line(feed_to, Vector2(feed_to.x, 0.0), TankPalette.STEEL_DARK, 2.0)
	var t := cradle_t()
	var at := a.lerp(b, t)
	item.draw_rect(Rect2(at.x - 3, at.y - 2, 6, 3), TankPalette.STEEL)
	item.draw_rect(Rect2(at.x - 2, at.y - 10, 4, 8), TankPalette.MUD_PALE)
	item.draw_rect(Rect2(at.x - 2, at.y - 10, 1, 8), TankPalette.CLAY)
	item.draw_rect(Rect2(at.x - 2, at.y - 4, 4, 2), TankPalette.MUD_LIGHT)
	item.draw_rect(Rect2(at.x - 1, at.y - 12, 2, 2), TankPalette.STEEL)


## The hull's flat roof in layer coordinates (x, y, width; height 0) for the wet-steel specular:
## the longest run of columns whose first opaque row is the sprite's topmost, measured once from
## the hull texture the view draws (so the line sits on the steel, never above a lower deck).
func hull_roof() -> Rect2:
	if _roof.size.x > 0.0 or _roof_done:
		return _roof
	_roof_done = true
	var img := TankSprites.tex(TankSprites.hull_id(tank)).get_image()
	if img == null or img.is_empty():
		return _roof
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var tops := PackedInt32Array()
	tops.resize(w)
	var min_top := img.get_height()
	for x in w:
		tops[x] = img.get_height()
		for y in img.get_height():
			if img.get_pixel(x, y).a > 0.5:
				tops[x] = y
				break
		min_top = mini(min_top, tops[x])
	var best_x := 0
	var best_n := 0
	var run_x := 0
	var run_n := 0
	for x in w:
		if tops[x] <= min_top + 1:
			if run_n == 0:
				run_x = x
			run_n += 1
			if run_n > best_n:
				best_n = run_n
				best_x = run_x
		else:
			run_n = 0
	var sx := float(hull_w) / float(maxi(w, 1))
	_roof = Rect2(
		base_pos + Vector2(float(best_x + 2) * sx, float(min_top)),
		Vector2(maxf(float(best_n - 4) * sx, 0.0), 0.0)
	)
	return _roof


## The shell cradle on the hoist rail, 0 (foot) .. 1 (breech): the steam engine's or the Rampart's.
func cradle_t() -> float:
	if steam_room != null:
		return steam_room.cradle_t
	return dynamo_room.hoist_t if dynamo_room != null else 0.0


func _paint_dozer(item: Node2D) -> void:
	var ground := float(hull_h + GROUND_GAP)
	var x0 := float(hull_w)
	# The arm and the blade: raised 14 px while driving, on the ground when dug in.
	var lift := 14.0 * (1.0 - blade)
	var bx := x0 + 8.0
	var by := ground - 16.0 - lift
	# Hull steel: a heavy push arm from the glacis foot to the blade's back, and the blade as one
	# solid curved slab (concave face forward, 16 px tall, 4-6 px thick) with a lit top edge, a dark
	# cutting edge and a lip of mud packed on it.
	var foot := Vector2(x0 - 4.0, ground - 14.0)
	item.draw_line(foot, Vector2(bx + 1.0, by + 9.0), TankPalette.IRON_DARK, 4.0)
	item.draw_line(foot + Vector2(0, -2), Vector2(bx + 1.0, by + 7.0), TankPalette.IRON, 1.0)
	item.draw_rect(Rect2(x0 - 7.0, ground - 18.0, 5, 7), TankPalette.IRON)
	item.draw_rect(Rect2(x0 - 7.0, ground - 18.0, 5, 1), TankPalette.STEEL_DARK)
	var face := PackedVector2Array(
		[
			Vector2(bx, by),
			Vector2(bx + 6.0, by - 1.0),
			Vector2(bx + 4.0, by + 4.0),
			Vector2(bx + 3.0, by + 9.0),
			Vector2(bx + 4.0, by + 13.0),
			Vector2(bx + 7.0, by + 16.0),
			Vector2(bx, by + 16.0),
			Vector2(bx - 1.0, by + 8.0),
		]
	)
	item.draw_colored_polygon(face, TankPalette.IRON)
	item.draw_polyline(
		PackedVector2Array([face[1], face[2], face[3], face[4], face[5]]),
		TankPalette.STEEL_DARK,
		1.0
	)
	item.draw_line(face[0], face[1], TankPalette.SLATE, 1.0)
	item.draw_line(Vector2(bx, by + 15.0), Vector2(bx + 7.0, by + 15.0), TankPalette.COAL, 1.0)
	item.draw_rect(Rect2(bx + 3.0, by + 12.0, 4, 3), TankPalette.MUD)
	item.draw_rect(Rect2(bx + 4.0, by + 11.0, 2, 1), TankPalette.MUD_LIGHT)
	if berm_hp > 0.5:
		var h := 3.0 + (BERM_MAX_H - 3.0) * clampf(berm_hp / 40.0, 0.0, 1.0)
		var pts := PackedVector2Array(
			[
				Vector2(bx + 4.0, ground),
				Vector2(bx + 9.0, ground - h * 0.8),
				Vector2(bx + 14.0, ground - h),
				Vector2(bx + BERM_W - 8.0, ground - h * 0.9),
				Vector2(bx + BERM_W, ground)
			]
		)
		item.draw_colored_polygon(pts, TankPalette.MUD)
		item.draw_polyline(PackedVector2Array([pts[1], pts[2], pts[3]]), TankPalette.MUD_PALE, 1.0)
		item.draw_rect(Rect2(bx + 12.0, ground - h * 0.5, 2, 2), TankPalette.MUD_DARK)
		item.draw_rect(Rect2(bx + 20.0, ground - h * 0.35, 3, 2), TankPalette.MUD_DARK)
