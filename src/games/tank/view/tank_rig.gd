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
## Barbette width under the secondary turrets (art px).
const BARBETTE_W := 12.0

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
## The hull sprite measured once: the first opaque row of every column and the last opaque column of
## every row (-1 for none), so the stack stands on the deck and the blade meets the nose.
var _col_top: PackedInt32Array = PackedInt32Array()
var _row_right: PackedInt32Array = PackedInt32Array()
## The x-ray drive sprocket the diesel chain ends on (drawn over the hull, toothed, turning).
var sprocket_paint: TankPainter = null
## Where the drive chain leaves its engine (the flywheel shaft's small sprocket or the gearbox's
## drive output) and that sprocket's radius.
var _chain_from: Vector2 = Vector2.ZERO
var _chain_r: float = 3.0
## The steam engine's deck vent (hull frame, its mouth): white steam on every stroke.
var _vent: Vector2 = Vector2(-1, -1)
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
	_measure_hull()
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
		var r_from := 3.0
		if diesel_room is TankBulwarkRoom:
			from = diesel_room.rect.position + (diesel_room as TankBulwarkRoom).outputs[0]
			r_from = TankBulwarkRoom.GEAR_R
		# A heavy 2 px chain with alternating link tones, routed like a real final drive: down from a
		# small sprocket on the flywheel shaft (or the gearbox's drive output) through the room floor
		# onto the skirt, then back along the skirt, sloping onto the drive sprocket's teeth at the
		# rear. It runs over the plain skirt plate, so it reads end to end.
		drive_chain = _chain("DriveChain", 70.0, TankPalette.SILVER, TankPalette.COAL)
		drive_chain.pitch_px = 4.0
		drive_chain.link_px = 2.0
		drive_chain.width_px = 2.0
		drive_chain.closed = false
		var run_y := minf(
			float(TankPlaceholderArt.skirt_row(TankSprites.hull_id(tank))) + 6.0,
			float(hull_h) - 3.0
		)
		var r_spr := TankRunningGear.SPROCKET_R
		_chain_from = from
		_chain_r = r_from
		var route := PackedVector2Array([from + Vector2(0, r_from)])
		for p: Vector2 in [
			Vector2(from.x, run_y),
			Vector2(sprocket.x + r_spr + 10.0, run_y),
			sprocket + Vector2(r_spr * 0.8, -r_spr * 0.6)
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
	if drive_chain != null:
		sprocket_paint = TankPainter.new()
		sprocket_paint.name = "DriveSprocket"
		sprocket_paint.painter = _paint_sprocket
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
	if sprocket_paint != null:
		links.add_child(sprocket_paint)
	if steam_room != null or hoist_chain != null or diesel_room is TankBulwarkRoom:
		rails = TankPainter.new()
		rails.name = "HoistRail"
		rails.painter = _paint_rails
		links.add_child(rails)


## The solid bodies under the moving links: the drive chain coal-dark, the turret shaft a steel rod
## with a lit upper pixel, the hoist chain dark.
func _paint_link_beds(item: Node2D) -> void:
	if drive_chain != null:
		# The slot the chain runs in through the belly: a dark channel with a lit lower lip.
		TankRunningGear.paint_bed(item, drive_chain, 4.0, TankPalette.BLACK)
	TankRunningGear.paint_bed(item, drive_chain, 2.0, TankPalette.IRON_DARK)
	TankRunningGear.paint_bed(item, hoist_chain, 2.0, TankPalette.IRON_DARK)
	if slew_shaft != null:
		TankRunningGear.paint_bed(item, slew_shaft, 2.0, TankPalette.STEEL_DARK)
		# The Bulwark's turret shaft catches a warm rim light while the lever drives it.
		var lit := (
			diesel_room is TankBulwarkRoom and (diesel_room as TankBulwarkRoom).active_output() == 1
		)
		var rim := TankPalette.with_alpha(TankPalette.AMBER, 0.7) if lit else TankPalette.STEEL
		var pts := slew_shaft.points
		for i in range(pts.size() - 1):
			if absf(pts[i].y - pts[i + 1].y) < 0.5:
				item.draw_line(pts[i] + Vector2(0, -1), pts[i + 1] + Vector2(0, -1), rim, 1.0)
			elif lit:
				item.draw_line(pts[i] + Vector2(-1, 0), pts[i + 1] + Vector2(-1, 0), rim, 1.0)


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
	# Stand the stack on the deck: the lowest deck row under its 8 px foot, measured on the sprite.
	var deck := -1
	for x in range(int(_stack_pos.x) - 4, int(_stack_pos.x) + 4):
		if x >= 0 and x < _col_top.size() and _col_top[x] >= 0:
			deck = maxi(deck, _col_top[x])
	if deck >= 0:
		_stack_pos.y = float(deck)
	if steam_room != null:
		# The steam engine's exhaust vent stands on the deck above its room, clear of the turrets.
		var vx := int(steam_room.rect.position.x + 36.0)
		var vdeck := -1
		for x in range(vx - 2, vx + 3):
			if x >= 0 and x < _col_top.size() and _col_top[x] >= 0:
				vdeck = maxi(vdeck, _col_top[x])
		if vdeck >= 0:
			_vent = Vector2(float(vx), float(vdeck) - 7.0)
	stack = TankPainter.new()
	stack.name = "Stack"
	stack.painter = _paint_stack
	add_child(stack)


func _build_guns() -> void:
	if not (def.get("secondaries", []) as Array).is_empty():
		var bb := TankPainter.new()
		bb.name = "Barbettes"
		bb.painter = _paint_barbettes
		add_child(bb)
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
	if sprocket_paint != null:
		sprocket_paint.queue_redraw()
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
			"stack", hub.to_layer(_stack_pos + Vector2(0, -16)), diesel_room.exhaust_frac(), dt
		)
	var ground_y := float(hull_h + GROUND_GAP)
	var rear := TankRigs.vec(def.get("drive_sprocket"))
	fx.track_dust("tracks", hub.to_layer(Vector2(rear.x - 6.0, ground_y - 3.0)), hl.speed_mps, dt)
	if dynamo_room != null:
		var frac := (
			0.0
			if (dynamo_room.input.unpowered or dynamo_room.stalled())
			else dynamo_room.input.frac
		)
		fx.dynamo_sparks("arc", hub.to_layer(dynamo_room.armature_hull_pos()), frac, dt)
	if rails != null and hub.lights != null:
		var lamp := hub.to_layer(cradle_pos().round() + Vector2(2.5, 0.5))
		hub.lights.add(lamp, 6.0, TankPalette.AMBER, 0.55)
	if steam_room != null:
		if steam_room.take_stroke():
			# Every stroke: a white plume out of the deck vent, clear of the deck (world plane), and
			# two small wisps from the cylinder's drain cock that stay in the room with the hull (a
			# full puff there would hide the crosshead and the shell rack).
			if _vent.x >= 0.0:
				fx.steam_plume(hub.to_layer(_vent))
			else:
				fx.steam_puff(hub.to_layer(steam_room.chimney_hull()))
			var drain := hub.to_layer(steam_room.drain_hull())
			for _i in 2:
				fx.particles.spawn(
					TankParticles.Kind.STEAM,
					drain + Vector2(fx.r(-1.0, 1.0), 0.0),
					Vector2(fx.r(-6.0, 6.0), fx.r(-20.0, -12.0)),
					fx.r(0.3, 0.45),
					1.5,
					fx.r(4.0, 6.0),
					Color(TankPalette.WHITE_COLD, 0.6),
					-4.0,
					1.6,
					TankParticles.PLANE_HULL
				)
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
	# The spent casing leaves through the turret's rear hatch, up and back, tumbling.
	var back := Vector2(-signf(turret.scale.x) * 0.8, -1.0).normalized()
	hub.fx.brass(hub.to_layer(turret_rear()), back)


