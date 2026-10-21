extends SceneTree
## Writes Workout's game picker card (16:9, 640 x 360) from WorkoutArt's procedural art:
##
##   tools/godot.sh --headless --path . -s src/games/workout/tools/make_picker_card.gd
##
## Optional user argument: -- --out=<path> (default res://assets/workout/picker_card.png).
## Deterministic: the same code always writes the same pixels (the card test checks the
## committed PNG against a fresh render). Re-import afterwards (tools/godot.sh --import).

const DEFAULT_OUT := "res://assets/workout/picker_card.png"


func _initialize() -> void:
	var out := DEFAULT_OUT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr("--out=".length())
	var img := WorkoutArt.picker_card()
	var path := ProjectSettings.globalize_path(out) if out.begins_with("res://") else out
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := img.save_png(path)
	if err != OK:
		printerr("make_picker_card: cannot write %s (error %d)" % [path, err])
		quit(1)
		return
	print("make_picker_card: wrote %s (%d x %d)" % [path, img.get_width(), img.get_height()])
	quit(0)
