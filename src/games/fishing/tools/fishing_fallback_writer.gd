extends RefCounted
## Writes FishingFallbackSprites' images to a sprite folder the way tools/art/pixelate.gd writes
## generated ones (brief 3.4 step 5, docs/ART_PIPELINE.md): `<id>.png`, `<id>__<part>.png` for
## every art.json part, and `sprites.json` (file, size, anchor, align, background, tile, mirror,
## parts) for every art.json sprite with a PNG in the folder, plus `"art_mode": "placeholder"`.
## picker_card is never written (it keeps its G0 placeholder) but is indexed. Files are written
## only when their bytes change, so a re-run is byte-identical. Editor-time only (it uses the
## pipeline's ArtPixelate helpers); fishing_write_fallback_sprites.gd runs it.

const ART_JSON := "res://assets/fishing/art.json"
const SPRITE_DIR := "res://assets/fishing/sprites"
const INDEX_FILE := "sprites.json"
const KEEP := ["picker_card"]


## Writes every fallback sprite of `art_path` into `out_dir`. Returns {"ok": bool, "written":
## [file names], "errors": [String]}.
static func write(out_dir: String = SPRITE_DIR, art_path: String = ART_JSON) -> Dictionary:
	var report := {"ok": false, "written": [], "errors": []}
	var errors: Array = report["errors"]
	var art: Variant = JSON.parse_string(FileAccess.get_file_as_string(art_path))
	if not art is Dictionary or not (art as Dictionary).get("sprites") is Array:
		errors.append("%s: not an art.json" % art_path)
		return report
	DirAccess.make_dir_recursive_absolute(out_dir)
	for s: Dictionary in art["sprites"]:
		var spec: Dictionary = ArtPixelate.normalize_sprite(s, art)
		var id: String = spec["id"]
		if KEEP.has(id):
			continue
		if not FishingFallbackSprites.has(id):
			errors.append("%s: no fallback drawing" % id)
			continue
		var img := FishingFallbackSprites.image(id)
		if img.get_size() != spec["size"]:
			errors.append("%s: drawn at %s, art.json says %s" % [id, img.get_size(), spec["size"]])
			continue
		_put(report, out_dir, id + ".png", img)
		var parts: Dictionary = spec["parts"]
		var names: Array = parts.keys()
		names.sort()
		for part_name: String in names:
			_put(
				report,
				out_dir,
				ArtPixelate.part_file_name(id, part_name),
				img.get_region(parts[part_name])
			)
	_write_index(report, art, out_dir)
	report["ok"] = errors.is_empty()
	return report


static func _put(report: Dictionary, out_dir: String, file: String, img: Image) -> void:
	if ArtPixelate.write_if_changed(out_dir.path_join(file), img.save_png_to_buffer()) != OK:
		(report["errors"] as Array).append("cannot write %s" % out_dir.path_join(file))
		return
	(report["written"] as Array).append(file)


## sprites.json in pixelate.gd's format (sorted keys, two-space indent), with no `source`.
static func _write_index(report: Dictionary, art: Dictionary, out_dir: String) -> void:
	var sprites := {}
	for s: Dictionary in art["sprites"]:
		var spec: Dictionary = ArtPixelate.normalize_sprite(s, art)
		var id: String = spec["id"]
		if not FileAccess.file_exists(out_dir.path_join(id + ".png")):
			continue
		var size: Vector2i = spec["size"]
		var anchor: Vector2 = ArtPixelate.anchor_point(spec["anchor"], size)
		var parts := {}
		for part_name: String in (spec["parts"] as Dictionary).keys():
			var r: Rect2i = spec["parts"][part_name]
			parts[part_name] = {
				"file": ArtPixelate.part_file_name(id, part_name),
				"rect": [r.position.x, r.position.y, r.size.x, r.size.y]
			}
		sprites[id] = {
			"file": id + ".png",
			"size": [size.x, size.y],
			"anchor": [_num(anchor.x), _num(anchor.y)],
			"align": spec["align"],
			"background": spec["background"],
			"tile": spec["tile"],
			"mirror": spec["mirror"],
			"parts": parts,
		}
	var index := {
		"game": "fishing", "palette": art["palette"], "sprites": sprites, "art_mode": "placeholder"
	}
	var text := JSON.stringify(index, "  ", true) + "\n"
	if ArtPixelate.write_if_changed(out_dir.path_join(INDEX_FILE), text.to_utf8_buffer()) != OK:
		(report["errors"] as Array).append("cannot write %s" % out_dir.path_join(INDEX_FILE))
		return
	(report["written"] as Array).append(INDEX_FILE)


static func _num(v: float) -> Variant:
	return int(v) if v == floorf(v) else v
