extends GutTest
## FtmsCodec (BRIEF 4.3, 7.1): every case in tests/vectors/ftms.json (encoders, parsers,
## multi-notification records, truncated packets), plus the assembler, hex helpers, encoder
## edge cases and the feature-bit constants.

const VECTORS_PATH := "res://tests/vectors/ftms.json"

var _doc: Dictionary = {}


func before_all() -> void:
	_doc = JSON.parse_string(FileAccess.get_file_as_string(VECTORS_PATH))


func _encode(op: String, args: Dictionary) -> PackedByteArray:
	match op:
		"request_control":
			return FtmsCodec.encode_request_control()
		"reset":
			return FtmsCodec.encode_reset()
		"start_resume":
			return FtmsCodec.encode_start_resume()
		"stop_pause":
			return FtmsCodec.encode_stop_pause(int(args["param"]))
		"target_power":
			return FtmsCodec.encode_target_power(int(args["watts"]))
		"target_resistance":
			return FtmsCodec.encode_target_resistance(float(args["level"]), str(args["encoding"]))
		"indoor_bike_simulation":
			return FtmsCodec.encode_indoor_bike_simulation(
				float(args["wind_mps"]),
				float(args["grade_pct"]),
				float(args["crr"]),
				float(args["cw"])
			)
		"indoor_bike_data":
			return FtmsCodec.encode_indoor_bike_data(args)
	fail_test("unknown encode op %s" % op)
	return PackedByteArray()


func _parse(kind: String, bytes: PackedByteArray) -> Dictionary:
	match kind:
		"indoor_bike_data":
			return FtmsCodec.parse_indoor_bike_data(bytes)
		"feature":
			return FtmsCodec.parse_feature(bytes)
		"power_range":
			return FtmsCodec.parse_power_range(bytes)
		"resistance_range":
			return FtmsCodec.parse_resistance_range(bytes)
		"machine_status":
			return FtmsCodec.parse_machine_status(bytes)
		"control_response":
			return FtmsCodec.parse_control_response(bytes)
		"cycling_power_measurement":
			return FtmsCodec.parse_cycling_power_measurement(bytes)
	fail_test("unknown parse kind %s" % kind)
	return {}


## Exact key set; numbers within 1e-9 (ints compare exactly through that); params as hex.
func _assert_record(got: Dictionary, expect: Dictionary, label: String) -> void:
	var got_keys := got.keys()
	var exp_keys := expect.keys()
	got_keys.sort()
	exp_keys.sort()
	assert_eq(got_keys, exp_keys, "%s: keys" % label)
	for key: Variant in expect.keys():
		if not got.has(key):
			continue
		var e: Variant = expect[key]
		var g: Variant = got[key]
		if g is PackedByteArray:
			assert_eq(FtmsCodec.to_hex(g), str(e), "%s: %s" % [label, key])
		elif e is bool:
			assert_eq(g, e, "%s: %s" % [label, key])
		else:
			assert_true(g is int or g is float, "%s: %s is a number" % [label, key])
			assert_almost_eq(float(g), float(e), 1e-9, "%s: %s" % [label, key])


# --- the vectors file -----------------------------------------------------------------


func test_vectors_file_is_documented_and_complete() -> void:
	assert_true(_doc.has("_doc"), "the format is documented in _doc")
	assert_eq(int(_doc["version"]), 1)
	var names := {}
	for section: String in ["encode", "parse", "assemble"]:
		assert_gt((_doc[section] as Array).size(), 0, section)
		for c: Dictionary in _doc[section]:
			assert_false(names.has(c["name"]), "unique case name %s" % c["name"])
			names[c["name"]] = true
	var ops := {}
	for c: Dictionary in _doc["encode"]:
		ops[c["op"]] = true
	for op: String in [
		"request_control",
		"reset",
		"start_resume",
		"stop_pause",
		"target_power",
		"target_resistance",
		"indoor_bike_simulation",
		"indoor_bike_data"
	]:
		assert_true(ops.has(op), "an encode vector for %s" % op)
	var kinds := {}
	var invalid := {}
	for c: Dictionary in _doc["parse"]:
		kinds[c["kind"]] = true
		if not bool(c["valid"]):
			invalid[c["kind"]] = true
	for kind: String in [
		"indoor_bike_data",
		"feature",
		"power_range",
		"resistance_range",
		"machine_status",
		"control_response",
		"cycling_power_measurement"
	]:
		assert_true(kinds.has(kind), "a parse vector for %s" % kind)
		assert_true(invalid.has(kind), "a malformed vector for %s" % kind)


