class_name TankViewSeats
extends TankViewMotion
## TankView's seats layer: who rides what, the machines and the lights they drive, and the public effects.

# --- Seats and machines ----------------------------------------------------------------------------------


## The power the machines show: watts over the rider's target (1 = in band, 0.84-1.17).
static func power_ratio(r: TankRiderState) -> float:
	if r == null:
		return 0.0
	if r.target_pct > 0.0 and r.ftp > 0.0:
		return clampf(r.raw_w / (r.ftp * r.target_pct / 100.0), 0.0, 1.6)
	return TankMech.rider_power(r.ftp_pct)


## The station of a seat (TankIds.SEATS: by its engine), or null.
func seat_station(state: TankState, seat: String) -> TankStationState:
	return state.station(str((rig.seats.get(seat, {}) as Dictionary).get("engine", "")))


## The seat a station's engine works (or "").
func seat_of_engine(engine: String) -> String:
	for s: String in rig.seats:
		if str(rig.seats[s]["engine"]) == engine:
			return s
	return ""


func _seats(state: TankState, feed: Dictionary, render_dt: float) -> void:
	seat_riders.clear()
	seat_slots.clear()
	for seat in TankRig.SEATS:
		var st := seat_station(state, seat)
		var slot := st.slot if st != null and not st.is_empty() else -1
		var r: TankRiderState = state.rider_at(slot) if slot >= 0 else null
		seat_riders[seat] = r
		seat_slots[seat] = slot if r != null else -1
		var rpm := 0.0
		if r != null and not state.all_afk:
			var f: Vector2 = feed.get(r.peer, Vector2(r.raw_w, r.cadence_rpm))
			rpm = f.y if f.y > 1.0 else 0.0
		cadences[seat] = rpm
		phases[seat] = float(phases.get(seat, 0.0)) + rpm / 60.0 * render_dt
		powers[seat] = power_ratio(r)


## What the audio reads per seat (SPEC_AUDIO 2.2): its crank revolutions, rpm (0 when the picture
## stops the machine, as `on` in _paint), power and whether the local rider leads it.
func audio_feed(state: TankState) -> Dictionary:
	var out := {}
	var me := game.ctx.local_peer if game.ctx != null else 0
	for seat: String in TankRig.SEATS:
		var r := rider_on(seat)
		out[seat] = {
			"revs": machine_phase(seat),
			"rpm": 0.0 if state.hull.breakdown else float(cadences.get(seat, 0.0)),
			"power": machine_power(seat),
			"lead": r != null and r.peer == me,
		}
	return out


## The rider on a seat, or null (an empty seat).
func rider_on(seat: String) -> TankRiderState:
	return seat_riders.get(seat, null)


## The rider working an engine's room (v2 names: diesel, steam, dynamo, arc, bulwark), or null.
func rider_of(engine: String) -> TankRiderState:
	return rider_on(seat_of_engine(engine))


## Crank revolutions of a seat's machine (its rider's cadence integrated over render time).
func machine_phase(seat: String) -> float:
	return float(phases.get(seat, 0.0))


func machine_power(seat: String) -> float:
	return float(powers.get(seat, 0.0))


## How bright the searchlights are (0.15..1): the arc generator's (lit while its rider is in band,
## dimmed when stalled or out of band); without an arc room, lit.
func searchlight_k(state: TankState) -> float:
	var arc := seat_station(state, "lights") as TankArcState
	if arc == null:
		return 1.0
	if state.hull.breakdown or arc.stalled or arc.unpowered:
		return 0.15
	return 1.0 if arc.lit else 0.3


## The Lights seat is powered while it is manned and its arc lit, its rider in band (brief v3
## "Lights"; tank 0.3.1: Simon). Both searchlights burn then (turret: forward about 11 degrees
## down; rear: aft about 13 degrees down) and the rooms have their warm lamps; unpowered, the
## searchlights go out (a standby glow on their lenses) and the rooms fall back to their dim backup
## lighting. search_level and backup_level fade them (search_fade()).
func lights_powered(state: TankState) -> bool:
	return rider_on("lights") != null and searchlight_k(state) >= 1.0