## The turret's rear hatch in the hull frame for the shown facing (where casings are ejected).
func turret_rear() -> Vector2:
	var tr := TankRigs.rect((def.get("turret", {}) as Dictionary).get("rect", [0, -30, 80, 30]))
	var x := tr.position.x + 5.0
	var y := tr.position.y + tr.size.y * 0.4
	if turret.scale.x < 0.0:
		x = turret.ring.x * 2.0 - x
	return Vector2(x, y)


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


## Measures the hull sprite once (_col_top, _row_right).
func _measure_hull() -> void:
	_col_top.resize(hull_w)
	_col_top.fill(-1)
	_row_right.resize(hull_h)
	_row_right.fill(-1)
	var img := hull_sprite.texture.get_image() if hull_sprite.texture != null else null
	if img == null or img.is_empty():
		return
	if img.is_compressed():
		img.decompress()
	var w := mini(img.get_width(), hull_w)
	var h := mini(img.get_height(), hull_h)
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.5:
				if _col_top[x] < 0:
					_col_top[x] = y
				_row_right[y] = x


## The hull's front edge (last opaque column) at hull-frame row `y`; below the hull, the idler's front.
func nose_x(y: float) -> float:
	var yi := int(y)
	if yi >= 0 and yi < _row_right.size() and _row_right[yi] >= 0:
		return float(_row_right[yi])
	if yi >= hull_h:
		var idl := TankRigs.vec(def.get("idler"))
		return idl.x + TankRunningGear.IDLER_R
	return float(hull_w)


