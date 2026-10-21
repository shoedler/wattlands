extends GutTest
## QaFitDecoder (tools/fit_decode, BRIEF 3.8 fallback decoder): header and CRC checks, definition
## and data messages, compressed timestamps, big endian, developer fields, chained files and the
## Wattlands activity checks, on files built with qa's own QaFitWriter.

const START := 1_100_000_000


func _activity(opts: Dictionary = {}) -> Dictionary:
	return QaFitDecoder.decode_bytes(QaFitWriter.activity(opts), "test.fit", opts)


func test_crc16_matches_the_fit_sdk_check_value() -> void:
	# The FIT CRC is CRC-16/ARC: "123456789" -> 0xBB3D.
	assert_eq(QaFitDecoder.crc16("123456789".to_ascii_buffer()), 0xBB3D)
	assert_eq(QaFitDecoder.crc16(PackedByteArray()), 0)


func test_crc16_of_a_file_with_its_crc_is_zero() -> void:
	var bytes := QaFitWriter.activity()
	assert_eq(
		QaFitDecoder.crc16(bytes), 0, "a CRC-16/ARC over data plus its little-endian CRC is 0"
	)


func test_fit_epoch() -> void:
	assert_eq(QaFitDecoder.fit_to_unix(0), 631065600)
	assert_eq(QaFitDecoder.fit_to_unix(1), 631065601)


func test_valid_activity_decodes_without_errors() -> void:
	var s := _activity()
	assert_eq(s["errors"], [], "errors")
	assert_true(s["ok"])
	assert_true(s["crc_ok"])
	assert_eq(s["segments"], 1)
	assert_eq(int(s["records"]), 120)
	assert_eq(float(s["record_span_s"]), 119.0)
	assert_eq(int(s["record_gaps"]), 0)
	assert_eq(int(s["first_record_ts"]), START)
	assert_eq((s["file_id"] as Dictionary)["type"], 4)
	assert_eq((s["file_id"] as Dictionary)["manufacturer"], 255)
	assert_eq(int(s["device_infos"]), 1)
	assert_eq(int(s["timer_starts"]), 1)
	assert_eq(int(s["timer_stops"]), 1)
	assert_eq((s["messages"] as Dictionary)["record"], 120)


func test_header_fields() -> void:
	var s := _activity()
	var h: Dictionary = s["header"]
	assert_eq(h["size"], 14)
	assert_eq(h["protocol_version"], 0x20)
	assert_eq(h["profile_version"], 2132)
	assert_eq(h["data_type"], ".FIT")
	assert_true(h["header_crc_ok"])


func test_laps_have_start_and_duration() -> void:
	var s := _activity({"laps": [30, 60, 30]})
	var laps: Array = s["laps"]
	assert_eq(laps.size(), 3)
	assert_eq(float(laps[0]["start_s"]), 0.0)
	assert_eq(float(laps[0]["duration_s"]), 30.0)
	assert_eq(float(laps[1]["start_s"]), 30.0)
	assert_eq(float(laps[1]["duration_s"]), 60.0)
	assert_eq(float(laps[2]["start_s"]), 90.0)
	assert_eq(float(laps[2]["duration_s"]), 30.0)
	assert_almost_eq(float(laps[1]["work_kj"]), 9.0, 0.0001)
	assert_eq(float(laps[1]["avg_power_w"]), 150.0)
	assert_eq(float(laps[1]["avg_cadence_rpm"]), 90.0)


func test_session_totals() -> void:
	var s := _activity(
		{"records": 300, "laps": [300], "power": 200, "cadence": 85, "speed_mps": 9.0}
	)
	var ses: Dictionary = s["session"]
	assert_eq(ses["sport"], 2)
	assert_eq(ses["sub_sport"], 58)
	assert_eq(float(ses["elapsed_s"]), 300.0)
	assert_eq(float(ses["timer_s"]), 300.0)
	assert_almost_eq(float(ses["distance_m"]), 2700.0, 0.01)
	assert_almost_eq(float(ses["work_kj"]), 60.0, 0.0001)
	assert_eq(float(ses["avg_power_w"]), 200.0)
	assert_eq(float(ses["max_power_w"]), 200.0)
	assert_eq(float(ses["avg_cadence_rpm"]), 85.0)
	assert_eq(int(ses["num_laps"]), 1)
	assert_eq(int(s["sessions"]), 1)
	assert_eq((s["activity"] as Dictionary)["num_sessions"], 1)


