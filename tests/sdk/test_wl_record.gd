extends GutTest
## WlRecord, the plain-data base of every game's state types: what it saves, how it casts JSON back.


class Rec:
	extends WlRecord
	var flag: bool = false
	var count: int = 0
	var ratio: float = 0.0
	var label: String = ""
	var at: Vector2 = Vector2.ZERO
	var spot: Vector3 = Vector3.ZERO
	var ints: Array[int] = []
	var floats: Array[float] = []
	var words: Array[String] = []
	var bools: Array[bool] = []
	var loose: Array = []
	var _hidden: int = 7
	var nested: RefCounted = null
	var nested_list: Array[RefCounted] = []
	var unsaved_dict: Dictionary = {}


func _round_trip(r: Rec) -> Dictionary:
	return JSON.parse_string(JSON.stringify(r.to_dict()))


func test_to_dict_writes_every_saved_kind() -> void:
	var r := Rec.new()
	r.flag = true
	r.count = 3
	r.ratio = 0.5
	r.label = "x"
	r.ints = [1, 2]
	var d := r.to_dict()
	assert_eq(d["flag"], true)
	assert_eq(d["count"], 3)
	assert_eq(d["ratio"], 0.5)
	assert_eq(d["label"], "x")
	assert_eq(d["ints"], [1, 2])


func test_vectors_are_written_as_arrays() -> void:
	var r := Rec.new()
	r.at = Vector2(1.5, 2.5)
	r.spot = Vector3(1.0, 2.0, 3.0)
	var d := r.to_dict()
	assert_eq(d["at"], [1.5, 2.5])
	assert_eq(d["spot"], [1.0, 2.0, 3.0])


func test_underscore_object_and_dictionary_variables_are_skipped() -> void:
	var r := Rec.new()
	r.nested = RefCounted.new()
	r.nested_list = [RefCounted.new()]
	var d := r.to_dict()
	for skipped: String in ["_hidden", "nested", "nested_list", "unsaved_dict"]:
		assert_false(d.has(skipped), "%s is not saved" % skipped)


func test_load_dict_ignores_the_skipped_variables() -> void:
	var r := Rec.new()
	r.load_dict({"_hidden": 9, "nested_list": [1], "unsaved_dict": {"a": 1}})
	assert_eq(r._hidden, 7)
	assert_eq(r.nested_list.size(), 0)
	assert_true(r.unsaved_dict.is_empty())


func test_to_dict_copies_arrays() -> void:
	var r := Rec.new()
	r.ints = [1]
	var d := r.to_dict()
	(d["ints"] as Array).append(2)
	assert_eq(r.ints.size(), 1, "the record's own array is untouched")


func test_a_json_round_trip_gives_the_same_record() -> void:
	var r := Rec.new()
	r.flag = true
	r.count = 3
	r.ratio = 0.25
	r.label = "x"
	r.at = Vector2(1.5, 2.5)
	r.spot = Vector3(1.0, 2.0, 3.0)
	r.ints = [4, 5]
	r.floats = [0.5]
	r.words = ["a"]
	r.bools = [true]
	var back := Rec.new()
	back.load_dict(_round_trip(r))
	assert_eq(back.to_dict(), r.to_dict())


func test_load_dict_casts_json_numbers_to_the_variable_type() -> void:
	var r := Rec.new()
	r.load_dict({"count": 3.0, "ratio": 2, "flag": 1, "label": 5})
	assert_typeof(r.count, TYPE_INT)
	assert_eq(r.count, 3)
	assert_typeof(r.ratio, TYPE_FLOAT)
	assert_eq(r.ratio, 2.0)
	assert_eq(r.flag, true)
	assert_eq(r.label, "5")


func test_load_dict_casts_typed_array_elements() -> void:
	var r := Rec.new()
	(
		r
		. load_dict(
			{
				"ints": [1.0, 2.0],
				"floats": [1],
				"words": [7],
				"bools": [1, 0],
				"loose": ["a", 1],
			}
		)
	)
	assert_eq(r.ints, [1, 2])
	assert_typeof(r.floats[0], TYPE_FLOAT)
	assert_eq(r.words, ["7"])
	assert_eq(r.bools, [true, false])
	assert_eq(r.loose, ["a", 1])


func test_missing_keys_keep_their_value() -> void:
	var r := Rec.new()
	r.count = 3
	r.ints = [1]
	r.load_dict({"label": "x"})
	assert_eq(r.count, 3)
	assert_eq(r.ints.size(), 1)
	assert_eq(r.label, "x")


func test_load_dict_replaces_an_array_rather_than_adding_to_it() -> void:
	var r := Rec.new()
	r.ints = [1, 2, 3]
	r.load_dict({"ints": [9]})
	assert_eq(r.ints, [9])


func test_junk_in_place_of_a_vector_or_array_gives_zero_or_empty() -> void:
	var r := Rec.new()
	r.at = Vector2.ONE
	r.spot = Vector3.ONE
	r.ints = [1]
	r.load_dict({"at": "junk", "spot": "junk", "ints": "junk"})
	assert_eq(r.at, Vector2.ZERO)
	assert_eq(r.spot, Vector3.ZERO)
	assert_eq(r.ints.size(), 0)


func test_a_short_array_gives_a_zero_vector3() -> void:
	var r := Rec.new()
	r.spot = Vector3.ONE
	r.load_dict({"spot": [1.0, 2.0]})
	assert_eq(r.spot, Vector3.ZERO)


func test_load_dict_returns_the_record() -> void:
	var r := Rec.new()
	assert_same(r.load_dict({}), r)
