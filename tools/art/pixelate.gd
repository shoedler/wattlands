extends SceneTree
## Pixelates a game's generated art (BRIEF 3.10, docs/ART_PIPELINE.md):
##
##   tools/godot.sh --headless --path . -s tools/art/pixelate.gd -- --game=<id> [--root=<dir>] [--only=<ids>]
##
## Reads <root>/assets/<id>/art.json and art_manifest.json, uses only each sprite's selected result
## (raw PNG in <root>/.art_cache/<id>/), and writes <root>/assets/<id>/sprites/<sprite id>.png, one
## <sprite id>__<part>.png per part and sprites.json. <root> defaults to this project; a relative
## <root> is relative to the project. The work is in
## ArtPixelate (tools/art/pixelate_lib.gd). Exits 0 when every selected sprite was written (sprites
## without a selected result are skipped with a warning), 1 on any error, 2 on bad arguments.


func _initialize() -> void:
	var args: Dictionary = CmdLine.parse(OS.get_cmdline_user_args())
	for key: String in args.keys():
		if not ["game", "root", "only"].has(key):
			printerr("pixelate: unknown option --%s (usage: -- --game=<id> [--root=<dir>] [--only=<ids>])" % key)
			quit(2)
			return
	var game: String = _last(args, "game")
	if game.is_empty() or game == "true":
		printerr("pixelate: --game=<id> is required (usage: -- --game=<id> [--root=<dir>] [--only=<ids>])")
		quit(2)
		return
	# --root: absolute, res://, or relative to this project (the wrapper runs with --path .).
	var root: String = _last(args, "root").replace("\\", "/")
	if root.is_empty() or root == "true":
		root = ProjectSettings.globalize_path("res://")
	elif root.begins_with("res://"):
		root = ProjectSettings.globalize_path(root)
	elif root.is_relative_path():
		root = ProjectSettings.globalize_path("res://").path_join(root)
	var only: PackedStringArray = PackedStringArray()
	for v: Variant in args.get("only", []):
		for id: String in str(v).split(",", false):
			only.append(id.strip_edges())
	print("pixelate: %s from %s" % [game, root])
	var report: Dictionary = ArtPixelate.run_game(root, game, only)
	for path: Variant in report["written"]:
		print("pixelate: wrote %s" % path)
	for id: Variant in report["skipped"]:
		print("pixelate: skipped %s (no selected result)" % id)
	for msg: Variant in report["errors"]:
		printerr("pixelate: error: %s" % msg)
	var ok: bool = report["ok"]
	print(
		"pixelate: %d file(s) written, %d sprite(s) skipped, %d error(s), %d warning(s)"
		% [(report["written"] as Array).size(), (report["skipped"] as Array).size(), (report["errors"] as Array).size(), (report["warnings"] as Array).size()]
	)
	quit(0 if ok else 1)


func _last(args: Dictionary, key: String) -> String:
	var vals: Array = args.get(key, [])
	return "" if vals.is_empty() else str(vals[vals.size() - 1])
