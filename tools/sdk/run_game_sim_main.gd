extends SceneTree
## Godot entry point of tools/run_game_sim and tools/run_game_sim.ps1 (BRIEF 3.6). Start it only
## through those wrappers: they set WATTLANDS_NO_HW_CONTROL=1 and WATTLANDS_NO_NETWORK_INTEGRATIONS=1,
## add --mock-trainer=erg and --caller-cwd, and run
##   tools/godot.sh --headless --path <repo> -s tools/sdk/run_game_sim_main.gd -- <flags>
## The work happens in GameSimCli (tools/sdk/game_sim_cli.gd), on the first frame, once every
## autoload is ready. The process exits with GameSimCli.main()'s exit code (5 when Godot logged a
## script error during the run, so a run that broke never reads as a success).

var _started: bool = false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		quit(GameSimCli.new().main(OS.get_cmdline_user_args(), root))
	return false
