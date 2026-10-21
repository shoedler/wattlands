extends GutTest
## .zwo content (BRIEF 3.7): zwo_sample imports content/workout/zwo/sample.zwo through the
## platform's ZwoImport, "zwo:<path>" imports any file, and the importer's clamps and
## warnings show in session_preview(). ZwoImport is still a stub in W1, so these tests
## inject a parser with the same result shape; tests/games/workout/integration/ runs the
## real importer.

const U := preload("res://tests/games/workout/workout_test_util.gd")
const SAMPLE := "res://content/workout/zwo/sample.zwo"
const CLAMPS: Array[String] = [
	"block 1: 0.70 -> 0.65 (warm-up limit)",
	"block 5: 1.10 -> 1.05 (phase > 300 s cap)",
	"block 7: 1.60 -> 1.50 (150% ceiling)",
]
const WARNINGS: Array[String] = ["MaxEffort: unsupported tag, skipped"]

var _paths: Array[String] = []
var _tr: Translation = null


func before_all() -> void:
	_tr = U.register_strings()


func after_all() -> void:
	U.unregister_strings(_tr)


func before_each() -> void:
	_paths.clear()
	WorkoutSession.zwo_parser = _fake_parser


func after_each() -> void:
	WorkoutSession.zwo_parser = Callable()


## What ZwoImport.parse_zwo_file returns for the sample (clamped, warm-up first, no
## cool-down appended), including an imported Cooldown block and a FreeRide.
func _fake_parser(path: String) -> Dictionary:
	_paths.append(path)
	var phases: Array = [
		PlanPhase.erg(Wl.WARMUP, 50.0, 300.0, "").with_ramp(65.0),
		PlanPhase.erg(Wl.WORK, 75.0, 240.0, ""),
	]
	for i in 3:
		phases.append(PlanPhase.erg(Wl.WORK, 110.0, 60.0, ""))
		phases.append(PlanPhase.erg(Wl.RECOVERY, 55.0, 120.0, ""))
	phases.append(PlanPhase.erg(Wl.WORK, 60.0, 180.0, "").with_ramp(85.0))
	phases.append(PlanPhase.erg(Wl.WORK, 105.0, 420.0, ""))
	phases.append(PlanPhase.sim(Wl.WORK, Wl.GRADE_FLAT, 60.0, ""))
	phases.append(PlanPhase.erg(Wl.WORK, 150.0, 30.0, "").to_dict())
	phases.append(PlanPhase.erg(Wl.COOLDOWN, 60.0, 120.0, "").with_ramp(45.0))
	return {"ok": true, "name": "Sample builds", "description": "", "phases": phases, "blocks": [],
		"clamps": CLAMPS.duplicate(), "warnings": WARNINGS.duplicate(), "error": ""}


func test_zwo_sample_imports_through_the_parser() -> void:
	var g := U.game("zwo_sample", U.players(1, 1))
	autofree(g)
	assert_eq(_paths, ["res://content/workout/zwo/sample.zwo"])
	var s := g.session
	assert_not_null(s)
	assert_eq(s.source, "zwo")
	assert_eq(s.label, "WORKOUT_CONTENT_ZWO_SAMPLE", "the session file's own label")
	assert_eq(s.phases.size(), 13)
	for p in s.phases:
		assert_true(p.lap, "every phase is a lap")
		assert_ne(p.label.strip_edges(), "", "every phase has a label")
		assert_ne(p.kind, Wl.COOLDOWN, "the platform appends the cool-down")
	assert_eq(s.phases[0].label, "Block 1")
	assert_eq(s.phases[10].kind, Wl.FREE, "FreeRide rides as a FREE phase (SIM flat)")
	assert_eq(s.phases[10].mode, Wl.SIM)
	assert_eq(s.phases[12].kind, Wl.RECOVERY, "an imported cool-down block becomes RECOVERY")
	assert_eq(s.phases[11].target_pct, 150.0, "dictionaries are accepted too")
	assert_eq(s.clamps, CLAMPS)
	assert_eq(s.warnings, WARNINGS)
	var plans := g.build_effort_plans()
	assert_eq(plans.size(), 2)
	assert_eq((plans[-1] as EffortPlan).size(), 13)


func test_preview_lists_the_clamps() -> void:
	var g := WorkoutGame.new()
	autofree(g)
	var pv := g.session_preview("zwo_sample")
	assert_eq(pv["title"], "Sample builds")
	var lines: Array = pv["lines"]
	assert_eq(lines.size(), 13 + CLAMPS.size() + WARNINGS.size())
	var text := "\n".join(PackedStringArray(lines))
	for c in CLAMPS:
		assert_string_contains(text, c)
	assert_string_contains(text, "Clamped: block 5")
	assert_string_contains(text, "Skipped: MaxEffort")
	assert_almost_eq(float(pv["total_s"]), 1890.0 + 180.0, 0.001)


func test_zwo_path_content_id() -> void:
	var abs_path := ProjectSettings.globalize_path(SAMPLE)
	var id := "zwo:" + abs_path
	var g := U.game(id, U.players(1))
	autofree(g)
	assert_eq(_paths, [abs_path], "the parser gets the path after zwo:")
	assert_not_null(g.session)
	assert_eq(g.session.id, id)
	assert_eq(g.session.label, "WORKOUT_CONTENT_ZWO")
	assert_eq(g.session.zwo_path, abs_path)
	assert_eq(g.build_effort_plans().size(), 1)
	assert_false(g.session_preview(id).is_empty())


func test_missing_zwo_file() -> void:
	assert_null(WorkoutSession.load_id("zwo:C:/no/such/file.zwo"))
	assert_push_error("not found")
	assert_true(_paths.is_empty(), "the parser never runs for a missing file")


func test_a_client_without_the_file_only_warns() -> void:
	var g := U.game("zwo:C:/no/such/file.zwo", U.players(2), Wl.CLIENT, 2)
	autofree(g)
	assert_null(g.session)
	assert_push_warning("not found here")
	assert_eq(g.state.phases.size(), 0, "the timeline arrives with the snapshots")


func test_parser_failure_is_an_error() -> void:
	WorkoutSession.zwo_parser = func(_p: String) -> Dictionary: return {"ok": false, "error": "bad xml"}
	assert_null(WorkoutSession.load_id("zwo_sample"))
	assert_push_error("bad xml")


func test_unsafe_imported_blocks_are_rejected() -> void:
	WorkoutSession.zwo_parser = func(_p: String) -> Dictionary:
		return {"ok": true, "phases": [PlanPhase.erg(Wl.WORK, 180.0, 30.0, "x")], "clamps": [], "warnings": []}
	assert_null(WorkoutSession.load_id("zwo_sample"))
	assert_push_error("target_pct")
