extends SceneTree
## Writes Turbo Reel's sprites from FishingArtGrids:
##   tools/godot.sh --headless --path . -s src/games/fishing/tools/fishing_write_sprites.gd
##     [-- --sheet=<abs path>]
## Each sprite becomes assets/fishing/sprites/<id>.png with its frames side by side; sprites.json
## lists {size (one frame), frames, anchor}; art.json records the palette and the sprite list for
## the art pipeline. PNGs in the folder that no sprite owns are deleted. It also writes the pixel
## font's glyph grid (FONT_PNG). --sheet also writes a 4x preview of every sprite (and the
## assembled boat, driving and fishing) for a look.

const DIR := "res://assets/fishing/sprites"
const ART_JSON := "res://assets/fishing/art.json"
const SHEET_SCALE := 4
## The pixel font's glyph grid (FishingFontGrids.font_image), read by the Image Font importer.
const FONT_PNG := "res://assets/fishing/font/turbo_reel_5x7.png"


func _init() -> void:
	var sprites := FishingArtGrids.build()
	var index := {}
	for id: String in sprites:
		var e: Dictionary = sprites[id]
		var frames: Array[Image] = []
		frames.assign(e["frames"])
		var strip := strip_of(frames)
		var err := strip.save_png(DIR.path_join(id + ".png"))
		if err != OK:
			push_error("fishing_write_sprites: could not write %s (%d)" % [id, err])
			quit(1)
			return
		var a: Vector2i = e["anchor"]
		index[id] = {
			"size": [frames[0].get_width(), frames[0].get_height()],
			"frames": frames.size(),
			"anchor": [a.x, a.y],
		}
	var font := FishingFontGrids.font_image()
	if font.save_png(FONT_PNG) != OK:
		push_error("fishing_write_sprites: could not write %s" % FONT_PNG)
		quit(1)
		return
	_prune(sprites)
	_write_json(DIR.path_join("sprites.json"), {"sprites": index})
	_write_json(ART_JSON, art_json(sprites))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sheet="):
			sheet(sprites).save_png(arg.trim_prefix("--sheet="))
	print("fishing_write_sprites: %d sprites" % sprites.size())
	quit(0)


## Frames side by side, one frame wide each.
static func strip_of(frames: Array[Image]) -> Image:
	var w := frames[0].get_width()
	var h := frames[0].get_height()
	var out := Image.create_empty(w * frames.size(), h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for k in frames.size():
		out.blit_rect(frames[k], Rect2i(0, 0, w, h), Vector2i(k * w, 0))
	return out


## The art pipeline's description of the hand-authored set (no fal requests are needed).
static func art_json(sprites: Dictionary) -> Dictionary:
	var pal: Array[String] = []
	for c in FishingPalette.ALL:
		pal.append("#" + c.to_html(false))
	var list: Array = []
	for id: String in sprites:
		var e: Dictionary = sprites[id]
		var f: Image = (e["frames"] as Array)[0]
		var entry := {
			"id": id,
			"prompt": str(e["desc"]),
			"size": [f.get_width(), f.get_height()],
			"_source": "hand-authored grid, FishingArtGrids",
		}
		if id.begins_with("card_"):
			entry["background"] = "opaque"
		list.append(entry)
	return {
		"palette": pal,
		"style":
		"one cool hue family, one warm accent, flat top-lit planes, no outlines, no dither",
		"notes": "Written by src/games/fishing/tools/fishing_write_sprites.gd; edit the grids.",
		"sprites": list,
	}


## Every sprite at SHEET_SCALE on the sky colour, then the assembled boat driving and fishing.
static func sheet(sprites: Dictionary) -> Image:
	var rows: Array[Image] = []
	for id: String in sprites:
		var frames: Array[Image] = []
		frames.assign(sprites[id]["frames"])
		rows.append(strip_of(frames))
	rows.append(FishingArtGrids.boat(false, 1))
	rows.append(FishingArtGrids.boat(true, 1))
	var w := 0
	var h := 0
	for r in rows:
		w = maxi(w, r.get_width())
		h += r.get_height() + 2
	var out := Image.create_empty(w + 4, h + 2, false, Image.FORMAT_RGBA8)
	out.fill(FishingPalette.SKY)
	var y := 2
	for r in rows:
		FishingArtGrids.blit(out, r, Vector2i(2, y))
		y += r.get_height() + 2
	out.resize(
		out.get_width() * SHEET_SCALE, out.get_height() * SHEET_SCALE, Image.INTERPOLATE_NEAREST
	)
	return out


static func _prune(sprites: Dictionary) -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		var id := f.get_basename().get_basename()
		if (f.ends_with(".png") or f.ends_with(".png.import")) and not sprites.has(id):
			d.remove(f)


static func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t") + "\n")
