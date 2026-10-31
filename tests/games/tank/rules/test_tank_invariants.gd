extends GutTest
## A fuzz of whole sessions: random intents from every rider, random power, cadence, rescue and AFK
## flips, every tick checked against the state's invariants (no NaN, bounds, caps, unique ids,
## the Loader's rack and Overpressure, seats). Seeded, so a failure repeats.

const KINDS := ["seat", "aim", "target", "fire", "latch", "over"]
const TO := ["next", "prev", "diesel", "dynamo", "steam", "arc", "feed", "repair"]


func _random_intent(rng: RandomNumberGenerator) -> Dictionary:
	var k: String = KINDS[rng.randi() % KINDS.size()]
	var d := {"k": k, "via": ["action", "surge", "button", "auto"][rng.randi() % 4]}
	match k:
		"seat":
			d["to"] = TO[rng.randi() % TO.size()]
		"aim", "target":
			d["d"] = 1 if rng.randi() % 2 == 0 else -1
	return d


func _check(rig: TankRulesRig, label: String) -> void:
	var s := rig.state
	var h := s.hull
	assert_true(
		is_finite(h.x_px) and is_finite(h.speed_mps) and is_finite(h.hp), "%s finite hull" % label
	)
	assert_between(h.hp, 0.0, h.hp_max, "%s hp" % label)
	assert_between(h.berm_hp, 0.0, 40.0, "%s berm" % label)
	assert_between(h.elev_deg, -12.0, 30.0, "%s elevation" % label)
	assert_gte(h.speed_mps, 0.0, "%s speed" % label)
	assert_has([TankIds.FACE_LEFT, TankIds.FACE_RIGHT], h.facing, "%s facing" % label)
	assert_gte(h.breech_s, 0.0)
	assert_gte(h.traverse_s, 0.0)
	assert_lte(s.enemies.size(), TankConst.MAX_ENEMIES, "%s enemies cap" % label)
	assert_lte(s.shells.size(), TankConst.MAX_SHELLS, "%s shells cap" % label)
	var ids := {}
	for e in s.enemies:
		assert_false(ids.has(e.id), "%s unique id" % label)
		ids[e.id] = true
		assert_true(
			is_finite(e.x_px) and e.hp > 0.0 and e.hp <= e.hp_max, "%s enemy %d" % [label, e.id]
		)
		_check_frame(rig, e, label)
	for sh in s.shells:
		assert_false(ids.has(sh.id), "%s unique shell id" % label)
		ids[sh.id] = true
		assert_true(is_finite(sh.x) and is_finite(sh.y), "%s shell finite" % label)
	for o in s.obstacles:
		assert_false(ids.has(o.id), "%s unique obstacle id" % label)
		ids[o.id] = true
	for st in s.stations:
		if st is TankDynamoState:
			assert_between((st as TankDynamoState).bank, 0.0, 100.0, "%s bank" % label)
		elif st is TankSteamState:
			var sm := st as TankSteamState
			assert_between(sm.pressure_pct, 0.0, 150.0, "%s pressure" % label)
			if not sm.over:
				assert_lte(sm.pressure_pct, 100.0, "%s: over 100%% only in Overpressure" % label)
			assert_eq(sm.chamber, s.hull.loaded != TankIds.SHELL_NONE, "%s chamber" % label)
			assert_eq(sm.rack, TankAux.of(s).rack_types.size(), "%s rack types" % label)
			assert_false(
				sm.over and sm.window_s > 0.0, "%s: over and window exclude each other" % label
			)
			assert_between(sm.rack, 0, TankConst.RACK_MAX, "%s rack" % label)
			assert_between(sm.load_t, 0.0, 1.0, "%s load_t" % label)
		elif st is TankFeedState:
			assert_gte((st as TankFeedState).rounds, 0, "%s rounds" % label)
	var b := s.boss
	assert_between(b.turret_hp, 0.0, b.turret_max + 0.001)
	for hp in b.bogie_hp:
		assert_between(hp, 0.0, b.bogie_max + 0.001)
	assert_between(s.score.crew_kills, 0, 10000)
	for r in s.riders:
		assert_true(is_finite(r.work_s) and r.band_s <= r.work_s + 1e-6, "%s band <= work" % label)


## v4: nothing behind the tank, far kinds in the far frame, near kinds ahead of the hull's front,
## no enemy in a checkpoint.
func _check_frame(rig: TankRulesRig, e: TankEnemyState, label: String) -> void:
	var s := rig.state
	assert_eq(e.side, 1, "%s side" % label)
	assert_false(e.fixed, "%s no stationary gun" % label)
	if e.is_near():
		assert_gt(TankEnemies.distance(s, e), 0.0, "%s near threat ahead of the front" % label)
	else:
		assert_gt(e.range_m, 0.0, "%s far range" % label)
		assert_lte(e.range_m, TankConst.FAR_SPAWN_M + 0.5, "%s far range" % label)
	assert_ne(s.seg.seg, TankIds.SEG_CHECKPOINT, "%s no enemy in a checkpoint" % label)


