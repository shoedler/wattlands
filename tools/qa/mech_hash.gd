extends SceneTree
## Hashes what TankMech paints, so a split of tank_mech.gd can prove it moved no pixel. Not a test: float output may
## differ across machines, so only compare two runs on one binary.
##
##   tools/godot.sh --headless --path . -s tools/qa/mech_hash.gd -- --out=<file>
##
## For each kind in TankMech.RATIO, at every phase, power, time and slot colour below, paints with the rpm given (so
## _rate_of's state plays no part), and writes the sha256 of each image's bytes as JSON. A relative --out is taken from
## the project folder. Exits 0, or 1 when the file can't be written or --out is missing.

const PHASES: Array[float] = [0.0, 0.3, 0.77, 1.3]
const POWERS: Array[float] = [0.3, 1.0, 1.4]
const TIMES: Array[float] = [0.0, 1.3]
const SLOTS: Array[Color] = [Color("#c8553d"), Color("#3d8bc8")]
const RPM := 90.0


func _initialize() -> void:
	quit(_run())


func _run() -> int:
	var out := _out_path()
	if out == "":
		printerr("mech_hash: --out=<file> is required")
		return 1
	var rows := {}
	for kind: String in TankMech.RATIO:
		for phase: float in PHASES:
			for power: float in POWERS:
				for t: float in TIMES:
					for slot: Color in SLOTS:
						rows[_key(kind, phase, power, t, slot)] = _hash(kind, phase, power, t, slot)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		printerr("mech_hash: cannot write %s" % out)
		return 1
	f.store_string(JSON.stringify(rows, "\t", true))
	f.close()
	print("mech_hash: %d images, wrote %s" % [rows.size(), out])
	return 0


func _hash(kind: String, phase: float, power: float, t: float, slot: Color) -> String:
	var img := Image.create_empty(TankMech.W, TankMech.H, false, Image.FORMAT_RGBA8)
	TankMech.paint_ex(img, kind, phase, power, t, slot, RPM)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(img.get_data())
	return ctx.finish().hex_encode()


func _key(kind: String, phase: float, power: float, t: float, slot: Color) -> String:
	return "%s phase=%.2f power=%.1f t=%.1f slot=%s" % [kind, phase, power, t, slot.to_html(false)]


func _out_path() -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			var p := a.trim_prefix("--out=")
			return p if p.is_absolute_path() else ProjectSettings.globalize_path("res://" + p)
	return ""
