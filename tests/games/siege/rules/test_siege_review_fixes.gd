extends GutTest
## The independent review's defects in the rules (2026-10-30), each pinned by a test that failed
## before its fix: a Breach running into a break, the rush double bounty, the replicated next rush,
## shop fallback and connection, the mine turning in breaks, the ram's reach event, the WKG ratio
## before any telemetry.

const F := preload("res://tests/games/siege/siege_fakes.gd")


func _breached(role: String = SiegeIds.ROLE_WAVE) -> SiegeState:
	var s := SiegeKit.state("short", 2, 0, 1, role)
	s.pad(1).type = SiegeIds.PAD_NONE
	return s


# --- 3. A Breach that runs into a break -----------------------------------------------------------


func test_a_breach_ending_in_a_break_keeps_the_break_s_repairs_and_bands() -> void:
	var s := _breached()
	var ev: Array[Dictionary] = []
	s.gate_hp = 2.0
	SiegeCombat.damage_gate(s, 5.0, ev)
	assert_eq(s.breaches, 1)
	s.role = SiegeIds.ROLE_BREAK
	s.phase_kind = Wl.RECOVERY
	s.rider(1).gold = 500.0
	var it := SiegeIntents.normalize(SiegeIntents.buy(SiegeIds.ITEM_IRON_BANDS))
	assert_eq(int(SiegeShop.buy(s, s.rider(1), it)["ok"]), 1)
	var rep := SiegeIntents.normalize(SiegeIntents.buy(SiegeIds.ITEM_REPAIR))
	assert_eq(int(SiegeShop.buy(s, s.rider(1), rep)["ok"]), 1)
	assert_eq(s.gate_hp, 45.0, "25 from the bands, 20 from the repair")
	SiegeKit.run_combat(s, 10.5)
	assert_eq(s.breach_s, 0.0)
	assert_eq(s.gate_hp, 45.0, "the restore never lowers the gate")


func test_the_restore_still_lifts_a_low_gate_to_30() -> void:
	var s := _breached()
	var ev: Array[Dictionary] = []
	s.gate_hp = 1.0
	SiegeCombat.damage_gate(s, 5.0, ev)
	SiegeKit.run_combat(s, 10.05)
	assert_eq(s.gate_hp, 30.0)


func test_the_breach_gold_cut_lands_when_the_breach_starts() -> void:
	var s := _breached()
	var ev: Array[Dictionary] = []
	s.rider(1).gold = 101.6
	s.rider(2).gold = 9.0
	s.gate_hp = 1.0
	SiegeCombat.damage_gate(s, 5.0, ev)
	assert_almost_eq(s.rider(1).gold, 101.6 - 30.0, 1e-6, "at once: floor(0.3 x 101)")
	assert_almost_eq(s.rider(2).gold, 7.0, 1e-6)
	SiegeKit.run_combat(s, 10.05)
	assert_almost_eq(s.rider(1).gold, 71.6, 1e-6, "and only once")


func test_buying_first_cannot_dodge_the_cut() -> void:
	var s := _breached()
	var ev: Array[Dictionary] = []
	s.rider(1).gold = 100.0
	s.gate_hp = 1.0
	SiegeCombat.damage_gate(s, 5.0, ev)
	s.role = SiegeIds.ROLE_BREAK
	var it := SiegeIntents.normalize(SiegeIntents.buy(SiegeIds.ITEM_MINE))
	SiegeShop.buy(s, s.rider(1), it)
	assert_almost_eq(s.rider(1).gold, 70.0 - 60.0, 1e-6, "cut first, then the 60 gold level")
	SiegeKit.run_combat(s, 10.05)
	assert_almost_eq(s.rider(1).gold, 10.0, 1e-6)


# --- 4. Rush double bounty by the rush clock ------------------------------------------------------


func _kill_with(s: SiegeState, rush_flag: bool) -> float:
	var r := s.rider(1)
	r.od_state = SiegeIds.OD_ACTIVE
	var before := r.gold
	var e := SiegeKit.enemy(s, SiegeIds.ENEMY_SPEAR, 100.0, 0.0, 5.0)
	e.rush = rush_flag
	var p := SiegeProjectile.new()
	p.kind = SiegeIds.SHOT_ARROW
	p.src = SiegeIds.STATION_ARROWS
	p.pos = e.pos
	p.damage = 8.0
	p.ticks = 1
	p.peers = [1]
	p.shares = [1.0]
	s.projectiles.append(p)
	var ev: Array[Dictionary] = []
	SiegeProjectiles.step(s, SiegeKit.table(s), ev)
	assert_eq(e.hp, 0.0)
	return r.gold - before


