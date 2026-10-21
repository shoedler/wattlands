extends GutTest
## MiniatureCameraRig (BRIEF 3.9; OWNERSHIP W3D3; Siege S3 "Camera"): limits, the high
## three-quarter placement, the push-in, the decaying shake and framing.


func _rig() -> MiniatureCameraRig:
	var r: MiniatureCameraRig = autofree(MiniatureCameraRig.new())
	r.auto_process = false
	return r


func test_defaults_match_the_miniature_view() -> void:
	var r := _rig()
	assert_eq(r.pitch_deg, 42.0)
	assert_true(r.fov_deg >= 30.0 and r.fov_deg <= 35.0, "Siege: FOV 30-35")
	assert_eq(r.camera.fov, r.fov_deg)
	assert_eq(r.max_shake_m, 0.15)


func test_pitch_yaw_fov_distance_are_clamped() -> void:
	var r := _rig()
	r.pitch_deg = 89.0
	assert_eq(r.pitch_deg, r.max_pitch_deg)
	r.pitch_deg = 5.0
	assert_eq(r.pitch_deg, r.min_pitch_deg)
	r.orbit_limit_deg = 20.0
	r.yaw_deg = 45.0
	assert_eq(r.yaw_deg, 20.0, "limited orbit")
	r.orbit(-100.0)
	assert_eq(r.yaw_deg, -20.0)
	r.base_yaw_deg = 90.0
	assert_eq(r.yaw_deg, 70.0, "re-clamped around the new centre")
	r.fov_deg = 170.0
	assert_eq(r.fov_deg, r.max_fov_deg)
	assert_eq(r.camera.fov, r.max_fov_deg)
	r.fov_deg = 1.0
	assert_eq(r.fov_deg, r.min_fov_deg)
	r.distance = 1.0e6
	assert_eq(r.distance, r.max_distance)
	r.distance = 0.0
	assert_eq(r.distance, r.min_distance)


func test_high_three_quarter_placement_looks_at_target() -> void:
	var r := _rig()
	r.target = Vector3(3, 2, -5)
	r.distance = 100.0
	r.pitch_deg = 42.0
	r.yaw_deg = 0.0
	var pos := r.camera.position
	assert_almost_eq(pos.y - 2.0, 100.0 * sin(deg_to_rad(42.0)), 0.001, "high above the target")
	assert_almost_eq(pos.z + 5.0, 100.0 * cos(deg_to_rad(42.0)), 0.001, "from the +Z side")
	assert_almost_eq(pos.x, 3.0, 0.001)
	var forward := -r.camera.transform.basis.z
	assert_almost_eq(forward.dot((r.target - pos).normalized()), 1.0, 0.0001, "looks at the target")
	r.orbit(10.0, -2.0)
	forward = -r.camera.transform.basis.z
	assert_almost_eq(forward.dot((r.target - r.camera.position).normalized()), 1.0, 0.0001)


func test_push_in_eases_to_distance() -> void:
	var r := _rig()
	r.distance = 100.0
	watch_signals(r)
	r.push_in(1.5, 4.0)
	assert_true(r.is_pushing_in())
	assert_almost_eq(r.effective_distance(), 150.0, 0.001, "starts farther out")
	var prev := r.effective_distance()
	for i in 79:
		r.tick(0.05)
		var d := r.effective_distance()
		assert_true(d <= prev + 0.0001, "monotonic")
		assert_true(d >= 100.0 - 0.0001)
		prev = d
	assert_signal_not_emitted(r, "push_in_finished")
	r.tick(0.1)
	assert_false(r.is_pushing_in())
	assert_eq(r.effective_distance(), 100.0)
	assert_signal_emitted(r, "push_in_finished")


func test_zero_length_push_in_finishes_at_once() -> void:
	var r := _rig()
	r.distance = 80.0
	watch_signals(r)
	r.push_in(2.0, 0.0)
	assert_false(r.is_pushing_in())
	assert_eq(r.effective_distance(), 80.0)
	assert_signal_emit_count(r, "push_in_finished", 1)


func test_shake_is_bounded_and_decays() -> void:
	var r := _rig()
	r.distance = 100.0
	var rest := r.camera_position()
	r.shake(1.0, 0.5)
	assert_almost_eq(r.current_shake_amplitude(), 0.15, 0.0001, "clamped to max_shake_m")
	var moved := false
	for i in 9:
		r.tick(0.05)
		var off := r.camera.position - rest
		assert_true(off.length() <= 0.15 + 0.0001)
		assert_true(off.length() <= r.current_shake_amplitude() + 0.0001)
		if off.length() > 0.001:
			moved = true
	assert_true(moved, "the camera shakes")
	r.tick(0.1)
	assert_eq(r.current_shake_amplitude(), 0.0)
	assert_true(r.camera.position.is_equal_approx(rest), "back at rest after the shake")


func test_shake_offset_is_in_the_screen_plane() -> void:
	var r := _rig()
	r.shake(0.15, 1.0)
	r.tick(0.13)
	var off := r.shake_offset()
	assert_almost_eq(off.dot(-r.camera.transform.basis.z), 0.0, 0.0001)


func test_weaker_shake_does_not_cut_a_stronger_one() -> void:
	var r := _rig()
	r.shake(0.15, 1.0)
	r.tick(0.1)
	var amp := r.current_shake_amplitude()
	r.shake(0.02, 1.0)
	assert_eq(r.current_shake_amplitude(), amp)


func test_shake_is_deterministic() -> void:
	var a := _rig()
	var b := _rig()
	for r: MiniatureCameraRig in [a, b]:
		r.shake(0.15, 0.6)
		for i in 5:
			r.tick(0.05)
	assert_eq(a.shake_offset(), b.shake_offset())


func test_fit_width_frames_a_span() -> void:
	var r := _rig()
	r.fov_deg = 32.0
	r.fit_width(150.0)
	var hfov := 2.0 * atan(tan(deg_to_rad(32.0) * 0.5) * 16.0 / 9.0)
	assert_almost_eq(2.0 * r.distance * tan(hfov * 0.5), 150.0, 0.01)


func test_camera_is_current_in_tree() -> void:
	var r := MiniatureCameraRig.new()
	add_child_autofree(r)
	await wait_process_frames(2)
	assert_true(r.camera.current)
	assert_eq(r.camera.get_parent(), r)