func test_every_encode_vector() -> void:
	for c: Dictionary in _doc["encode"]:
		var got := _encode(str(c["op"]), c["args"])
		assert_eq(FtmsCodec.to_hex(got), str(c["hex"]), str(c["name"]))
	assert_push_error_count(0)


func test_every_parse_vector() -> void:
	for c: Dictionary in _doc["parse"]:
		var got := _parse(str(c["kind"]), FtmsCodec.from_hex(str(c["hex"])))
		if bool(c["valid"]):
			_assert_record(got, c["expect"], str(c["name"]))
		else:
			assert_eq(got, {}, "%s is rejected" % c["name"])
			assert_push_error("FtmsCodec: malformed", str(c["name"]))


func test_every_assemble_vector() -> void:
	for c: Dictionary in _doc["assemble"]:
		var got := FtmsCodec.assemble_indoor_bike_data(c["hex"])
		var expect: Array = c["expect"]
		assert_eq(got.size(), expect.size(), "%s: record count" % c["name"])
		for i in mini(got.size(), expect.size()):
			_assert_record(got[i], expect[i], "%s[%d]" % [c["name"], i])
		for e in int(c["errors"]):
			assert_push_error("FtmsCodec: malformed", str(c["name"]))


func test_bike_data_encoder_round_trips() -> void:
	for c: Dictionary in _doc["encode"]:
		if c["op"] != "indoor_bike_data":
			continue
		var args: Dictionary = c["args"]
		var rec := FtmsCodec.parse_indoor_bike_data(_encode("indoor_bike_data", args))
		for key: Variant in args.keys():
			assert_almost_eq(float(rec[key]), float(args[key]), 1e-9, "%s: %s" % [c["name"], key])
		assert_eq(bool(rec["more_data"]), not args.has("speed_kmh"))


# --- encoders beyond the vectors ------------------------------------------------------


func test_encoder_rejects_bad_arguments() -> void:
	assert_eq(FtmsCodec.encode_stop_pause(3), PackedByteArray())
	assert_push_error("stop/pause parameter")
	assert_eq(FtmsCodec.encode_stop_pause(0), PackedByteArray())
	assert_push_error("stop/pause parameter")
	assert_eq(FtmsCodec.encode_target_resistance(10.0, "uint16"), PackedByteArray())
	assert_push_error("unknown resistance encoding")


func test_simulation_nan_and_infinite_values_are_safe() -> void:
	assert_eq(
		FtmsCodec.to_hex(FtmsCodec.encode_indoor_bike_simulation(NAN, NAN, 0.004, 0.51)),
		"11000000002833"
	)
	assert_eq(
		FtmsCodec.to_hex(FtmsCodec.encode_indoor_bike_simulation(INF, -INF, INF, -INF)),
		"11ff7f00" + "80ff00"
	)


func test_simulation_defaults_match_brief_4_5() -> void:
	var p := FtmsCodec.encode_indoor_bike_simulation(0.0, 0.0, 0.004, 0.51)
	assert_eq(p[0], FtmsCodec.OP_SET_SIMULATION)
	assert_eq(p.size(), 7)
	assert_eq(p[5], 40, "crr 0.004 in 0.0001 units")
	assert_eq(p[6], 51, "cw 0.51 kg/m in 0.01 units")


func test_target_power_never_negative() -> void:
	for w: int in [-1, -200, -40000]:
		assert_eq(FtmsCodec.to_hex(FtmsCodec.encode_target_power(w)), "050000")


# --- assembler ------------------------------------------------------------------------


func test_assembler_streams_parts() -> void:
	var a := FtmsCodec.BikeDataAssembler.new()
	assert_false(a.has_pending())
	assert_eq(a.push(FtmsCodec.from_hex("4500b400c800")).size(), 0)
	assert_true(a.has_pending())
	var out := a.push(FtmsCodec.from_hex("0000ea0b"))
	assert_eq(out.size(), 1)
	assert_false(a.has_pending())
	assert_eq(int(out[0]["parts"]), 2)
	assert_almost_eq(float(out[0]["speed_kmh"]), 30.5, 1e-9)
	a.push(FtmsCodec.from_hex("4500b400c800"))
	a.reset()
	assert_false(a.has_pending())