## The turret searchlight's rule (lights_powered(); kept for its callers).
func turret_search_on(state: TankState) -> bool:
	return lights_powered(state)


## The searchlights' and the backup lighting's levels this frame: powered (lights_powered) the
## searchlights fade up and the backup down; unpowered, both hold SEARCH_HOLD_S first while the
## seat's rider stays on it (dropped out of band), then the searchlights fade down and the backup
## up. An empty seat or a breakdown skips the hold.
func _search(state: TankState, step_dt: float) -> void:
	var want := lights_powered(state)
	if not _search_primed:
		_search_primed = true
		search_level = 1.0 if want else 0.0
		_search_hold = SEARCH_HOLD_S if want else 0.0
		backup_level = 0.0 if want else 1.0
		_backup_hold = _search_hold
		return
	if not want and (rider_on("lights") == null or state.hull.breakdown):
		_search_hold = 0.0
		_backup_hold = 0.0
	var lh := search_fade(search_level, _search_hold, want, step_dt)
	search_level = lh.x
	_search_hold = lh.y
	var bh := fade(1.0 - backup_level, _backup_hold, want, step_dt, BACKUP_FADE_S, SEARCH_HOLD_S)
	backup_level = 1.0 - bh.x
	_backup_hold = bh.y


## One step of the searchlights' fade (fade() over SEARCH_FADE_S, holding SEARCH_HOLD_S).
static func search_fade(level: float, hold: float, want: bool, step_dt: float) -> Vector2:
	return fade(level, hold, want, step_dt, SEARCH_FADE_S, SEARCH_HOLD_S)


## One step of a light's fade: Vector2(level, hold left) after `step_dt` s from `level` (0..1) and
## `hold` (s) with it wanted on or not. On: up by step_dt / `fade_s`, the hold refilled to
## `hold_s`. Off: the hold runs out first, the rest of the step fades it down.
static func fade(
	level: float, hold: float, want: bool, step_dt: float, fade_s: float, hold_s: float
) -> Vector2:
	if want:
		var up := level + step_dt / fade_s
		return Vector2(1.0 if up > 0.999 else up, hold_s)
	var left := hold - step_dt
	if left >= 0.0:
		return Vector2(level, left)
	var down := level + left / fade_s
	return Vector2(0.0 if down < 0.001 else down, 0.0)


## The loader's picture from the contracts' rack, load_t and chamber_s: {lt (s into the r6 7 s
## cycle, < 0 idle), ready (rounds in the rack), fire_t}. See TankFiring.loader_view.
func loader_view(state: TankState) -> Dictionary:
	return TankFiring.loader_view(state, seat_station(state, "loader"), firing.fire_t)


func _paint(state: TankState) -> void:
	var inp := paint_input(state)
	if interior.paints == 0:
		interior.paint_all(inp)
	else:
		interior.paint(inp, time)
	body.travel = travel
	body.wheels = wheel_centres
	body.elev_deg = state.hull.elev_deg
	body.recoil = firing.recoil()
	body.bow_elev_deg = bow_elev
	for k in 2:
		body.bow_kick[k] = BOW_KICK if firing.bow_kicking(k, BOW_KICK_S) else 0.0
	body.search_lit = search_level >= 0.5
	body.rear_lit = search_level >= 0.5
	body.backup = backup_level


## What the rooms are painted from this frame (TankInterior.paint).
func paint_input(state: TankState) -> Dictionary:
	var inp := {"t": time}
	for seat in TankRig.SEATS:
		inp[seat] = {
			"slot": int(seat_slots.get(seat, -1)),
			"revs": machine_phase(seat),
			"on": float(cadences.get(seat, 0.0)) > 1.0 and not state.hull.breakdown,
		}
	var rp := seat_station(state, "repair") as TankRepairState
	if rp != null:
		inp["repair"]["press_t"] = rp.press_t
		inp["repair"]["patches"] = rp.patches
	inp["loader_seat"] = inp["loader"]
	var lv := loader_view(state)
	lv["elev"] = state.hull.elev_deg
	inp["loader"] = lv
	var sec: Dictionary = inp["sec"]
	inp["bow"] = {"revs": machine_phase("sec") if bool(sec["on"]) else -1.0}
	var feed := seat_station(state, "sec") as TankFeedState
	if feed != null and feed.rpm <= 0.0:
		inp["bow"] = {"revs": -1.0}
	return inp


