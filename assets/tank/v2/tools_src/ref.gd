extends SceneTree
# Decodes THE reference (assets/tank/v2/source/reference.webp, 1088x608) to build/v2/ref.png, the input of
# plate.gd, tankfix.gd, tank.gd and assemble.gd.


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/v2/view"))
	var img := Image.new()
	var err := img.load_webp_from_buffer(FileAccess.get_file_as_bytes("res://assets/tank/v2/source/reference.webp"))
	if err != OK:
		push_error("ref.gd: cannot decode the reference (%d)" % err)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	img.save_png("res://build/v2/ref.png")
	print("ref.png %dx%d" % [img.get_width(), img.get_height()])
	quit()