func test_assembler_flushes_after_max_parts() -> void:
	var a := FtmsCodec.BikeDataAssembler.new()
	var parts: Array[Dictionary] = [
		{"avg_speed_kmh": 20.0},
		{"avg_cadence_rpm": 80.0},
		{"resistance_level": 3},
		{"avg_power_w": 150},
		{"heart_rate_bpm": 120},
		{"met": 4.5},
		{"elapsed_s": 60},
		{"remaining_s": 30},
	]
	var out: Array[Dictionary] = []
	for p in parts:
		out.append_array(a.push(FtmsCodec.encode_indoor_bike_data(p)))
	assert_eq(out.size(), 1, "flushed at MAX_PARTS")
	assert_eq(int(out[0]["parts"]), FtmsCodec.BikeDataAssembler.MAX_PARTS)
	assert_true(bool(out[0]["more_data"]))
	assert_eq(int(out[0]["remaining_s"]), 30)
	assert_false(a.has_pending())


func test_assemble_accepts_bytes_or_hex() -> void:
	var from_bytes := FtmsCodec.assemble_indoor_bike_data([FtmsCodec.from_hex("4400ea0bb400c800")])
	var from_hex := FtmsCodec.assemble_indoor_bike_data(["4400ea0bb400c800"])
	assert_eq(from_bytes, from_hex)
	assert_eq(from_hex.size(), 1)


# --- helpers and constants ------------------------------------------------------------


func test_hex_helpers() -> void:
	assert_eq(FtmsCodec.from_hex("05 C8:00"), PackedByteArray([5, 200, 0]))
	assert_eq(FtmsCodec.from_hex(""), PackedByteArray())
	assert_eq(FtmsCodec.to_hex(PackedByteArray([0, 255, 16])), "00ff10")
	assert_eq(FtmsCodec.from_hex("0g"), PackedByteArray())
	assert_push_error("bad hex")
	assert_eq(FtmsCodec.from_hex("abc"), PackedByteArray())
	assert_push_error("bad hex")
	assert_eq(FtmsCodec.from_hex("+a"), PackedByteArray())
	assert_push_error("bad hex")


func test_names() -> void:
	assert_eq(FtmsCodec.opcode_name(0x05), "Set Target Power")
	assert_eq(FtmsCodec.opcode_name(0x11), "Set Indoor Bike Simulation")
	assert_eq(FtmsCodec.opcode_name(0x42), "op 0x42")
	assert_eq(FtmsCodec.result_name(0x05), "control not permitted")
	assert_eq(FtmsCodec.result_name(0x09), "result 0x09")


func test_feature_bits_match_brief_4_3() -> void:
	assert_eq(FtmsCodec.MACHINE_CADENCE, 2)
	assert_eq(FtmsCodec.MACHINE_RESISTANCE_LEVEL, 128)
	assert_eq(FtmsCodec.MACHINE_POWER_MEASUREMENT, 16384)
	assert_eq(FtmsCodec.TARGET_RESISTANCE, 4)
	assert_eq(FtmsCodec.TARGET_POWER, 8)
	assert_eq(FtmsCodec.TARGET_SIMULATION, 8192)
	assert_eq(FtmsCodec.TARGET_WHEEL_CIRCUMFERENCE, 16384)
	assert_eq(FtmsCodec.TARGET_SPIN_DOWN, 32768)
	assert_eq(FtmsCodec.TARGET_CADENCE, 65536)
	var mock := MockTrainer.FEATURES_MACHINE
	assert_eq(
		mock,
		(
			FtmsCodec.MACHINE_CADENCE
			| FtmsCodec.MACHINE_RESISTANCE_LEVEL
			| FtmsCodec.MACHINE_POWER_MEASUREMENT
		)
	)
	assert_eq(
		MockTrainer.FEATURES_TARGET,
		FtmsCodec.TARGET_RESISTANCE | FtmsCodec.TARGET_POWER | FtmsCodec.TARGET_SIMULATION
	)
	assert_eq(MockTrainer.OP_SET_TARGET_POWER, FtmsCodec.OP_SET_TARGET_POWER)
	assert_eq(MockTrainer.OP_SET_SIMULATION, FtmsCodec.OP_SET_SIMULATION)
	assert_eq(MockTrainer.OP_SET_RESISTANCE, FtmsCodec.OP_SET_TARGET_RESISTANCE)
	assert_eq(MockTrainer.OP_STOP_PAUSE, FtmsCodec.OP_STOP_PAUSE)