func test_header_crc_zero_means_not_computed() -> void:
	var s := QaFitDecoder.decode_bytes(
		QaFitWriter.activity_writer().to_bytes({"header_crc": false})
	)
	assert_eq(s["errors"], [])
	assert_eq((s["header"] as Dictionary)["header_crc"], 0)


func test_twelve_byte_header() -> void:
	var s := QaFitDecoder.decode_bytes(QaFitWriter.activity_writer().to_bytes({"header_size": 12}))
	assert_eq(s["errors"], [])
	assert_eq((s["header"] as Dictionary)["size"], 12)


func test_bad_header_crc_is_an_error() -> void:
	var s := QaFitDecoder.decode_bytes(
		QaFitWriter.activity_writer().to_bytes({"bad_header_crc": true})
	)
	assert_false(s["ok"])
	assert_false(s["crc_ok"])
	assert_string_contains(str(s["errors"]), "header CRC mismatch")


func test_bad_file_crc_is_an_error() -> void:
	var s := QaFitDecoder.decode_bytes(
		QaFitWriter.activity_writer().to_bytes({"bad_file_crc": true})
	)
	assert_false(s["ok"])
	assert_false(s["crc_ok"])
	assert_string_contains(str(s["errors"]), "file CRC mismatch")
	assert_eq(int(s["records"]), 120, "the data is still decoded")


func test_flipped_data_byte_breaks_the_crc() -> void:
	var bytes := QaFitWriter.activity()
	var i := bytes.size() - 40
	bytes[i] = bytes[i] ^ 0x01
	var s := QaFitDecoder.decode_bytes(bytes)
	assert_false(s["ok"])
	assert_string_contains(str(s["errors"]), "file CRC mismatch")


func test_missing_signature_is_an_error() -> void:
	var s := QaFitDecoder.decode_bytes(
		QaFitWriter.activity_writer().to_bytes({"signature": ".FOO"})
	)
	assert_false(s["ok"])
	assert_string_contains(str(s["errors"]), ".FIT")


func test_bad_header_size_is_an_error() -> void:
	var bytes := QaFitWriter.activity()
	bytes[0] = 13
	var s := QaFitDecoder.decode_bytes(bytes)
	assert_false(s["ok"])
	assert_string_contains(str(s["errors"]), "bad header size 13")


func test_truncated_file_is_an_error() -> void:
	var bytes := QaFitWriter.activity()
	bytes = bytes.slice(0, bytes.size() - 50)
	var s := QaFitDecoder.decode_bytes(bytes)
	assert_false(s["ok"])
	assert_string_contains(str(s["errors"]), "runs past the end of the file")


func test_empty_and_tiny_files_are_errors() -> void:
	var empty := QaFitDecoder.decode_bytes(PackedByteArray())
	assert_false(empty["ok"])
	assert_string_contains(str(empty["errors"]), "empty file")
	var tiny := QaFitDecoder.decode_bytes(PackedByteArray([14, 0x20, 0, 0]))
	assert_false(tiny["ok"])
	assert_string_contains(str(tiny["errors"]), "too short")


func test_data_message_for_an_undefined_local_type() -> void:
	var w := QaFitWriter.new()
	w.define(0, QaFitDecoder.MESG_FILE_ID, [[0, 1, QaFitWriter.ENUM]])
	w.data(0, [4])
	w.raw(PackedByteArray([0x05, 1, 2, 3]))
	var s := QaFitDecoder.decode_bytes(w.to_bytes())
	assert_false(s["ok"])
	assert_string_contains(str(s["errors"]), "undefined local type 5")


func test_truncated_data_message() -> void:
	var w := QaFitWriter.new()
	w.define(
		0, QaFitDecoder.MESG_RECORD, [[253, 4, QaFitWriter.UINT32], [7, 2, QaFitWriter.UINT16]]
	)
	w.raw(PackedByteArray([0x00, 1, 2, 3]))
	var s := QaFitDecoder.decode_bytes(w.to_bytes())
	assert_false(s["ok"])
	assert_string_contains(str(s["errors"]), "truncated data message")


