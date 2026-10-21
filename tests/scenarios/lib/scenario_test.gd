extends GutTest
## Base class of the BRIEF 7.4 scenario tests (owned by qa; not collected itself: GUT only runs
## test_*.gd). Each test gets a fresh temp dir as Paths.user_dir() and for its reports and FIT
## files, removed afterwards.

const S := preload("res://tests/scenarios/lib/scenario_lib.gd")

var tmp: String = ""
## Runners start_runner() made: after_each calls cleanup() on each, which deletes the runner's
## temp root (wattlands_sim_* under OS temp; W3 QT-4).
var runners: Array[GameSimRunner] = []


func before_each() -> void:
	tmp = Paths.make_temp_dir("wattlands_scenarios")
	Paths.set_override(tmp)


func after_each() -> void:
	for r in runners:
		if is_instance_valid(r):
			r.cleanup()
	runners.clear()
	Paths.set_override("")
	S.remove_tree(tmp)
	tmp = ""


func report_path(stem: String) -> String:
	return tmp.path_join("%s.json" % stem)


## A GameSimRunner set up from run_game_sim flags and added to the tree (freed after the test),
## or null after a failed assertion.
func start_runner(f: PackedStringArray) -> GameSimRunner:
	var made := S.new_runner(f)
	assert_eq(made["error"], "", "GameSimRunner.parse_args(%s)" % " ".join(f))
	if made["runner"] == null:
		return null
	var runner: GameSimRunner = made["runner"]
	add_child_autofree(runner)
	runners.append(runner)
	var err := runner.setup(made["args"])
	assert_eq(err, "", "GameSimRunner.setup(%s)" % " ".join(f))
	if err != "":
		return null
	return runner


## The host's own rider after setup (asserts it exists and rides a MockTrainer).
func human_rider(runner: GameSimRunner) -> LocalRider:
	var rider := S.rider_of(runner, S.human_peer(runner))
	assert_not_null(rider, "the host's own rider is in GameHost.local_riders")
	if rider != null:
		assert_not_null(S.mock_of(rider), "the rider rides a MockTrainer")
	return rider


## Up to `limit` problems, then a count of the rest.
static func first(problems: Array, limit: int = 8) -> String:
	if problems.size() <= limit:
		return "\n".join(PackedStringArray(problems))
	return "%s\n... and %d more" % ["\n".join(PackedStringArray(problems.slice(0, limit))), problems.size() - limit]
