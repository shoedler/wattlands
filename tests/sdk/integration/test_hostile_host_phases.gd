extends GutTest
## BRIEF 4.5 on a client: `phase` messages come from the host, which a client doesn't have to trust
## (anyone can run a modified build). Whatever the host sends, the rider's trainer switches between
## ERG and SIM at most once per 30 s (SafetyGovernor.SWITCH_SPACING_S). The session follows the host
## at once; only the rider's trainer waits.

const Kit := preload("res://tests/sdk/helpers/session_kit.gd")

var _bundle: Dictionary = {}
var _client: GameHost = null
var _rider: LocalRider = null


func before_each() -> void:
	var root := Node.new()
	add_child_autofree(root)
	_bundle = Kit.multi(root, 2)
	assert_eq(str(_bundle["err"]), "")
	_client = (_bundle["clients"] as Array)[0]
	# The kit's riders have no governor; this client rides a real stack.
	var slot := Kit.human(2, 1)
	var dev := MockTrainer.from_spec("erg", slot.ftp, {"seed": 11})
	_rider = LocalRider.new()
	_rider.setup(2, null, slot, dev, {"multiplayer": true, "record": false})
	_rider.add_child(dev)
	root.add_child(_rider)
	_client._local_riders[2] = _rider
	Kit.start(_bundle)
	Kit.step(_bundle, 4)


func after_each() -> void:
	Kit.remove_tree(str(_bundle["tmp"]))


## A plan of `n` phases, ERG and SIM in turn, every one short enough for a host to flip through.
func _flip_plan(n: int) -> EffortPlan:
	var phases: Array[PlanPhase] = []
	for i in n:
		if i % 2 == 0:
			phases.append(PlanPhase.erg(Wl.WORK, 50.0, 20.0))
		else:
			phases.append(PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 20.0))
	return PlanValidator.finalize(EffortPlan.of(phases))


func _send_plan(plan: EffortPlan) -> void:
	_client._client_plan = plan
	_client._client_phase = -1
	_client._held_rider_phase = -1
	_rider.set_plan(plan)


func _phase(index: int, tick: int) -> void:
	_client._on_phase({"index": index, "start_tick": tick, "elapsed_s": 0.0})


func _last_switch() -> float:
	return float(_rider.governor.status()["last_switch_t"])


func test_a_host_flipping_phases_cannot_flip_the_trainer() -> void:
	_send_plan(_flip_plan(40))
	_phase(0, 1)
	_client.step()
	var seen: Array[float] = []
	var last := _last_switch()
	var tick := 2
	# One phase message every 2 s for two minutes, each one a mode change.
	for i in range(1, 60):
		_phase(i % 40, tick)
		tick += 1
		for _s in 40:
			_client.step()
			var now := _last_switch()
			if now != last:
				seen.append(now)
				last = now
	assert_gt(seen.size(), 1, "the trainer did follow, slowly")
	for i in range(1, seen.size()):
		assert_gte(seen[i] - seen[i - 1], SafetyGovernor.SWITCH_SPACING_S - 0.001)


func test_the_session_follows_at_once_and_the_rider_when_the_switch_may_happen() -> void:
	_send_plan(_flip_plan(4))
	_phase(0, 1)
	_client.step()
	assert_eq(str(_rider.governor.status()["desired_mode"]), Wl.ERG)
	# Past any earlier switch's spacing: the first switch goes at once, the one right after waits.
	for _s in int(SafetyGovernor.SWITCH_SPACING_S / Wl.SIM_DT) + 2:
		_client.step()
	_phase(1, 2)
	assert_eq(str(_rider.governor.status()["desired_mode"]), Wl.SIM)
	assert_eq(_client._held_rider_phase, -1)
	_phase(2, 3)
	assert_eq(_client._client_phase, 2, "the session is in the new phase")
	assert_eq(_client._held_rider_phase, 2, "the trainer waits")
	assert_eq(str(_rider.governor.status()["desired_mode"]), Wl.SIM)
	for _s in int(10.0 / Wl.SIM_DT):
		_client.step()
	assert_eq(str(_rider.governor.status()["desired_mode"]), Wl.SIM, "still inside the 30 s")
	for _s in int(SafetyGovernor.SWITCH_SPACING_S / Wl.SIM_DT):
		_client.step()
	assert_eq(_client._held_rider_phase, -1)
	assert_eq(str(_rider.governor.status()["desired_mode"]), Wl.ERG)
	assert_eq(int(_rider.governor.status()["phase_index"]), 2)
	assert_gt(
		float(_rider.governor.status()["phase_elapsed_s"]),
		10.0,
		"the rider joins the phase at its clock, as after a rejoin"
	)


