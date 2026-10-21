extends SceneTree
## tools/fit_decode/decode.gd: the GDScript FIT decoder's command line (BRIEF 3.8). Owned by qa.
## tools/fit_check/check.mjs runs it when @garmin/fitsdk can't be loaded; anyone can run it:
##
##   tools/godot.sh --headless --path . -s tools/fit_decode/decode.gd -- <file|dir>...
##       [--expect-laps=<n>] [--json] [--out=<file>]
##
## Directories are searched recursively for *.fit. Prints per file its errors, record count, laps
## (start, duration) and session totals (with --json: one JSON line, schema in
## docs/decisions/qa.md; Godot prints its own header line first, so --out=<file> is the cleanest
## way for another program to read it). Exit code 0 when every file decoded without errors,
## 1 on any error, 2 on a usage error.

const Decoder := preload("res://tools/fit_decode/lib/fit_decoder.gd")


func _initialize() -> void:
	var result: Dictionary = Decoder.run_cli(OS.get_cmdline_user_args())
	for line: String in result["out"]:
		print(line)
	for line: String in result["err"]:
		printerr(line)
	quit(int(result["code"]))