## The bow guns tilt toward the nearest near threat ahead (cosmetic; the rules aim them), back to rest
## without one, slewing at BOW_SLEW.
func _bow_aim(step_dt: float) -> void:
	bow_target = Vector2.ZERO
	var piv := at_sprite(rig.bow[0]["pivot"]) if not rig.bow.is_empty() else Vector2.ZERO
	var best := INF
	for id: int in enemy_rects:
		var r: Rect2 = enemy_rects[id]
		var dx := r.get_center().x - piv.x
		if dx > 20.0 and dx < best:
			best = dx
			bow_target = r.get_center() + Vector2(0, r.size.y * 0.1)
	var want := BOW_REST_DEG
	if bow_target != Vector2.ZERO:
		var d := bow_target - piv
		want = clampf(-rad_to_deg(d.angle() - hull_rot), BOW_MIN_DEG, BOW_MAX_DEG)
	bow_elev = move_toward(bow_elev, want, BOW_SLEW * step_dt)


# --- Public effects -------------------------------------------------------------------------------------


## The evade effect: "lurch" (the drive surges the tank forward with a burst of dust) or "smoke"
## (the boiler blows a smoke screen).
func play_evade(kind: String) -> void:
	if not _built:
		return
	if kind == "smoke":
		screen_s = 0.0
		var vent := at_sprite(rig.exhaust) + Vector2(40, -6)
		for i in 26:
			var j := fx.rng.randf()
			fx.puff(
				vent + Vector2(i * 9.0, fx.rng.randf_range(-6.0, 6.0)),
				Vector2(fx.rng.randf_range(10.0, 40.0), fx.rng.randf_range(-10.0, 2.0)),
				5.0 + j * 2.0,
				Vector2(10.0, 50.0 + j * 20.0),
				0.4,
				Color(0.62, 0.62, 0.6).lerp(Color(0.5, 0.48, 0.45), j),
				0.6
			)
	else:
		lurch_s = 0.0
		var rear := Vector2(tank_pos.x + ART_REAR + 30.0, GROUND - 2.0)
		for i in 10:
			fx.puff(
				rear + Vector2(i * 8.0, 0),
				Vector2(fx.rng.randf_range(-30.0, -10.0), fx.rng.randf_range(-12.0, -4.0)),
				1.6,
				Vector2(4.0, 18.0),
				0.35,
				Color(0.36, 0.3, 0.24),
				1.0
			)


## A shot of the tank's own: "main" (the main gun: blast, recoil, rock, jolt, scene flash, shake)
## or "bow" (one round from bow gun `gun`, alternating when -1). The `shot` cue and the feed's
## round count call it.
func fire(kind: String, gun: int = -1) -> void:
	if not _built:
		return
	if kind == "bow":
		firing.bow_round(gun)
		if bow_target != Vector2.ZERO:
			var hit := bow_target + Vector2(fx.rng.randf_range(-8, 8), fx.rng.randf_range(-5, 3))
			fx.spark_burst(hit, 3, Color(1.0, 0.8, 0.4), 46.0)
			fx.flash(hit, 5.0, 0.08, Color(1.0, 0.82, 0.5))
		return
	var mz := muzzle()
	firing.fire_main(mz, barrel_vector().angle())
	fx.light_scene(mz, 1.0, Color(1.0, 0.72, 0.4))


## The Secondaries' new rounds (TankFeedState.rounds; round k from gun (k - 1) mod 2): a flash, a
## tracer and a case each, at most MAX_ROUNDS_PER_FRAME a frame (a late snapshot catches up).
func _feed_rounds(state: TankState) -> void:
	var feed := seat_station(state, "sec") as TankFeedState
	if feed == null:
		return
	if _rounds_seen < 0 or feed.rounds < _rounds_seen:
		_rounds_seen = feed.rounds
		return
	var from := maxi(_rounds_seen + 1, feed.rounds - MAX_ROUNDS_PER_FRAME + 1)
	for k in range(from, feed.rounds + 1):
		fire("bow", posmod(k - 1, 2))
	_rounds_seen = feed.rounds