func test_a_kill_while_a_rush_is_on_pays_double_whoever_it_was() -> void:
	var s := _breached()
	s.wave.rush_s = 12.0
	assert_almost_eq(_kill_with(s, false), 2.0 * s.bounty_scale, 1e-6, "a regular spearman")


func test_a_rush_body_killed_after_the_rush_pays_single() -> void:
	var s := _breached()
	s.wave.rush_s = 0.0
	assert_almost_eq(_kill_with(s, true), 1.0 * s.bounty_scale, 1e-6)


# --- 5, 6, 9. What a client learns from the snapshot -------------------------------------------------


func _client_of(host: SiegeState) -> SiegeState:
	var c := SiegeState.create(host.content, SiegeFixtures.slots(), Wl.FAIR_FTP, null)
	SiegeSnapshot.apply(c, JSON.parse_string(JSON.stringify(SiegeSnapshot.encode(host))))
	return c


func test_a_restarted_client_learns_the_next_rush() -> void:
	var host := SiegeFixtures.mid_wave(SiegeFixtures.content("endurance"))
	host.wave.rush_next = 2
	host.wave.rush_s = 0.0
	assert_eq(_client_of(host).wave.rush_next, 2)
	host.wave.rush_next = 0
	assert_eq(_client_of(host).wave.rush_next, 0)


func test_a_client_learns_the_shop_fallback() -> void:
	var host := SiegeFixtures.mid_wave()
	host.rider_at(0).shop_fallback = false
	host.rider_at(3).shop_fallback = true
	var c := _client_of(host)
	assert_false(c.rider_at(0).shop_fallback, "a manual buy ends it on the client too")
	assert_true(c.rider_at(3).shop_fallback)


func test_a_client_learns_who_is_disconnected() -> void:
	var host := SiegeFixtures.mid_wave()
	host.rider_at(2).connected = false
	var c := _client_of(host)
	assert_false(c.rider_at(2).connected)
	assert_false(c.rider_at(2).delivering(), "its path goes dark")
	assert_true(c.rider_at(1).connected)


func test_the_rider_row_carries_the_two_flags() -> void:
	var row: Array = SiegeSnapshot.encode(SiegeFixtures.mid_wave())["r"][0]
	assert_eq(row.size(), 13)
	assert_eq(int(row[11]), 1, "connected")
	assert_eq(int(row[12]), 0, "slot 0 left the shop fallback")


func test_an_older_eleven_column_row_still_applies() -> void:
	var host := SiegeFixtures.mid_wave()
	var snap := SiegeSnapshot.encode(host)
	for row: Array in snap["r"]:
		row.resize(11)
	var c := SiegeState.create(host.content, SiegeFixtures.slots(), Wl.FAIR_FTP, null)
	SiegeSnapshot.apply(c, snap)
	assert_eq(c.rider_at(0).target, SiegeIds.STATION_BALLISTA)
	assert_true(c.rider_at(0).connected, "the defaults stand")


func test_the_snapshot_stays_under_8_kb_at_the_cap_with_the_new_fields() -> void:
	var s := SiegeFixtures.cap()
	s.wave.rush_next = 4
	s.wave.rush_s = 10.0
	var snap := SiegeSnapshot.encode(s)
	assert_eq(SiegeSnapshotSchema.check(snap), "")
	assert_lte(SiegeSnapshotSchema.byte_size(snap), SiegeSnapshotSchema.MAX_BYTES)


# --- 10. The mine turns in breaks -------------------------------------------------------------


func test_the_mine_turns_in_a_break_whatever_the_targets() -> void:
	var s := _breached(SiegeIds.ROLE_BREAK)
	SiegeKit.put(s, 1, SiegeIds.STATION_ARROWS, 250.0)
	SiegeKit.put(s, 2, SiegeIds.STATION_MINE, 125.0)
	var arm0 := s.station(SiegeIds.STATION_MINE).arm
	SiegeKit.run_stations(s, 0.5)
	assert_almost_eq(s.station(SiegeIds.STATION_MINE).m, 1.5, 1e-6, "all output goes to the mine")
	assert_ne(s.station(SiegeIds.STATION_MINE).arm, arm0, "and its arm moves")