func _fuzz(crew: int, rng_seed: int) -> TankRulesRig:
	var rig := TankRulesRig.new(crew, "ashfall_road", rng_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed * 7919
	rig.auto_phase = true
	rig.bank_director = true
	var label := "crew %d seed %d" % [crew, rng_seed]
	# Hop around the mission so every segment type runs with the fuzz on.
	var hops := [0, 1, 2, 3, 4, 5, 7, 8, 10, 11]
	for hop in hops:
		rig.enter(hop, 0.0, Wl.ENDED_MAX_S if hop % 3 == 0 else Wl.ENDED_END_PHASE)
		var ticks := roundi(40.0 / Wl.SIM_DT)
		for i in ticks:
			if i % 40 == 0:
				for p in rig.slots:
					var roll := rng.randi() % 10
					rig.power_w.erase(p.peer_id)
					if roll == 0:
						rig.power_w[p.peer_id] = 0.0
					elif roll == 1:
						rig.power_w[p.peer_id] = 1.6 * p.ftp
					elif roll == 2:
						rig.power_w[p.peer_id] = 0.5 * p.ftp
					rig.rescue[p.peer_id] = rng.randi() % 12 == 0
					rig.afk[p.peer_id] = rng.randi() % 15 == 0
					rig.cadence[p.peer_id] = [90.0, 55.0, 30.0][rng.randi() % 3]
			for p in rig.slots:
				if rng.randf() < 0.12:
					var st := rig.state.station_of(p.slot_index)
					var engine: String = st.engine if st != null else ""
					var raw := _random_intent(rng)
					if TankIntents.owned(str(raw["k"]), engine):
						rig.send(p.peer_id, raw)
			rig.step()
			if i % 10 == 0:
				_check(rig, "%s hop %d tick %d" % [label, hop, i])
		if rig.in_cooldown():
			break
	return rig


## The solo rider moves seats at random (0.3.1: every move lands at once): the main gun fires only
## while it sits on the Gun (an empty Gun seat never fires).
func test_random_play_keeps_every_invariant_for_a_solo_crew() -> void:
	var rig := _fuzz(1, 1)
	_fuzz(1, 2)
	var engine := TankIds.ENGINE_DIESEL
	var main := 0
	for e: Dictionary in rig.events:
		if e["type"] == TankEvents.SEAT:
			engine = TankIds.engine_of(int(e["to"]))
		elif e["type"] == TankEvents.SHOT and int(e["s"]) >= 0 and e["sh"] != TankIds.SHELL_BOW:
			main += 1
			assert_eq(engine, TankIds.ENGINE_DYNAMO, "an empty Gun seat never fires")
	gut.p("%d main-gun shots, each from the Gun" % main)
	assert_gt(rig.of_type("hit").size(), 0, "the enemies did")


func test_random_play_keeps_every_invariant_for_a_crew_of_2() -> void:
	var rig := _fuzz(2, 3)
	_fuzz(2, 4)
	assert_gt(rig.of_type("shot").size(), 10)
	assert_gt(rig.of_type("hit").size(), 5)


func test_random_play_keeps_every_invariant_for_a_crew_of_3() -> void:
	var rig := _fuzz(3, 5)
	_fuzz(3, 6)
	assert_gt(rig.of_type("latch").size(), 2, "shells were latched")
	assert_gt(rig.of_type("shot").size(), 10)
	assert_gt(rig.of_type("kill").size(), 0)


## Every 100 ticks of a 20-minute run: the v4 frame holds, losses and restarts included.
func test_a_twenty_minute_hard_run_keeps_the_frame() -> void:
	for crew in [2, 4]:
		var rig := TankRulesRig.new(crew, "ashfall_road", crew)
		rig.state.difficulty = TankIds.DIFF_HARD
		rig.auto_phase = true
		rig.bank_director = true
		rig.enter(1, 0.0)
		for i in roundi(1200.0 / Wl.SIM_DT):
			rig.step()
			if i % 100 == 0:
				_check(rig, "crew %d tick %d" % [crew, i])
			if rig.in_cooldown():
				break
		assert_gt(rig.of_type("shot").size(), 10)


func test_random_play_keeps_every_invariant_for_a_crew_of_4() -> void:
	var rig := _fuzz(4, 7)
	assert_gt(rig.of_type("latch").size(), 2, "shells were latched")
	assert_gt(rig.of_type("shot").size(), 10)
