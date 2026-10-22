extends GutTest
## What the Siege HUD says (SiegeHudModel): titles, enemy lines, warnings, targets, the
## Overdrive button's face, rush markers; plus that every string key it uses exists.

var _game: SiegeGame = null
var _state: SiegeState = null
var _tx: GameStrings = null


func before_each() -> void:
	_state = SiegeFixtures.mid_wave()
	_game = SiegeHudUtil.make_game(_state)
	_tx = _game.ctx.strings


func after_each() -> void:
	SiegeHudUtil.free_game(_game)


func test_every_hud_string_key_exists() -> void:
	for key in SiegeHudModel.STRING_KEYS:
		assert_true(_tx.has(key), "missing string key %s" % key)


func test_every_siege_key_used_by_the_view_hud_and_audio_exists() -> void:
	var re := RegEx.new()
	re.compile('"(SIEGE_[A-Z0-9_]+)"')
	var dynamic_prefixes := ["SIEGE_SHOP_", "SIEGE_ITEM_", "SIEGE_TOWER_", "SIEGE_PHASE_BREAK_"]
	for dir in [
		"res://src/games/siege/hud", "res://src/games/siege/view", "res://src/games/siege/audio"
	]:
		for f in _gd_files(dir):
			var text := FileAccess.get_file_as_string(f)
			for m in re.search_all(text):
				var key := m.get_string(1)
				if key.ends_with("_"):
					continue
				assert_true(_tx.has(key), "%s uses a missing key %s" % [f, key])
	assert_gt(dynamic_prefixes.size(), 0)


func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for name in da.get_files():
		if name.ends_with(".gd"):
			out.append(dir.path_join(name))
	for sub in da.get_directories():
		out.append_array(_gd_files(dir.path_join(sub)))
	return out


func test_wave_titles_by_role() -> void:
	assert_eq(SiegeHudModel.wave_title(_state, _tx), "Wave 2/6")
	_state.role = SiegeIds.ROLE_WARMUP_WAVE
	assert_eq(SiegeHudModel.wave_title(_state, _tx), "Warm-up wave")
	_state.role = SiegeIds.ROLE_BUILD_BREAK
	assert_eq(SiegeHudModel.wave_title(_state, _tx), "Build break")
	_state.role = SiegeIds.ROLE_BREAK
	_state.wave_no = 2
	assert_eq(SiegeHudModel.wave_title(_state, _tx), "Break 2")
	_state.role = SiegeIds.ROLE_COOLDOWN
	assert_eq(SiegeHudModel.wave_title(_state, _tx), "The siege is lifted")


func test_a_three_wave_shift_reads_wave_2_of_3() -> void:
	var s := SiegeFixtures.mid_wave(SiegeFixtures.content("short"))
	assert_eq(SiegeHudModel.wave_title(s, _tx), "Wave 2/3")


func test_enemy_lines_count_the_living_by_type_and_the_queue() -> void:
	var lines := SiegeHudModel.enemy_lines(_state, _tx)
	assert_eq(lines.size(), 2)
	var alive := _state.alive_by_type()
	var text := "\n".join(lines)
	assert_string_contains(text, "Raiders %d" % alive[SiegeIds.ENEMY_RAIDERS])
	assert_string_contains(text, "Shield wall %d" % alive[SiegeIds.ENEMY_SHIELD_WALL])
	assert_string_contains(text, "Horsemen %d" % alive[SiegeIds.ENEMY_HORSEMEN])
	assert_string_contains(text, "Battering ram 1")
	assert_string_contains(text, "+3 waiting")


func test_enemy_lines_skip_empty_types_and_show_nothing_in_a_break() -> void:
	for e in _state.enemies.duplicate():
		if e.type != SiegeIds.ENEMY_RAIDERS:
			_state.enemies.erase(e)
	_state.queue.clear()
	var lines := SiegeHudModel.enemy_lines(_state, _tx)
	assert_eq(lines.size(), 1)
	assert_false("\n".join(lines).contains("Shield"))
	_state.role = SiegeIds.ROLE_BREAK
	assert_eq(SiegeHudModel.enemy_lines(_state, _tx).size(), 0)


func test_warning_priority_breach_then_rush_then_ram() -> void:
	# The fixture has a ram battering the gate.
	assert_eq(SiegeHudModel.warning(_game)["key"], "SIEGE_HUD_RAM_ON_ROAD")
	_state.wave.rush_s = 12.0
	assert_eq(SiegeHudModel.warning(_game)["key"], "SIEGE_HUD_RUSH_ON")
	_state.breach_s = 6.2
	var w := SiegeHudModel.warning(_game)
	assert_eq(w["key"], "SIEGE_HUD_BREACH")
	assert_eq(w["args"], [7])


func test_warning_ram_push_ahead_and_horn_and_failing_gate() -> void:
	for e in _state.enemies.duplicate():
		if e.type == SiegeIds.ENEMY_RAM:
			_state.enemies.erase(e)
	_state.phase_duration_s = 120.0
	_state.phase_elapsed_s = 20.0
	assert_true(SiegeHudModel.warning(_game).is_empty(), "nothing urgent with 100 s left")
	# 70 s left of a wave: the push (60 s left) is 10 s away.
	_state.phase_elapsed_s = 50.0
	var w := SiegeHudModel.warning(_game)
	assert_eq(w["key"], "SIEGE_WARN_RAM")
	assert_eq(w["args"], [10])
	_state.phase_elapsed_s = 20.0
	_state.wave.horn_s = 3.2
	assert_eq(SiegeHudModel.warning(_game)["key"], "SIEGE_WARN_HORN")
	_state.wave.horn_s = 0.0
	_state.gate_hp = 20.0
	assert_eq(SiegeHudModel.warning(_game)["key"], "SIEGE_WARN_GATE_LOW")