func test_big_endian_definitions() -> void:
	var w := QaFitWriter.new()
	w.define(
		0, QaFitDecoder.MESG_FILE_ID, [[0, 1, QaFitWriter.ENUM], [1, 2, QaFitWriter.UINT16]], true
	)
	w.data(0, [4, 255])
	w.define(
		1,
		QaFitDecoder.MESG_RECORD,
		[[253, 4, QaFitWriter.UINT32], [7, 2, QaFitWriter.UINT16], [4, 1, QaFitWriter.UINT8]],
		true
	)
	for i in 3:
		w.data(1, [START + i, 0x0102 + i, 90])
	_append_tail(w, 3, true)
	var s := QaFitDecoder.decode_bytes(w.to_bytes())
	assert_eq(s["errors"], [])
	assert_eq((s["file_id"] as Dictionary)["manufacturer"], 255)
	assert_eq(int(s["records"]), 3)
	assert_eq(int(s["first_record_ts"]), START)
	assert_eq(int(s["last_record_ts"]), START + 2)


func test_compressed_timestamps() -> void:
	var w := QaFitWriter.new()
	w.define(0, QaFitDecoder.MESG_FILE_ID, [[0, 1, QaFitWriter.ENUM]])
	w.data(0, [4])
	w.define(
		1, QaFitDecoder.MESG_RECORD, [[253, 4, QaFitWriter.UINT32], [7, 2, QaFitWriter.UINT16]]
	)
	var base := START + 30  # START is a multiple of 32, so the low 5 bits are 30
	w.data(1, [base, 100])
	w.define(2, QaFitDecoder.MESG_RECORD, [[7, 2, QaFitWriter.UINT16]])
	# Offsets wrap around the 32-second window: +1, +2, then a rollover.
	var low := base & 0x1F
	w.compressed(2, (low + 1) & 0x1F, [101])
	w.compressed(2, (low + 2) & 0x1F, [102])
	w.compressed(2, (low + 3) & 0x1F, [103])
	_append_tail(w, 4, false, base)
	var s := QaFitDecoder.decode_bytes(w.to_bytes())
	assert_eq(s["errors"], [])
	assert_eq(int(s["records"]), 4)
	assert_eq(int(s["first_record_ts"]), base)
	assert_eq(int(s["last_record_ts"]), base + 3, "compressed offsets roll over correctly")
	assert_eq(int(s["record_gaps"]), 0)


func test_compressed_timestamp_rollover_past_32_seconds() -> void:
	var w := QaFitWriter.new()
	w.define(0, QaFitDecoder.MESG_FILE_ID, [[0, 1, QaFitWriter.ENUM]])
	w.data(0, [4])
	var base := (START & ~0x1F) + 31
	w.define(1, QaFitDecoder.MESG_RECORD, [[253, 4, QaFitWriter.UINT32]])
	w.data(1, [base])
	w.define(2, QaFitDecoder.MESG_RECORD, [[7, 2, QaFitWriter.UINT16]])
	w.compressed(2, 0, [50])
	_append_tail(w, 2, false, base)
	var s := QaFitDecoder.decode_bytes(w.to_bytes())
	assert_eq(s["errors"], [])
	assert_eq(int(s["last_record_ts"]), base + 1)


func test_compressed_timestamp_without_a_full_one_is_an_error() -> void:
	var w := QaFitWriter.new()
	w.define(0, QaFitDecoder.MESG_FILE_ID, [[0, 1, QaFitWriter.ENUM]])
	w.data(0, [4])
	w.define(1, QaFitDecoder.MESG_RECORD, [[7, 2, QaFitWriter.UINT16]])
	w.compressed(1, 3, [50])
	var s := QaFitDecoder.decode_bytes(w.to_bytes())
	assert_false(s["ok"])
	assert_string_contains(str(s["errors"]), "before any full timestamp")


func test_developer_fields_are_skipped() -> void:
	var w := QaFitWriter.new()
	w.define(0, QaFitDecoder.MESG_FILE_ID, [[0, 1, QaFitWriter.ENUM]])
	w.data(0, [4])
	w.define(
		1,
		QaFitDecoder.MESG_RECORD,
		[[253, 4, QaFitWriter.UINT32], [7, 2, QaFitWriter.UINT16]],
		false,
		[[0, 3, 0], [1, 2, 0]]
	)
	for i in 5:
		w.data(1, [START + i, 150], PackedByteArray([1, 2, 3, 4, 5]))
	_append_tail(w, 5, false)
	var s := QaFitDecoder.decode_bytes(w.to_bytes())
	assert_eq(s["errors"], [])
	assert_eq(int(s["records"]), 5)


