class_name GameSimRunner
extends Node
## In-process, headless (or windowed) simulation of a whole session with MockTrainer riders
## (BRIEF 3.6 tools/run_game_sim, tools/screenshot). Owned by sdk-runtime; public API frozen
## after W0. qa's tools/screenshot reuses it windowed.
##
## One human slot (with or without bots) runs SOLO; two or more run as HOST with
## LoopbackTransport clients, one GameHost and NetSession per human slot. Every human slot
## has its own MockTrainer and governor; bots are added after the humans.
## args (the run_game_sim flags, parsed): game, content, players (int), bots (int),
## riders (Array[String] per human slot), sim_speed, seed, report (path), autopilot
## ("all" | "none" | Array[int] slots), ftp (Array[float]), unverified (bool),
## haptics_off (Array[int]), options (Dictionary), player_options (Array[Dictionary]),
## override (Dictionary of content patches), max_sim_seconds (float), headless (bool).

var host: GameHost = null


## The one flag parser shared by tools/run_game_sim and tools/screenshot: turns
## "--game=... --players=2 --rider=erg --rider=zero --ftp=180,220 ..." into the args
## Dictionary setup() takes ({"error": String} on a bad flag).
static func parse_args(_args: PackedStringArray) -> Dictionary:
	return {"error": "not implemented"}


## "" on success, else an error (invalid args, invalid game, invalid plan).
func setup(_args: Dictionary) -> String:
	return "not implemented"


## One fixed platform step for every peer (host first, then clients, then loopback poll).
func step() -> void:
	pass


## Run until the cool-down finishes, max_sim_seconds, or 120 s of platform time paused
## (SOLO). Returns end_reason: "complete", "timeout" or "paused".
func run_to_end() -> String:
	return "timeout"


## Platform seconds simulated so far.
func sim_seconds() -> float:
	return 0.0


## The JSON report (BRIEF 3.6): schema, args, slots, plans, plan_warnings, overrides,
## end_reason, finished_reason, events, phases, directives (requested and applied), 1 Hz
## traces, snapshots (sha256 and JSON byte size: UTF-8 length of JSON.stringify(state)),
## max_snapshot_bytes, oversize_snapshots, results, fit_paths, meta, deterministic_hash
## (sha256 of the report without paths and wall-clock fields).
func build_report() -> Dictionary:
	return {}


## Write the report to args.report (and FIT files under <report dir>/fit/). Returns path.
func write_report() -> String:
	return ""