## The exhaust stack standing on the deck: a foot flange bolted to the deck, the pipe with a lit edge
## and a soot-black band, and a rain cap.
func _paint_stack(item: Node2D) -> void:
	var p := _stack_pos
	item.draw_rect(Rect2(p.x - 5, p.y - 2, 10, 3), TankPalette.IRON)
	item.draw_rect(Rect2(p.x - 5, p.y - 2, 10, 1), TankPalette.STEEL)
	item.draw_rect(Rect2(p.x - 3, p.y - 14, 6, 12), TankPalette.STEEL_DARK)
	item.draw_rect(Rect2(p.x - 3, p.y - 14, 1, 12), TankPalette.STEEL)
	item.draw_rect(Rect2(p.x + 2, p.y - 14, 1, 12), TankPalette.IRON_DARK)
	item.draw_rect(Rect2(p.x - 3, p.y - 7, 6, 1), TankPalette.RUST_DARK)
	item.draw_rect(Rect2(p.x - 4, p.y - 16, 8, 2), TankPalette.STEEL)
	item.draw_rect(Rect2(p.x - 3, p.y - 14, 6, 2), TankPalette.SOOT)
	if _vent.x < 0.0:
		return
	# The steam vent: a slim pipe on a flange with a flared, soot-free mouth.
	var v := _vent
	item.draw_rect(Rect2(v.x - 3, v.y + 6, 7, 2), TankPalette.IRON)
	item.draw_rect(Rect2(v.x - 3, v.y + 6, 7, 1), TankPalette.STEEL)
	item.draw_rect(Rect2(v.x - 1, v.y + 1, 3, 6), TankPalette.STEEL_DARK)
	item.draw_rect(Rect2(v.x - 1, v.y + 1, 1, 6), TankPalette.STEEL_LIGHT)
	item.draw_rect(Rect2(v.x - 2, v.y, 5, 2), TankPalette.STEEL)
	item.draw_rect(Rect2(v.x - 1, v.y, 3, 1), TankPalette.SOOT)


## The barbette under every secondary turret, so none floats over the sloped glacis or the low rear
## deck: a riveted steel cylinder BARBETTE_W px wide from the turret's underside down into the hull
## (the lowest deck row under it, measured on the sprite), shaded round (a lit left edge, a dark
## right one), with a collar under the turret and a rivet row.
func _paint_barbettes(item: Node2D) -> void:
	for sd: Variant in def.get("secondaries", []):
		var sdd: Dictionary = sd
		var r := barbette_rect(TankRigs.rect(sdd.get("rect")), int(sdd.get("facing", 1)))
		if r.size.y < 1.0:
			continue
		var shades: Array[Color] = [
			TankPalette.STEEL,
			TankPalette.STEEL_DARK,
			TankPalette.IRON,
			TankPalette.IRON,
			TankPalette.IRON_DARK,
			TankPalette.COAL,
		]
		var w := int(r.size.x)
		for i in w:
			var k := int(float(i) / float(w) * float(shades.size()))
			item.draw_rect(
				Rect2(r.position.x + float(i), r.position.y, 1, r.size.y), shades[mini(k, 5)]
			)
		item.draw_rect(
			Rect2(r.position.x - 1.0, r.position.y, r.size.x + 2.0, 2.0), TankPalette.IRON
		)
		item.draw_rect(
			Rect2(r.position.x - 1.0, r.position.y, r.size.x + 2.0, 1.0), TankPalette.STEEL
		)
		item.draw_rect(
			Rect2(r.position.x - 1.0, r.position.y + 2.0, r.size.x + 2.0, 1.0), TankPalette.COAL
		)
		var x := r.position.x + 2.0
		while x < r.end.x - 1.0:
			item.draw_rect(Rect2(x, r.position.y + 4.0, 1, 1), TankPalette.STEEL_PALE)
			x += 3.0