func test_invalid_values_are_left_out() -> void:
	var w := QaFitWriter.new()
	w.define(0, QaFitDecoder.MESG_FILE_ID, [[0, 1, QaFitWriter.ENUM], [1, 2, QaFitWriter.UINT16]])
	w.data(0, [4, null])
	w.define(
		1, QaFitDecoder.MESG_RECORD, [[253, 4, QaFitWriter.UINT32], [7, 2, QaFitWriter.UINT16]]
	)
	w.data(1, [START, null])
	_append_tail(w, 1, false)
	var s := QaFitDecoder.decode_bytes(w.to_bytes())
	assert_eq(s["errors"], [])
	assert_eq((s["file_id"] as Dictionary)["manufacturer"], null)
	assert_eq(int(s["records"]), 1)


func test_strings_arrays_signed_and_float_fields() -> void:
	var w := QaFitWriter.new()
	w.define(0, QaFitDecoder.MESG_FILE_ID, [[0, 1, QaFitWriter.ENUM], [8, 12, QaFitWriter.STRING]])
	w.data(0, [4, "Wattlands"])
	w.define(
		1,
		300,
		[
			[0, 3, QaFitWriter.UINT8],
			[1, 2, QaFitWriter.SINT16],
			[2, 4, QaFitWriter.FLOAT32],
			[3, 4, QaFitWriter.SINT32]
		]
	)
	w.data(1, [[1, 2, 3], -5, 1.5, -100000])
	_append_tail(w, 0, false)
	var bytes := w.to_bytes()
	var s := QaFitDecoder.decode_bytes(bytes)
	assert_eq((s["messages"] as Dictionary)["mesg_300"], 1)
	# Read the raw message values through the internal reader as well.
	var v_sint16: Variant = QaFitDecoder._read_scalar(PackedByteArray([0xFB, 0xFF]), 0, 3, false)
	assert_eq(v_sint16, -5)
	var v_sint32: Variant = QaFitDecoder._read_scalar(
		PackedByteArray([0x60, 0x79, 0xFE, 0xFF]), 0, 5, false
	)
	assert_eq(v_sint32, -100000)
	var f := PackedByteArray()
	f.resize(4)
	f.encode_float(0, 1.5)
	assert_eq(QaFitDecoder._read_scalar(f, 0, 8, false), 1.5)
	assert_eq(QaFitDecoder._read_value(PackedByteArray([1, 2, 3]), 0, 3, 2, false), [1, 2, 3])
	var text := "Wattlands".to_utf8_buffer()
	text.append_array(PackedByteArray([0, 0]))
	assert_eq(QaFitDecoder._read_value(text, 0, 11, 7, false), "Wattlands")
	assert_eq(QaFitDecoder._read_value(PackedByteArray([0xFF, 0xFF]), 0, 2, 4, false), null)


func test_chained_files() -> void:
	var one := QaFitWriter.activity({"records": 10, "laps": [10]})
	var two := QaFitWriter.activity({"records": 20, "laps": [20], "start": START + 100})
	var both := one.duplicate()
	both.append_array(two)
	var s := QaFitDecoder.decode_bytes(both)
	assert_eq(s["segments"], 2)
	assert_eq(int(s["records"]), 30)
	assert_true(s["crc_ok"])
	assert_string_contains(
		str(s["errors"]), "2 session messages", "a Wattlands ride holds one session"
	)


func test_trailing_garbage_is_an_error() -> void:
	var bytes := QaFitWriter.activity()
	bytes.append_array(PackedByteArray([1, 2, 3]))
	var s := QaFitDecoder.decode_bytes(bytes)
	assert_false(s["ok"])
	assert_string_contains(str(s["errors"]), "trailing byte")


func test_wrong_sport_is_an_error() -> void:
	var s := _activity({"sport": 1, "sub_sport": 0})
	assert_false(s["ok"])
	assert_string_contains(str(s["errors"]), "session.sport is 1")
	assert_string_contains(str(s["errors"]), "session.sub_sport is 0")


