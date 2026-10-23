extends GutTest
## Siege's synthesized audio (brief 3 "Audio"): sounds registered with the Sfx autoload, loops
## pitched by watts, shots, hooves, the ram, the gate, horns and coins from what the state says,
## and silence plus no errors headless.

var _state: SiegeState = null
var _audio: SiegeAudio = null


func before_each() -> void:
	_state = SiegeFixtures.mid_wave()
	_audio = SiegeAudio.new()
	add_child_autofree(_audio)


func _step(dt: float = 0.05) -> void:
	_state.tick += 1
	_audio.update(_state, dt, 1)


func test_the_sounds_are_registered_with_sfx() -> void:
	var sfx := get_node("/root/Sfx") as WlSfx
	for key in SiegeAudio.SOUND_NAMES:
		assert_true(sfx.has_sound(key), key)
		assert_not_null(sfx.get_stream(key), key)


func test_headless_makes_no_players_and_stays_silent() -> void:
	assert_true(_audio.silent)
	assert_null(_audio.creak)
	assert_null(_audio.hum)
	_step()
	assert_gt(_audio.played.size(), 0, "it still records what it would play")


func test_loop_pitch_follows_watts() -> void:
	assert_almost_eq(SiegeAudio.pitch_for(0.0, 300.0, SiegeAudio.CREAK_PITCH), 0.55, 1e-6)
	assert_almost_eq(SiegeAudio.pitch_for(300.0, 300.0, SiegeAudio.CREAK_PITCH), 1.6, 1e-6)
	assert_almost_eq(SiegeAudio.pitch_for(900.0, 300.0, SiegeAudio.CREAK_PITCH), 1.6, 1e-6)
	var low := SiegeAudio.pitch_for(250.0, 2000.0, SiegeAudio.HUM_PITCH)
	var high := SiegeAudio.pitch_for(1500.0, 2000.0, SiegeAudio.HUM_PITCH)
	assert_lt(low, high)
	_state.team_w = 1000.0
	_step()
	assert_almost_eq(_audio.hum_pitch, 1.35, 1e-6)
	var mean := 0.0
	for r in _state.riders:
		mean += r.p_eff_w
	mean /= 4.0
	assert_almost_eq(
		_audio.creak_pitch, SiegeAudio.pitch_for(mean, 300.0, SiegeAudio.CREAK_PITCH), 1e-6
	)


func test_each_tower_type_has_its_own_shot_sound() -> void:
	_step()
	# The fixture's shots: pad 3 (Ballista), pad 4 (Scorpion), pad 2 (Caltrop thrower).
	assert_true(_audio.played.has("siege_ballista"))
	assert_true(_audio.played.has("siege_scorpion"))
	assert_true(_audio.played.has("siege_caltrop"))


func test_a_shot_sounds_once() -> void:
	_step()
	_audio.played.clear()
	_state.tick += 0
	_audio.update(_state, 0.05, 1)
	assert_false(_audio.played.has("siege_ballista"), "the same tick again plays nothing")
	for shot in _state.shots:
		shot.age_s += Wl.SIM_DT
	_step()
	assert_false(_audio.played.has("siege_ballista"), "the same shot, aged, plays nothing new")


func test_hooves_and_the_ram_at_the_gate() -> void:
	_step()
	assert_true(_audio.played.has("siege_hooves"), "horsemen are walking")
	assert_true(_audio.played.has("siege_ram"), "a ram is battering the gate")
	_audio.played.clear()
	_step(0.05)
	assert_false(_audio.played.has("siege_ram"), "not every tick")


func test_the_gate_losing_hp_sounds_and_a_breach_booms() -> void:
	_step()
	_audio.played.clear()
	_state.gate_hp -= 8.0
	_step()
	assert_true(_audio.played.has("siege_gate"))
	_audio.played.clear()
	_state.breach_s = 10.0
	_step()
	assert_true(_audio.played.has("boom"))
	_audio.played.clear()
	_state.breach_s = 9.0
	_step()
	assert_false(_audio.played.has("boom"), "one boom per breach")


func test_a_horn_when_a_wave_starts_but_not_at_the_first_look() -> void:
	_step()
	assert_false(_audio.played.has("siege_horn"), "joining mid-wave plays no horn")
	_state.role = SiegeIds.ROLE_BREAK
	_state.phase_index = 5
	_step()
	assert_false(_audio.played.has("siege_horn"))
	_state.role = SiegeIds.ROLE_WAVE
	_state.phase_index = 6
	_step()
	assert_true(_audio.played.has("siege_horn"))


func test_coins_when_the_local_riders_denarii_rise() -> void:
	_step()
	_audio.played.clear()
	_state.rider_at(0).denarii += 2.0
	_step(0.4)
	assert_true(_audio.played.has("coin"))
	_audio.played.clear()
	_step(0.4)
	assert_false(_audio.played.has("coin"))
