extends GutTest
## The one terrain sampler: the grade the rules roll the hull on (TankHullState.grade_pct) and the
## grade the director pushes with course_grade come from the same function (TankTerrain).

const DEPOT := 0
const ADVANCE := 1


func test_grade_at_interpolates_holds_and_handles_empty_profiles() -> void:
	assert_eq(TankTerrain.grade_at([], 50.0), 0.0)
	var pts := [[0, 1.0], [100, 3.0], [200, -1.0]]
	assert_eq(TankTerrain.grade_at(pts, -5.0), 1.0, "held before the first point")
	assert_eq(TankTerrain.grade_at(pts, 50.0), 2.0)
	assert_eq(TankTerrain.grade_at(pts, 100.0), 3.0)
	assert_eq(TankTerrain.grade_at(pts, 150.0), 1.0)
	assert_eq(TankTerrain.grade_at(pts, 999.0), -1.0, "held past the last point")


func test_for_segment_clamps_to_the_envelope_and_the_warm_up_range() -> void:
	var c := TankFixtures.content()
	for seg in c.segments().size():
		for m in range(0, 1600, 10):
			for warm in [false, true]:
				var g := TankTerrain.for_segment(c, seg, float(m), warm)
				if warm:
					assert_between(g, 0.0, 2.0, "warm-up terrain 0..+2%% (seg %d, %d m)" % [seg, m])
				else:
					assert_between(g, -3.0, 6.0, "terrain -3..+6%% (seg %d, %d m)" % [seg, m])
				assert_eq(g, TankDirector.terrain_grade_pct(c, seg, float(m), warm))


## Every tick of a driven Advance and of the depot, the hull's grade is the director's grade at the
## distance the tick started from.
func test_the_hull_rolls_on_the_grade_the_director_pushes() -> void:
	for seg in [ADVANCE, DEPOT]:
		var rig := TankRulesRig.new(1)
		rig.enter(seg, 5.0)
		var warm: bool = rig.state.seg.kind == Wl.WARMUP
		var checked := 0
		for i in 1200:
			var before := rig.hull().distance_m
			rig.step()
			var want := TankDirector.terrain_grade_pct(
				rig.state.content, rig.state.seg.segment_index, before, warm
			)
			assert_eq(rig.hull().grade_pct, want, "seg %d tick %d at %.2f m" % [seg, i, before])
			if rig.hull().speed_mps > 0.0:
				checked += 1
		assert_gt(checked, 600, "the tank was driving")
