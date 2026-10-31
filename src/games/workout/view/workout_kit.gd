class_name WorkoutKit
extends RefCounted
## assets/workout/kit.json: where every sprite of Workout's art is and how it lines up, written by
## src/games/workout/art/bake.mjs. Loaded once, validated at load (push_error on a missing key or
## file), and it hands out each texture once.

const PATH := "res://assets/workout/kit.json"
const REQUIRED: Array[String] = [
	"version",
	"base",
	"lut",
	"tod",
	"rider",
	"wheel",
	"fx",
	"planes",
	"sun",
	"road",
	"props",
]
const RIDER_KEYS: Array[String] = [
	"cell",
	"cols",
	"frames",
	"origin",
	"rear_hub",
	"front_hub",
	"pennant_foot",
	"mouth_by_pose",
	"bubble",
	"rear_contact",
	"pose_rows",
	"slots",
	"slot_colors",
	"near_pedal",
]
const PLANE_NAMES: Array[String] = [
	"sky",
	"stars",
	"clouds_hi",
	"clouds_lo",
	"far_hills",
	"mid_hills",
	"near_trees",
	"poles",
	"foreground",
]
const PROP_NAMES: Array[String] = [
	"windpump",
	"cattle",
	"tractor",
	"smoke",
	"flock",
	"balloon",
	"crowd",
	"flag",
	"gantry",
]

static var _shared: WorkoutKit = null

var data: Dictionary = {}
var rider: Dictionary = {}
var road: Dictionary = {}
var props: Dictionary = {}
var tod: Array = []
var _textures: Dictionary = {}


## The one kit (kit.json does not change while the game runs).
static func shared() -> WorkoutKit:
	if _shared == null:
		_shared = load_from(PATH)
	return _shared


## Reads and validates a kit file; every problem is a push_error.
static func load_from(path: String) -> WorkoutKit:
	var kit := WorkoutKit.new()
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	if not parsed is Dictionary:
		push_error("WorkoutKit: cannot read %s" % path)
		return kit
	kit._take(parsed)
	for problem in problems(parsed):
		push_error("WorkoutKit: %s" % problem)
	return kit


## What is wrong with a parsed kit: missing keys, and paths that do not resolve. Files are checked
## with ResourceLoader, since an exported build has only the remap.
static func problems(d: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in REQUIRED:
		if not d.has(key):
			out.append("missing key %s" % key)
	if not out.is_empty():
		return out
	for key in RIDER_KEYS:
		if not (d["rider"] as Dictionary).has(key):
			out.append("missing key rider.%s" % key)
	for key in PROP_NAMES:
		if not (d["props"] as Dictionary).has(key):
			out.append("missing key props.%s" % key)
	var names: Array = []
	for p: Dictionary in d["planes"]:
		names.append(p.get("name", ""))
	for key in PLANE_NAMES:
		if not names.has(key):
			out.append("missing plane %s" % key)
	if (d["tod"] as Array).size() != int(d["lut"].get("rows", 0)):
		out.append("tod has %d rows, the LUT %d" % [d["tod"].size(), d["lut"].get("rows", 0)])
	_check_paths(d, out)
	return out


static func _check_paths(node: Variant, out: Array[String]) -> void:
	if node is Dictionary:
		for v: Variant in (node as Dictionary).values():
			_check_paths(v, out)
	elif node is Array:
		for v: Variant in node:
			_check_paths(v, out)
	elif node is String:
		var s := node as String
		if s.begins_with("res://") and not ResourceLoader.exists(s):
			out.append("missing file %s" % s)


func _take(d: Dictionary) -> void:
	data = d
	rider = d.get("rider", {})
	road = d.get("road", {})
	props = d.get("props", {})
	tod = d.get("tod", [])


func texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D
	return _textures[path]


## The kit's plane called `plane_name` ({} if none).
func plane(plane_name: String) -> Dictionary:
	for p: Dictionary in data.get("planes", []):
		if str(p.get("name", "")) == plane_name:
			return p
	return {}


## A colour of time-of-day row `row` (sky_top, rider_tint, bank, bank_hi).
func tod_color(row: int, key: String) -> Color:
	var c: Array = tod[clampi(row, 0, tod.size() - 1)][key]
	return Color(float(c[0]), float(c[1]), float(c[2]))


func tod_row(row: int) -> Dictionary:
	return tod[clampi(row, 0, tod.size() - 1)]


## An [x, y] pair of the kit as a Vector2i.
static func vec(pair: Variant) -> Vector2i:
	var a: Array = pair
	return Vector2i(int(a[0]), int(a[1]))
