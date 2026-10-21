extends GutTest
## BRIEF 3.6: src/games/_template/ is a tiny working game that shows every SDK call in under 300
## lines (its .gd files plus game.json). A .gd file counts logical lines: a statement gdformat
## wraps inside brackets counts once, so the budget measures the code, not the formatter
## (docs/decisions/lead.md, 2026-10-21 lint ADR). This test lives under tests/tools/, which
## tools/new_game never copies, so a game scaffolded from the template may grow freely.

const DIR := "res://src/games/_template"


func test_the_template_stays_under_300_lines() -> void:
	var total := 0
	var da := DirAccess.open(DIR)
	assert_not_null(da)
	for f in da.get_files():
		var text := FileAccess.get_file_as_string(DIR.path_join(f))
		if f.get_extension() == "gd":
			total += logical_lines(text)
		elif f == "game.json":
			total += text.count("\n")
	assert_gt(total, 100, "the template is all there")
	assert_lt(total, 300, "%d lines" % total)


func test_logical_lines_count_a_wrapped_statement_once() -> void:
	var wrapped := 'var a := f(\n\t1,\n\t2,\n)\n# a comment (\nvar b := "("\n\n'
	assert_eq(logical_lines(wrapped), 4, "the call, the comment, b and the blank line")
	assert_eq(logical_lines("var a := f(1, 2)\nvar b := 2\n"), 2)


## Newlines outside brackets, strings and comments: one per statement, comment or blank line.
static func logical_lines(src: String) -> int:
	var depth := 0
	var lines := 0
	var i := 0
	while i < src.length():
		var c := src[i]
		if c == "#":
			var nl := src.find("\n", i)
			i = src.length() if nl < 0 else nl
			continue
		if c == '"' or c == "'":
			if src.substr(i, 3) == c.repeat(3):
				var close := src.find(c.repeat(3), i + 3)
				i = src.length() if close < 0 else close + 3
				continue
			var j := i + 1
			while j < src.length() and src[j] != c:
				j += 2 if src[j] == "\\" else 1
			i = j + 1
			continue
		if c in "([{":
			depth += 1
		elif c in ")]}":
			depth -= 1
		elif c == "\n" and depth == 0:
			lines += 1
		i += 1
	return lines


func test_the_template_shows_every_sdk_call() -> void:
	var src := FileAccess.get_file_as_string(DIR.path_join("template_game.gd"))
	for call: String in [
		"func configure(",
		"func build_effort_plans(",
		"func sim_step(",
		"func autopilot_intents(",
		"func on_rescue(",
		"func on_afk(",
		"func local_intents(",
		"func snapshot(",
		"func apply_snapshot(",
		"func apply_event(",
		"func client_predict(",
		"func int_fields(",
		"func make_view(",
		"func hud_spec(",
		"func results(",
		"func apply_progress(",
		"send_event(",
		"GameResults.from_stats(",
		"ctx.progress",
		"ctx.directives.request(",
		"ctx.directives.cadence_band(",
		"ctx.hud.toast(",
		"ctx.hud.power_band(",
		"ctx.hud.teammate_status(",
		"ctx.hud.readout(",
		"ctx.intents.send(",
		"lap_marker.emit(",
		"finished.emit(",
		"phase_changed.emit(",
		"ctx.load_content_json(",
		"ctx.rng.",
		"with_range(",
		"with_ramp(",
		"add_control(",
		"ctx.directives.course_grade(",
		"ctx.directives.end_phase(",
		"ctx.directives.replan(",
		"ctx.hud.banner(",
		"with_open(",
		"PlanPhase.sim(",
		"Wl.GRADE_GAME"
	]:
		assert_true(src.contains(call), call)
