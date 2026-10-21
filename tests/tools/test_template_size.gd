extends GutTest
## BRIEF 3.6: src/games/_template/ is a tiny working game that shows every SDK call in under 300
## lines (its .gd files plus game.json). This test lives under tests/tools/, which tools/new_game
## never copies, so a game scaffolded from the template may grow freely.

const DIR := "res://src/games/_template"


func test_the_template_stays_under_300_lines() -> void:
	var total := 0
	var da := DirAccess.open(DIR)
	assert_not_null(da)
	for f in da.get_files():
		if f.get_extension() == "gd" or f == "game.json":
			total += FileAccess.get_file_as_string(DIR.path_join(f)).count("\n")
	assert_gt(total, 100, "the template is all there")
	assert_lt(total, 300, "%d lines" % total)


func test_the_template_shows_every_sdk_call() -> void:
	var src := FileAccess.get_file_as_string(DIR.path_join("template_game.gd"))
	for call: String in ["func configure(", "func build_effort_plans(", "func sim_step(", "func autopilot_intents(",
			"func on_rescue(", "func on_afk(", "func local_intents(", "func snapshot(", "func apply_snapshot(",
			"func apply_event(", "func client_predict(", "func int_fields(", "func make_view(", "func hud_spec(",
			"func results(", "func apply_progress(", "send_event(", "GameResults.from_stats(", "ctx.progress",
			"ctx.directives.request(", "ctx.directives.cadence_band(", "ctx.hud.toast(", "ctx.hud.power_band(",
			"ctx.hud.teammate_status(", "ctx.hud.readout(", "ctx.intents.send(", "lap_marker.emit(",
			"finished.emit(", "phase_changed.emit(", "ctx.load_content_json(", "ctx.rng.", "with_range(",
			"with_ramp(", "add_control("]:
		assert_true(src.contains(call), call)
