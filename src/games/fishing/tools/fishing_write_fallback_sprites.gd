extends SceneTree
## Writes the placeholder sprites (FishingFallbackSprites) into assets/fishing/sprites/ with their
## parts and sprites.json (brief 3.4 step 5). picker_card keeps its G0 placeholder.
##
##   tools/godot.sh --headless --path . -s src/games/fishing/tools/fishing_write_fallback_sprites.gd
##   tools/godot.sh --headless --path . --import    # then commit the PNGs and their .import files
##
## Exit 0 when every sprite was written, 1 otherwise (each problem on stderr).

const Writer := preload("res://src/games/fishing/tools/fishing_fallback_writer.gd")


func _init() -> void:
	var report: Dictionary = Writer.write()
	for f: String in report["written"]:
		print("fallback sprite: %s" % f)
	for e: String in report["errors"]:
		printerr("fallback sprites: %s" % e)
	quit(0 if report["ok"] else 1)