func test_wrong_file_type_is_an_error() -> void:
	var s := _activity({"file_type": 6})
	assert_false(s["ok"])
	assert_string_contains(str(s["errors"]), "file_id.type is 6")


func test_missing_messages_are_errors() -> void:
	for missing: String in ["session", "activity", "lap", "file_id"]:
		var s := _activity({"skip": [missing]})
		assert_false(s["ok"], "missing %s" % missing)
	var no_records := _activity({"records": 0, "laps": [1]})
	assert_string_contains(str(no_records["errors"]), "no record messages")


func test_missing_device_info_and_timer_events_are_warnings() -> void:
	var s := _activity({"skip": ["device_info", "event"]})
	assert_true(s["ok"], str(s["errors"]))
	assert_string_contains(str(s["warnings"]), "no device_info message")
	assert_string_contains(str(s["warnings"]), "no timer start event")


func test_num_laps_mismatch_is_an_error() -> void:
	var s := _activity({"num_laps": 5})
	assert_false(s["ok"])
	assert_string_contains(str(s["errors"]), "num_laps is 5")


func test_expect_laps() -> void:
	assert_true(_activity({"laps": [60, 60], "expect_laps": 2})["ok"])
	var s := _activity({"laps": [60, 60], "expect_laps": 3})
	assert_false(s["ok"])
	assert_string_contains(str(s["errors"]), "expected 3 lap(s), found 2")


func test_record_gaps_and_backwards_time() -> void:
	var w := QaFitWriter.new()
	w.define(0, QaFitDecoder.MESG_FILE_ID, [[0, 1, QaFitWriter.ENUM]])
	w.data(0, [4])
	w.define(1, QaFitDecoder.MESG_RECORD, [[253, 4, QaFitWriter.UINT32]])
	for ts: int in [START, START + 1, START + 5, START + 6]:
		w.data(1, [ts])
	_append_tail(w, 4, false)
	var s := QaFitDecoder.decode_bytes(w.to_bytes())
	assert_eq(s["errors"], [])
	assert_eq(int(s["record_gaps"]), 1)
	var w2 := QaFitWriter.new()
	w2.define(0, QaFitDecoder.MESG_FILE_ID, [[0, 1, QaFitWriter.ENUM]])
	w2.data(0, [4])
	w2.define(1, QaFitDecoder.MESG_RECORD, [[253, 4, QaFitWriter.UINT32]])
	for ts: int in [START, START + 2, START + 1]:
		w2.data(1, [ts])
	_append_tail(w2, 3, false)
	var s2 := QaFitDecoder.decode_bytes(w2.to_bytes())
	assert_string_contains(str(s2["errors"]), "go backwards")


func test_decode_file_reports_a_missing_file() -> void:
	var s := QaFitDecoder.decode_file("C:/definitely/not/here.fit")
	assert_false(s["ok"])
	assert_string_contains(str(s["errors"]), "no such file")


func test_errors_are_capped() -> void:
	var s := {"errors": [], "warnings": []}
	for i in 200:
		QaFitDecoder._err(s, "e%d" % i)
	assert_eq((s["errors"] as Array).size(), QaFitDecoder.MAX_ERRORS + 1)


## A lap, a cycling session and an activity after hand-built records, so only the part under
## test can fail.
func _append_tail(w: QaFitWriter, records: int, big: bool, start: int = START) -> void:
	w.define(
		10,
		QaFitDecoder.MESG_LAP,
		[[253, 4, QaFitWriter.UINT32], [2, 4, QaFitWriter.UINT32], [7, 4, QaFitWriter.UINT32]],
		big
	)
	w.data(10, [start + records, start, records * 1000])
	w.define(
		11,
		QaFitDecoder.MESG_SESSION,
		[
			[253, 4, QaFitWriter.UINT32],
			[2, 4, QaFitWriter.UINT32],
			[5, 1, QaFitWriter.ENUM],
			[6, 1, QaFitWriter.ENUM],
			[7, 4, QaFitWriter.UINT32],
			[26, 2, QaFitWriter.UINT16]
		],
		big
	)
	w.data(11, [start + records, start, 2, 58, records * 1000, 1])
	w.define(
		12,
		QaFitDecoder.MESG_ACTIVITY,
		[[253, 4, QaFitWriter.UINT32], [1, 2, QaFitWriter.UINT16]],
		big
	)
	w.data(12, [start + records, 1])