## The barbette rect (hull frame) under a secondary turret drawn at `tr` facing `facing`: under its
## rear half (toward the deck, away from the gun), from 3 px above its bottom down to 2 px below the
## lowest deck row under the barbette (height 0 when the turret already sits on the deck).
func barbette_rect(tr: Rect2, facing: int = 1) -> Rect2:
	var cx := roundf(tr.position.x + tr.size.x * (0.38 if facing > 0 else 0.62))
	var x0 := int(cx - BARBETTE_W * 0.5)
	var top := tr.end.y - 3.0
	var deck := -1
	for x in range(x0, x0 + int(BARBETTE_W)):
		if x >= 0 and x < _col_top.size() and _col_top[x] >= 0:
			deck = maxi(deck, _col_top[x])
	if deck < 0:
		deck = int(top)
	var bottom := float(deck) + 2.0
	return Rect2(float(x0), top, BARBETTE_W, maxf(bottom - top, 0.0))


## The drive sprocket in x-ray where the diesel's chain ends: a lighter toothed ring whose ten teeth
## are cut by 1 px dark notches, turning with the running gear, on a dark disc with a lit hub and the
## chain's amber catch-light, unlike the road wheels.
func _paint_sprocket(item: Node2D) -> void:
	var c := TankRigs.vec(def.get("drive_sprocket"))
	var ang := gear.wheels[0].angle() if not gear.wheels.is_empty() else 0.0
	var r := TankRunningGear.SPROCKET_R
	item.draw_circle(c, r + 0.5, TankPalette.BLACK)
	item.draw_circle(c, r - 0.5, TankPalette.STEEL)
	item.draw_arc(c, r - 0.5, PI * 1.1, PI * 1.8, 10, TankPalette.STEEL_PALE, 1.0)
	item.draw_circle(c, r - 3.0, TankPalette.IRON_DARK)
	for i in 10:
		var d := Vector2.from_angle(ang + TAU * float(i) / 10.0)
		item.draw_line(c + d * (r - 3.0), c + d * (r + 0.5), TankPalette.COAL, 1.0)
	item.draw_circle(c, 3.5, TankPalette.STEEL_DARK)
	item.draw_circle(c, 2.0, TankPalette.STEEL_LIGHT)
	item.draw_rect(Rect2(c.round() + Vector2(-1, -2), Vector2(1, 1)), TankPalette.CLAY)
	if diesel_room == null:
		return
	# The chain's warm catch-light where it drops out of the lit room.
	var glow := clampf(diesel_room.glow, 0.0, 1.0)
	var pts := drive_chain.points if drive_chain != null else PackedVector2Array()
	if glow > 0.05 and pts.size() >= 2:
		item.draw_line(
			pts[0] + Vector2(-1, 0),
			pts[1] + Vector2(-1, 0),
			TankPalette.with_alpha(TankPalette.FIRE, 0.45 * glow),
			1.0
		)
	if diesel_room is TankBulwarkRoom:
		return
	# The small drive sprocket on the flywheel's shaft the chain leaves from, turning with it.
	var f := _chain_from
	var fa := diesel_room.flywheel.angle()
	item.draw_circle(f, _chain_r + 1.0, TankPalette.BLACK)
	item.draw_circle(f, _chain_r, TankPalette.STEEL_LIGHT)
	for i in 6:
		var d := Vector2.from_angle(fa + TAU * float(i) / 6.0)
		item.draw_line(f + d * (_chain_r - 1.0), f + d * (_chain_r + 0.5), TankPalette.COAL, 1.0)
	item.draw_circle(f, 1.2, TankPalette.STEEL_DARK)


