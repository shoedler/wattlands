extends GutTest
## Enemy spacing (brief 2.4 Spacing): every held position is reserved in a depth lane (enemies.json
## lanes), so no two enemies on one side and lane overlap, at a gun line or in an Advance; the
## snapshot carries the lane for the view.

const ADVANCE := 1
const GUN_LINES := [2, 5, 8]


## [start, end] of `e`'s held box with its weave, along the distance from the hull's nearer end.
func _span(rig: TankRulesRig, e: TankEnemyState) -> Array[float]:
	var pad := TankEnemies.pad_of(rig.state, e)
	return [e.hold_px - pad, e.hold_px + float(e.w) + pad]


## Every pair of live enemies on one side and lane keeps its held boxes apart.
func _assert_apart(rig: TankRulesRig, at: String) -> void:
	var aux := TankAux.of(rig.state)
	var list := rig.state.enemies.filter(
		func(e: TankEnemyState) -> bool: return TankEnemies.holds_position(aux, e)
	)
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a: TankEnemyState = list[i]
			var b: TankEnemyState = list[j]
			if a.side != b.side or a.lane != b.lane:
				continue
			var sa := _span(rig, a)
			var sb := _span(rig, b)
			var apart := sa[1] <= sb[0] + 1e-6 or sb[1] <= sa[0] + 1e-6
			assert_true(
				apart,
				(
					"%s: %s at %.0f and %s at %.0f share lane %d"
					% [
						at,
						TankIds.enemy_of(a.code),
						a.hold_px,
						TankIds.enemy_of(b.code),
						b.hold_px,
						a.lane
					]
				)
			)


func test_no_two_gun_line_enemies_share_a_lane_and_a_spot_for_any_tank() -> void:
	for crew in [1, 2, 3, 4]:
		for index: int in GUN_LINES:
			var rig := TankRulesRig.new(crew)
			rig.enter(index, 0.5)
			assert_gt(rig.state.enemies.size(), 2)
			_assert_apart(rig, "crew %d gun line %d" % [crew, index])
			for e in rig.state.enemies:
				assert_between(e.lane, 0, int(rig.content.num("enemies", "lanes.count")) - 1)


func test_copies_of_one_encounter_spread_over_lanes_and_distances() -> void:
	var rig := TankRulesRig.new(4)
	rig.no_fire = true
	rig.no_bow = true
	rig.enter(ADVANCE, 1.0)
	rig.state.enemies.clear()
	var aux := TankAux.of(rig.state)
	for _i in 4:
		TankEnemies.spawn(rig.state, aux, TankIds.ENEMY_LIGHT, 1, 130.0, false, false, 0)
	_assert_apart(rig, "four lights wanting 130 px")
	var lanes := {}
	for e in rig.state.enemies:
		lanes[e.lane] = true
	assert_gt(lanes.size(), 1, "they use more than one lane")
	rig.run(20.0)
	_assert_apart(rig, "after they rolled in and weaved")


func test_an_advance_never_stacks_holds_while_it_plays() -> void:
	for crew in [1, 4]:
		var rig := TankRulesRig.new(crew)
		rig.enter(ADVANCE, 0.0)
		var most := 0
		for _i in 180:
			rig.run(1.0)
			most = maxi(most, rig.state.enemies.size())
			_assert_apart(rig, "crew %d at %.0f s" % [crew, rig.seg_t])
		assert_gt(most, 0, "crew %d: enemies came" % crew)


func test_a_destroyer_shift_and_a_heavy_back_off_respect_the_lanes() -> void:
	var rig := TankRulesRig.new(3)
	rig.no_fire = true
	rig.no_bow = true
	rig.enter(ADVANCE, 1.0)
	rig.state.enemies.clear()
	var edge := TankEnemies.clamp_hold(rig.state, 109, 1, 1.0e9)
	var d := rig.spawn(TankIds.ENEMY_DESTROYER, 1, edge)
	var blocker := rig.spawn(TankIds.ENEMY_MEDIUM, 1, edge - 60.0)
	blocker.lane = d.lane
	blocker.hold_px = edge - 60.0
	blocker.gun_s = 1.0e6
	d.gun_s = 0.1
	rig.run(8.0)
	assert_eq(rig.of_type("shot").size(), 1, "after its full 7 s glint")
	_assert_apart(rig, "after the destroyer's shift")
	var h := rig.spawn(TankIds.ENEMY_HEAVY, 1, 60.0)
	h.gun_s = 1.0e6
	var other := rig.spawn(TankIds.ENEMY_HEAVY, 1, 60.0 + float(h.w) + 10.0)
	other.lane = h.lane
	other.gun_s = 1.0e6
	TankEnemies.back_off(rig.state, h)
	_assert_apart(rig, "after the heavy's back-off")


func test_two_rear_lights_take_two_lanes() -> void:
	var rig := TankRulesRig.new(2)
	rig.no_fire = true
	rig.no_bow = true
	rig.enter(ADVANCE, 1.0)
	rig.state.enemies.clear()
	var aux := TankAux.of(rig.state)
	var a := TankEnemies.spawn(rig.state, aux, TankIds.ENEMY_LIGHT, -1, -1.0, false, false, 0)
	var b := TankEnemies.spawn(rig.state, aux, TankIds.ENEMY_LIGHT, -1, -1.0, false, false, 0)
	assert_ne(a.lane, b.lane, "both show their 24 px at the left edge, in two lanes")
	assert_eq(a.hold_px, b.hold_px)


func test_the_snapshot_carries_the_lane() -> void:
	var host := TankFixtures.state(3)
	host.enemies[0].lane = 3
	var snap := TankSnapshot.encode(host)
	assert_eq(int(snap["e"][0][TankSnapshotSchema.E_LANE]), 3)
	var client := TankFixtures.state(3)
	client.enemies.clear()
	TankSnapshot.apply(client, snap)
	assert_eq(client.enemy(host.enemies[0].id).lane, 3)