## A rider on a hard ERG target whose last switch was just now, with a SIM phase on its way.
func _just_switched_to_hard_erg() -> void:
	var phases: Array[PlanPhase] = [
		PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 40.0),
		PlanPhase.erg(Wl.WORK, 60.0, 40.0),
		PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 40.0),
	]
	_send_plan(PlanValidator.finalize(EffortPlan.of(phases)))
	_phase(0, 1)
	for _s in int(SafetyGovernor.SWITCH_SPACING_S / Wl.SIM_DT) + 2:
		_client.step()
	_phase(1, 2)
	for _s in 60:
		_client.step()
	assert_gt(_erg_target(), _floor_w(), "riding the hard phase")
	assert_eq(str(_rider.governor.status()["desired_mode"]), Wl.ERG)


func _erg_target() -> int:
	return int(_rider.governor.status()["governed_target_w"])


func _floor_w() -> int:
	return maxi(50, roundi(_rider.slot.ftp * 0.3))


func test_a_held_rider_never_keeps_the_old_phases_load() -> void:
	_just_switched_to_hard_erg()
	_phase(2, 3)
	assert_eq(_client._held_rider_phase, 2)
	_client.step()
	assert_lte(_erg_target(), _floor_w(), "the hold rides easy, not at the old target")
	assert_eq(str(_rider.governor.status()["desired_mode"]), Wl.ERG, "no switch yet")
	for _s in int(SafetyGovernor.SWITCH_SPACING_S / Wl.SIM_DT):
		_client.step()
	assert_eq(_client._held_rider_phase, -1)
	assert_eq(str(_rider.governor.status()["desired_mode"]), Wl.SIM)
	assert_false(bool(_rider.governor.status()["paused"]), "the rider's governor rides on")


func test_a_wait_of_a_moment_keeps_the_load() -> void:
	_just_switched_to_hard_erg()
	var left := SafetyGovernor.SWITCH_SPACING_S - GameHost.HOLD_JITTER_S + 0.5 - 3.0
	for _s in int(left / Wl.SIM_DT):
		_client.step()
	var before := _erg_target()
	_phase(2, 3)
	assert_eq(_client._held_rider_phase, 2)
	_client.step()
	assert_gte(_erg_target(), before, "jitter on a plan's own 30 s doesn't drop the rider")


func test_a_lost_room_reaches_the_cool_down_at_once_from_erg() -> void:
	_just_switched_to_hard_erg()
	_client._lose_net("dropped")
	assert_eq(_client._held_rider_phase, -1, "ERG to the ERG cool-down is no switch")
	assert_eq(int(_rider.governor.status()["phase_index"]), _client._client_plan.cooldown_index())


func test_a_lost_room_waits_for_the_cool_down_on_a_flat_road_from_sim() -> void:
	_just_switched_to_hard_erg()
	for _s in int(SafetyGovernor.SWITCH_SPACING_S / Wl.SIM_DT):
		_client.step()
	_phase(2, 3)
	assert_eq(str(_rider.governor.status()["desired_mode"]), Wl.SIM)
	_client._lose_net("dropped")
	assert_gt(_client._held_rider_phase, -1, "SIM to the ERG cool-down waits for its 30 s")
	_client.step()
	assert_true(bool(_rider.governor.status()["paused"]), "a flat road while it waits")
	for _s in int(SafetyGovernor.SWITCH_SPACING_S / Wl.SIM_DT):
		_client.step()
	assert_eq(_client._held_rider_phase, -1)
	assert_eq(int(_rider.governor.status()["phase_index"]), _client._client_plan.cooldown_index())
	assert_false(bool(_rider.governor.status()["paused"]))


func test_a_session_ending_ends_the_hold() -> void:
	_just_switched_to_hard_erg()
	_phase(2, 3)
	_client.end_session("host_left")
	_rider.clear_plan()
	for _s in 5:
		_client.step()
	assert_eq(_client._held_rider_phase, -1)
	assert_false(bool(_rider.governor.status()["paused"]), "nothing stays paused")


func test_panic_during_a_hold_stays_safe() -> void:
	_just_switched_to_hard_erg()
	_phase(2, 3)
	_rider.panic()
	assert_eq(str(_rider.governor.status()["desired_mode"]), SafetyGovernor.MODE_SAFE)
	for _s in int(SafetyGovernor.SWITCH_SPACING_S / Wl.SIM_DT):
		_client.step()
	assert_eq(str(_rider.governor.status()["desired_mode"]), SafetyGovernor.MODE_SAFE)


func test_a_later_phase_of_the_same_mode_needs_no_wait() -> void:
	_send_plan(_flip_plan(6))
	_phase(0, 1)
	_client.step()
	_phase(2, 2)
	assert_eq(_client._held_rider_phase, -1, "ERG to ERG is no switch")
	assert_eq(int(_rider.governor.status()["phase_index"]), 2)


func test_a_new_plan_cancels_what_waited() -> void:
	_send_plan(_flip_plan(4))
	_phase(0, 1)
	_client.step()
	for _s in int(SafetyGovernor.SWITCH_SPACING_S / Wl.SIM_DT) + 2:
		_client.step()
	_phase(1, 2)
	_phase(2, 3)
	assert_eq(_client._held_rider_phase, 2)
	_send_plan(_flip_plan(4))
	assert_eq(_client._held_rider_phase, -1)
