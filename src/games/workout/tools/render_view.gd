extends SceneTree
## Renders Workout's ride view from a snapshot fixture to a PNG, for looking at the art
## (needs a renderer, so run it windowed, not --headless):
##
##   tools/godot.sh --path . -s src/games/workout/tools/render_view.gd -- --out=build/workout_view.png
##
## User arguments: --fixture=<res path> (default the rolling-road test fixture),
## --content=<id> (default rolling_road), --local=<peer> (default 2), --scale=<n> (default 2),
## --out=<path> (default build/workout_view.png).

const DEFAULT_FIXTURE := "res://tests/games/workout/fixtures/rolling_snapshot.json"

var _viewport: SubViewport = null
var _out: String = "build/workout_view.png"
var _scale: int = 2
var _frames: int = 0


func _initialize() -> void:
	var fixture := DEFAULT_FIXTURE
	var content := "rolling_road"
	var local := 2
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="):
			fixture = arg.substr(10)
		elif arg.begins_with("--content="):
			content = arg.substr(10)
		elif arg.begins_with("--local="):
			local = int(arg.substr(8))
		elif arg.begins_with("--scale="):
			_scale = maxi(1, int(arg.substr(8)))
		elif arg.begins_with("--out="):
			_out = arg.substr(6)
	var snap: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	if not (snap is Dictionary):
		printerr("render_view: cannot read %s" % fixture)
		quit(1)
		return
	var players: Array[PlayerSlot] = []
	var rows: Array = snap.get("r", [])
	for i in rows.size():
		var peer := int(rows[i][0])
		var s := PlayerSlot.new()
		s.peer_id = peer
		s.name = "Rider %d" % peer
		s.apply_look(i)
		s.is_bot = peer < 0
		players.append(s)
	var ctx := GameContext.new()
	ctx.game_id = "workout"
	ctx.content_id = content
	ctx.players = players
	ctx.role = Wl.CLIENT
	ctx.local_peer = local
	ctx.content_dir = "res://content/workout"
	ctx.strings = GameStrings.new()
	ctx.progress = ProgressStore.open("workout", "")
	ctx.progress.set_value("pennant", "pennant_star")
	var game := WorkoutGame.new()
	game.configure(ctx)
	game.apply_snapshot(_int_fields(snap))
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(640, 360)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(_viewport)
	_viewport.add_child(game)
	_viewport.add_child(game.make_view())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	var img := _viewport.get_texture().get_image()
	if img == null:
		printerr("render_view: no image (run without --headless)")
		quit(1)
		return true
	if _scale > 1:
		img.resize(img.get_width() * _scale, img.get_height() * _scale, Image.INTERPOLATE_NEAREST)
	var path := ProjectSettings.globalize_path(_out) if _out.begins_with("res://") else _out
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := img.save_png(path)
	print("render_view: wrote %s (error %d)" % [path, err])
	quit(0 if err == OK else 1)
	return true


## The fixture's numbers back to ints (JSON parses them as floats).
static func _int_fields(snap: Dictionary) -> Dictionary:
	var out := snap.duplicate(true)
	for key in ["t", "p", "pt"]:
		if out.has(key):
			out[key] = int(out[key])
	for list_key in ["r", "tl"]:
		var arr: Array = out.get(list_key, [])
		for row: Variant in arr:
			if row is Array:
				for i in (row as Array).size():
					row[i] = int(row[i])
	return out