func test_the_mine_is_still_in_a_break_breach_and_the_cool_down() -> void:
	var s := _breached(SiegeIds.ROLE_BREAK)
	SiegeKit.put(s, 1, SiegeIds.STATION_MINE, 250.0)
	s.breach_s = 3.0
	SiegeKit.run_stations(s, 0.1)
	assert_eq(s.station(SiegeIds.STATION_MINE).m, 0.0)
	s.breach_s = 0.0
	s.role = SiegeIds.ROLE_COOLDOWN
	SiegeKit.run_stations(s, 0.1)
	assert_eq(s.station(SiegeIds.STATION_MINE).m, 0.0)


func test_break_pay_is_unchanged_by_the_shown_m() -> void:
	var rig := SiegeRig.new("short", 1)
	rig.manual()
	rig.enter(1, 1.0)
	rig.p_eff[1] = 250.0
	var before := rig.rider().gold
	rig.run(40.0)
	assert_almost_eq(rig.rider().gold - before, 10.0, 0.01, "250 W x 40 s = 10 kJ = 10 gold")
	assert_almost_eq(rig.state.station(SiegeIds.STATION_MINE).m, 1.0, 1e-6)


# --- 13. The ram's reach event ----------------------------------------------------------------


func test_a_ram_reaching_the_gate_raises_a_reach_event_and_its_cue() -> void:
	var s := _breached()
	var ram := SiegeKit.enemy(s, SiegeIds.ENEMY_RAM, s.path.length_m - 0.02)
	var ev := SiegeKit.run_combat(s, 0.05)
	var reach := SiegeKit.of_type(ev, "reach")
	assert_eq(reach.size(), 1)
	assert_eq(int(reach[0]["id"]), ram.id)
	assert_eq(int(reach[0]["et"]), SiegeIds.ENEMY_RAM)
	assert_eq(SiegeEvents.check(reach[0]), "")


func test_a_ram_killed_after_reaching_is_not_stopped() -> void:
	var s := _breached()
	var ram := SiegeKit.enemy(s, SiegeIds.ENEMY_RAM, s.path.length_m - 0.02, 0.0, 5.0)
	SiegeKit.run_combat(s, 0.05)
	assert_true(ram.reached)
	var p := SiegeProjectile.new()
	p.kind = SiegeIds.SHOT_STONE
	p.src = SiegeIds.STATION_ONAGER
	p.pos = ram.pos
	p.damage = 160.0
	p.ticks = 1
	s.projectiles.append(p)
	var ev: Array[Dictionary] = []
	SiegeProjectiles.step(s, SiegeKit.table(s), ev)
	assert_eq(ram.hp, 0.0)
	assert_eq(s.engines_stopped, 0)


func test_the_host_cues_the_reach_event() -> void:
	var g := F.make_game(F.make_ctx(1, 0, "short"))
	var kinds: Array = []
	g.cue.connect(func(kind: String, _d: Dictionary) -> void: kinds.append(kind))
	g._local_effects({"type": "reach", "id": 3, "et": SiegeIds.ENEMY_RAM})
	assert_eq(kinds, ["reach"])
	assert_true(g.int_fields().has("reach"))
	F.free_game(g)


# --- WKG before any telemetry -----------------------------------------------------------------


func test_the_wkg_ratio_starts_from_the_slot_s_p_eff_per_w() -> void:
	var slots := F.make_slots(1)
	slots[0].p_eff_per_w = 1.6
	var s := SiegeState.create(F.content("short"), slots, Wl.WKG, null)
	assert_almost_eq(s.riders[0].r_wkg, 1.6, 1e-6)
	assert_almost_eq(SiegeRules.planned_p_eff_w(s, s.riders[0], 50.0), 0.5 * 200.0 * 1.6, 1e-6)


func test_the_wkg_warm_up_budget_uses_the_slot_ratio() -> void:
	var rig := SiegeRig.new("short", 1, 0, 7, Wl.WKG)
	rig.slots[0].p_eff_per_w = 1.5
	rig.state.rider(1).r_wkg = 1.0
	var s := SiegeState.create(rig.content, rig.slots, Wl.WKG, rig.state.rng)
	rig.state = s
	rig.power_w[1] = 0.0
	rig.step()
	var want := SiegeRules.planned_p_eff_w(s, s.rider(1), 57.5) / 250.0
	want *= rig.content.num("c_budget") * (300.0 - 60.0) / 60.0
	want *= 0.4 * SiegeRules.budget_factor(rig.content) * SiegeRules.slot_factor(rig.content, 1)
	assert_almost_eq(s.wave.budget, want, 1e-3)
	assert_almost_eq(s.rider(1).r_wkg, 1.5, 1e-6, "no telemetry of >= 50 W yet")
