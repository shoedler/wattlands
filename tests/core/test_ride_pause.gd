extends GutTest
## RidePause (BRIEF 3.5): not_pedaling (power < 15 W and cadence < 20 rpm) held for 5 s pauses;
## 1 s at >= 30 rpm resumes; a breaking value restarts either count.


func test_enter_after_5_s_and_resume_after_1_s() -> void:
	var p := RidePause.new()
	assert_false(p.update(0.0, 0.0, 0.0))
	assert_false(p.update(4.99, 10.0, 15.0), "still not pedaling, 4.99 s")
	assert_true(p.update(5.0, 0.0, 0.0), "5 s")
	assert_true(p.paused)
	assert_false(p.update(6.0, 50.0, 29.0), "29 rpm never resumes")
	assert_false(p.update(7.0, 50.0, 30.0))
	assert_false(p.update(7.95, 50.0, 30.0))
	assert_true(p.update(8.0, 50.0, 30.0), "1 s at 30 rpm")
	assert_false(p.paused)


func test_breaks_restart_the_counts() -> void:
	var p := RidePause.new()
	p.update(0.0, 0.0, 0.0)
	p.update(4.0, 20.0, 0.0)
	assert_false(p.update(8.0, 0.0, 0.0), "15 W or more is pedaling: restarted at 8 s")
	assert_true(p.update(13.0, 0.0, 0.0))
	p.update(14.0, 0.0, 40.0)
	p.update(14.5, 0.0, 10.0)
	assert_false(p.update(15.4, 0.0, 40.0), "a low sample restarts the 1 s")
	assert_true(p.update(16.4, 0.0, 40.0))
	p.update(17.0, 0.0, 0.0)
	p.reset()
	assert_false(p.paused)