func test_a_clients_phase_clock_comes_from_the_shift_when_the_state_has_none() -> void:
	_state.phase_duration_s = 0.0
	_state.phase_index = 4
	_state.phase_elapsed_s = 50.0
	assert_eq(SiegeHudModel.phase_duration_s(_game), 120.0, "vo2 wave 2 is 120 s")
	assert_eq(SiegeHudModel.phase_remaining_s(_game), 70.0)


func test_target_names() -> void:
	assert_eq(SiegeHudModel.target_short(_tx, 0), "GEN")
	assert_eq(SiegeHudModel.target_short(_tx, 3), "T3")
	assert_eq(SiegeHudModel.target_long(_state, _tx, 0), "Generator")
	assert_eq(SiegeHudModel.target_long(_state, _tx, 3), "Tower 3 (Ballista)")
	assert_eq(SiegeHudModel.target_long(_state, _tx, 1), "Tower 1", "an empty pad has no name")


func test_pct_ftp_from_the_riders_raw_watts() -> void:
	var r := _state.rider_at(0)
	r.raw_w = 240.0
	r.ftp = 200.0
	assert_eq(SiegeHudModel.pct_ftp(r), 120)
	assert_eq(SiegeHudModel.pct_ftp(null), 0)


func test_overdrive_face_by_state() -> void:
	var r := _state.rider_at(0)
	var face := SiegeHudModel.overdrive_face(_game)
	assert_eq(face["mode"], SiegeHudModel.OD_ACTIVE)
	assert_eq(face["text"], "12 s")
	assert_almost_eq(float(face["fill"]), 12.0 / 30.0, 1e-4)
	assert_false(face["enabled"])
	r.od_state = SiegeIds.OD_COOLDOWN
	r.od_cd_s = 61.5
	face = SiegeHudModel.overdrive_face(_game)
	assert_eq(face["mode"], SiegeHudModel.OD_COOLDOWN)
	assert_eq(face["text"], "Recharging 62 s")
	assert_almost_eq(float(face["fill"]), 1.0 - 61.5 / 90.0, 1e-4)
	r.od_state = SiegeIds.OD_READY
	face = SiegeHudModel.overdrive_face(_game)
	assert_eq(face["mode"], SiegeHudModel.OD_READY)
	assert_true(face["enabled"])
	r.od_prompt = true
	face = SiegeHudModel.overdrive_face(_game)
	assert_eq(face["mode"], SiegeHudModel.OD_PROMPT)
	assert_eq(face["text"], "Surge for Overdrive!")


func test_overdrive_is_closed_outside_a_work_wave() -> void:
	_state.rider_at(0).od_state = SiegeIds.OD_READY
	_state.role = SiegeIds.ROLE_BREAK
	var face := SiegeHudModel.overdrive_face(_game)
	assert_eq(face["mode"], SiegeHudModel.OD_CLOSED)
	assert_false(face["enabled"])


func test_rush_fractions_come_from_the_phase_meta() -> void:
	var g := SiegeHudUtil.make_game(SiegeFixtures.mid_wave(SiegeFixtures.content("endurance")))
	g.metas = SiegePlanBuilder.phase_metas(g.state.content.shift, "endurance")
	g.state.phase_index = 2
	g.state.phase_duration_s = 2700.0
	var f := SiegeHudModel.rush_fractions(g)
	assert_eq(f.size(), 5)
	assert_almost_eq(f[0], 480.0 / 2700.0, 1e-4)
	assert_almost_eq(f[4], 2400.0 / 2700.0, 1e-4)
	SiegeHudUtil.free_game(g)
	assert_eq(SiegeHudModel.rush_fractions(_game).size(), 0, "vo2 has no rushes")


func test_a_client_computes_the_overdrive_prompt_from_its_snapshot_state() -> void:
	# A client: the snapshot-rebuilt state has no phase kind, duration or prompt flag.
	var client := SiegeState.create(
		SiegeFixtures.content("vo2"), SiegeFixtures.slots(), Wl.FAIR_FTP, null
	)
	SiegeSnapshot.apply(client, SiegeFixtures.snapshot())
	client.role = SiegeIds.ROLE_WAVE
	client.wave_no = 2
	var g := SiegeHudUtil.make_game(client)
	g.ctx.role = Wl.CLIENT
	var r := client.rider_at(0)
	assert_eq(r.od_state, SiegeIds.OD_ACTIVE, "the snapshot has slot 0 in Overdrive")
	assert_false(SiegeHudModel.overdrive_prompt(g), "not ready")
	r.od_state = SiegeIds.OD_READY
	r.od_s = 0.0
	assert_eq(SiegeHudModel.phase_kind(g), Wl.WORK, "vo2 wave 2, from the shift's plan")
	client.phase_elapsed_s = 50.0
	assert_true(client.target_hot(r.target), "an enemy is in range of pad 3")
	assert_true(SiegeHudModel.overdrive_prompt(g), "ready, work, 70 s left, enemies in reach")
	client.phase_elapsed_s = 100.0
	assert_false(SiegeHudModel.overdrive_prompt(g), "under 30 s left")
	client.phase_elapsed_s = 50.0
	r.rescue = true
	assert_false(SiegeHudModel.overdrive_prompt(g), "never in rescue")
	r.rescue = false
	client.pad(3).type = SiegeIds.TOWER_NONE
	client.wave.rush_s = 0.0
	assert_false(SiegeHudModel.overdrive_prompt(g), "no enemy in reach, no rush")
	client.wave.rush_s = 10.0
	assert_true(SiegeHudModel.overdrive_prompt(g), "a rush is on")
	SiegeHudUtil.free_game(g)