## The hoist rail's foot and top in the hull frame: the Citadel's from rigs.json (its steam room),
## the Rampart's `hoist_rail` of the tank def or else a rail in the rear bay behind the dynamo.
func _rail_points() -> Array[Vector2]:
	var rail: Array = []
	if steam_room != null:
		rail = steam_room.def.get("hoist_rail", [])
	elif diesel_room is TankBulwarkRoom:
		rail = diesel_room.def.get("hoist_rail", [])
	elif dynamo_room != null:
		rail = def.get("hoist_rail", [])
		if rail.size() < 2:
			var x := dynamo_room.rect.end.x + 20.0
			rail = [[x, dynamo_room.rect.end.y - 2.0], [x, 10.0]]
	if rail.size() < 2:
		return []
	return [TankRigs.vec(rail[0]), TankRigs.vec(rail[1])]


## The hoist's whole path in the hull frame: the rail's foot and top, then the feed up through the
## turret ring to the main gun's breech (rigs.json `hoist_breech` of the room or the tank; without one,
## a point above the rail's top at the roof).
func rail_path() -> Array[Vector2]:
	var pts := _rail_points()
	if pts.size() < 2:
		return pts
	var b: Variant = null
	if steam_room != null:
		b = steam_room.def.get("hoist_breech")
	elif diesel_room is TankBulwarkRoom:
		b = diesel_room.def.get("hoist_breech")
	else:
		b = def.get("hoist_breech")
	pts.append(TankRigs.vec(b) if b != null else Vector2(pts[1].x, 0.0))
	return pts


## The point `t` (0 .. 1) of the way along polyline `pts` by length.
static func along(pts: Array[Vector2], t: float) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	var want := clampf(t, 0.0, 1.0) * total
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if want <= seg or i == pts.size() - 1:
			return pts[i - 1].lerp(pts[i], clampf(want / maxf(seg, 0.001), 0.0, 1.0))
		want -= seg
	return pts[0]


## The hoist rail: a dark x-ray slot with two steel rails and rungs every 6 px along its whole path,
## from the foot up and on to the main gun's breech, where a breech receiver (a cast block with a
## dark loading slot, lit amber while a shell waits in it) sits under the main turret, so the rail
## plainly feeds the main gun. In the Bulwark a shaft runs straight right from the gearbox's hoist
## gear to the rail, warm-lit and turning while the lever drives it. The cradle rides on top.
func _paint_rails(item: Node2D) -> void:
	var path := rail_path()
	if path.size() < 2:
		return
	for i in range(1, path.size()):
		item.draw_line(path[i - 1], path[i], TankPalette.SOOT, 5.0)
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)
		for side: float in [-2.0, 2.0]:
			item.draw_line(a + n * side, b + n * side, TankPalette.STEEL_LIGHT, 1.0)
		var seg := a.distance_to(b)
		var k := 3.0
		while k < seg:
			var p := a + d * k
			item.draw_line(p - n * 2.0, p + n * 2.0, TankPalette.IRON, 1.0)
			k += 6.0
	var br := path[path.size() - 1].round()
	var loaded := cradle_t() >= 0.98
	item.draw_rect(Rect2(br.x - 4, br.y - 2, 8, 5), TankPalette.BLACK)
	item.draw_rect(Rect2(br.x - 3, br.y - 1, 6, 3), TankPalette.IRON)
	item.draw_rect(Rect2(br.x - 3, br.y - 1, 6, 1), TankPalette.STEEL_LIGHT)
	item.draw_rect(Rect2(br.x - 1, br.y, 2, 2), TankPalette.AMBER if loaded else TankPalette.SOOT)
	if diesel_room is TankBulwarkRoom:
		var bw := diesel_room as TankBulwarkRoom
		var out := bw.rect.position + bw.outputs[2]
		var on := bw.active_output() == 2
		var to := Vector2(path[0].x, out.y)
		item.draw_line(out, to, TankPalette.BLACK, 4.0)
		item.draw_line(out, to, TankPalette.STEEL_DARK, 2.0)
		item.draw_line(
			out + Vector2(0, -1),
			to + Vector2(0, -1),
			TankPalette.with_alpha(TankPalette.AMBER, 0.75) if on else TankPalette.STEEL,
			1.0
		)
		# Turning: a dark stripe running along the shaft with the hoist gear.
		var ang := bw.gears[2].angle() if bw.gears.size() > 2 else 0.0
		var span := maxf(to.x - out.x, 1.0)
		var sx := out.x + fposmod(ang * 3.0, span)
		item.draw_rect(Rect2(sx, out.y - 1.0, 1.0, 2.0), TankPalette.COAL)
	var at := cradle_pos().round()
	# The cradle: a 6 x 4 steel block on the rails holding a shell upright, a small amber lamp on it.
	item.draw_rect(Rect2(at.x - 3, at.y - 1, 6, 4), TankPalette.STEEL_DARK)
	item.draw_rect(Rect2(at.x - 3, at.y - 1, 6, 1), TankPalette.STEEL_LIGHT)
	item.draw_rect(Rect2(at.x - 3, at.y + 2, 6, 1), TankPalette.COAL)
	item.draw_rect(Rect2(at.x - 1, at.y - 8, 3, 7), TankSteamRoom.BRASS_MID)
	item.draw_rect(Rect2(at.x - 1, at.y - 8, 1, 7), TankSteamRoom.BRASS_PALE)
	item.draw_rect(Rect2(at.x - 1, at.y - 3, 3, 1), TankSteamRoom.BRASS_DARK)
	item.draw_rect(Rect2(at.x - 1, at.y - 10, 3, 2), TankSteamRoom.OGIVE)
	item.draw_rect(Rect2(at.x, at.y - 11, 1, 1), TankSteamRoom.OGIVE)
	item.draw_rect(Rect2(at.x + 2, at.y, 1, 1), TankPalette.AMBER)


## The shell cradle's position on the hoist path (hull frame).
func cradle_pos() -> Vector2:
	return along(rail_path(), cradle_t())


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
	if diesel_room is TankBulwarkRoom:
		return (diesel_room as TankBulwarkRoom).hoist_fill()
	return dynamo_room.hoist_t if dynamo_room != null else 0.0


## The dozer blade: a solid curved slab (concave face forward, 16 px tall) whose back stands 1 px off
## the hull's nose at its rows (measured on the sprite, so it never floats), raised 14 px while
## driving and on the ground when dug in, pushed by two 2 px arms from the lower nose.
func _paint_dozer(item: Node2D) -> void:
	var ground := float(hull_h + GROUND_GAP)
	var lift := 14.0 * (1.0 - blade)
	var by := ground - 16.0 - lift
	var r0 := float(hull_h) - 11.0
	var r1 := float(hull_h) - 3.0
	var front := maxf(nose_x(r0), nose_x(r1))
	for yy in range(int(by), int(by) + 16):
		front = maxf(front, nose_x(float(yy)))
	var bx := front + 2.0
	for arm: Array in [[r0, by + 4.0], [r1, by + 12.0]]:
		var from := Vector2(nose_x(float(arm[0])) - 3.0, float(arm[0]))
		var to := Vector2(bx, float(arm[1]))
		item.draw_line(from, to, TankPalette.IRON_DARK, 2.0)
		item.draw_line(from + Vector2(0, -1), to + Vector2(0, -1), TankPalette.STEEL_DARK, 1.0)
		item.draw_rect(Rect2(from + Vector2(-1, -1), Vector2(3, 3)), TankPalette.IRON)
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
	# Shaded like the hull: a dark iron slab, a steel concave face, a 1 px lit lip on top, a rust
	# streak down the face, a dark bottom edge and mud packed on the cutting edge.
	item.draw_colored_polygon(face, TankPalette.IRON)
	item.draw_polyline(
		PackedVector2Array([face[1], face[2], face[3], face[4], face[5]]),
		TankPalette.STEEL_DARK,
		1.0
	)
	item.draw_line(face[0], face[1], TankPalette.STEEL_LIGHT, 1.0)
	item.draw_line(
		Vector2(bx + 3.0, by + 2.0), Vector2(bx + 2.0, by + 9.0), TankPalette.RUST_DARK, 1.0
	)
	item.draw_line(
		Vector2(bx - 1.0, by + 15.0), Vector2(bx + 7.0, by + 15.0), TankPalette.COAL, 1.0
	)
	item.draw_rect(Rect2(bx + 2.0, by + 12.0, 5, 3), TankPalette.MUD)
	item.draw_rect(Rect2(bx + 3.0, by + 11.0, 3, 1), TankPalette.MUD_LIGHT)
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
