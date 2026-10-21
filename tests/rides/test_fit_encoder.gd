extends GutTest
## FitEncoder (BRIEF 3.8, 7.1): header layout, CRCs, message layout and field values,
## timestamps. The output is decoded with tests/rides/fit_reader.gd.

const Reader := preload("res://tests/rides/fit_reader.gd")
const START := 1_800_000_000  # 2027-01-15T08:00:00Z


func _decode(bytes: PackedByteArray) -> Dictionary:
	var d := Reader.read(bytes)
	assert_eq(d["errors"], [], "decodes without errors")
	return d


func test_fit_epoch() -> void:
	assert_eq(FitEncoder.FIT_EPOCH_UNIX, 631065600, "1989-12-31T00:00:00Z")
	assert_eq(FitEncoder.fit_time(631065600), 0)
	assert_eq(FitEncoder.fit_time(START), START - 631065600)
	assert_eq(FitEncoder.unix_time(FitEncoder.fit_time(START)), START)
	assert_eq(Time.get_unix_time_from_datetime_string("1989-12-31T00:00:00"), 631065600)


func test_header_layout() -> void:
	var enc := FitEncoder.new()
	enc.file_id(START, 99)
	var b := enc.finish()
	assert_eq(b[0], 14, "14-byte header")
	assert_eq(b[1], 0x20, "protocol 2.0")
	assert_eq(b.decode_u16(2), FitEncoder.PROFILE_VERSION)
	assert_eq(b.decode_u32(4), b.size() - 16, "data size excludes the header and file CRC")
	assert_eq(b.slice(8, 12).get_string_from_ascii(), ".FIT")
	assert_eq(b.decode_u16(12), FitCrc.compute(b, 0, 12), "header CRC over bytes 0..11")
	assert_eq(
		b.decode_u16(b.size() - 2),
		FitCrc.compute(b, 0, b.size() - 2),
		"file CRC over header and data"
	)


func test_file_id_fields() -> void:
	var enc := FitEncoder.new()
	enc.file_id(START, 0xABCDEF01)
	var d := _decode(enc.finish())
	var defs: Array = d["definitions"]
	assert_eq(defs.size(), 1)
	assert_eq(int(defs[0]["global"]), 0, "file_id")
	assert_eq(int(defs[0]["arch"]), 0, "little endian")
	var m: Dictionary = Reader.of(d, 0)[0]
	var f: Dictionary = m["fields"]
	assert_eq(f[0], 4, "type activity")
	assert_eq(f[1], 255, "manufacturer development")
	assert_eq(f[2], FitEncoder.PRODUCT_ID)
	assert_eq(f[3], 0xABCDEF01, "serial")
	assert_eq(f[4], START - 631065600, "time_created in FIT seconds")
	assert_eq(f[8], "Wattlands")


func test_serial_zero_becomes_one() -> void:
	var enc := FitEncoder.new()
	enc.file_id(START, 0)
	var f: Dictionary = (Reader.of(_decode(enc.finish()), 0)[0] as Dictionary)["fields"]
	assert_eq(f[3], 1, "uint32z: 0 is invalid")


func test_record_fields_and_scales() -> void:
	var enc := FitEncoder.new()
	enc.file_id(START, 1)
	enc.record(START + 5, 250.4, 90.6, 8.3334, 1234.567)
	enc.record(START + 6, 0.0, -1.0, -1.0, 1234.567)
	enc.record(START + 7, 70000.0, 300.0, 100.0, 0.0)
	var d := _decode(enc.finish())
	var recs := Reader.of(d, 20)
	assert_eq(recs.size(), 3)
	var f: Dictionary = recs[0]["fields"]
	assert_eq(f[253], START + 5 - 631065600, "timestamp")
	assert_eq(f[7], 250, "power W")
	assert_eq(f[4], 91, "cadence rpm")
	assert_eq(f[6], 8333, "speed m/s x 1000")
	assert_eq(f[5], 123457, "distance m x 100")
	var g: Dictionary = recs[1]["fields"]
	assert_eq(g[4], 0xFF, "absent cadence is invalid")
	assert_eq(g[6], 0xFFFF, "absent speed is invalid")
	var h: Dictionary = recs[2]["fields"]
	assert_eq(h[7], 0xFFFE, "power clamped below the invalid marker")
	assert_eq(h[4], 0xFE, "cadence clamped below the invalid marker")
	assert_false(
		d["messages"].any(
			func(m: Dictionary) -> bool: return m["fields"].has(0) and int(m["global"]) == 20
		),
		"no GPS or other fields"
	)


func test_record_definition_has_no_gps() -> void:
	var enc := FitEncoder.new()
	enc.record(START, 100.0, 80.0, 5.0, 0.0)
	var d := _decode(enc.finish())
	var nums: Array = []
	for fd: Array in d["definitions"][0]["fields"]:
		nums.append(int(fd[0]))
	assert_eq(nums, [253, 7, 4, 6, 5], "timestamp, power, cadence, speed, distance")
	assert_false(nums.has(0) or nums.has(1), "no position_lat/long")


func test_timer_events() -> void:
	var enc := FitEncoder.new()
	enc.timer_event(START, true)
	enc.timer_event(START + 60, false)
	var evs := Reader.of(_decode(enc.finish()), 21)
	assert_eq(evs.size(), 2)
	assert_eq(evs[0]["fields"][0], 0, "event timer")
	assert_eq(evs[0]["fields"][1], 0, "start")
	assert_eq(evs[1]["fields"][1], 4, "stop_all")
	assert_eq(evs[1]["fields"][253], START + 60 - 631065600)


func test_lap_fields_and_name() -> void:
	var enc := FitEncoder.new()
	(
		enc
		. lap(
			{
				"index": 2,
				"start_unix": START + 300,
				"end_unix": START + 480,
				"elapsed_s": 180.05,
				"timer_s": 170.0,
				"distance_m": 1500.25,
				"avg_speed_mps": 8.33,
				"max_speed_mps": 10.0,
				"avg_power_w": 249.6,
				"max_power_w": 300.0,
				"avg_cadence_rpm": 88.4,
				"max_cadence_rpm": 101.0,
				"work_j": 44928.0,
				"trigger": 0,
				"name": "Wave 2",
			}
		)
	)
	var d := _decode(enc.finish())
	var is_lap := func(x: Dictionary) -> bool: return int(x["global"]) == 19
	var lap_def: Dictionary = (d["definitions"] as Array).filter(is_lap)[0]
	assert_eq(lap_def["dev_fields"], [[0, 32, 0]], "one developer field: lap_name")
	var f: Dictionary = Reader.of(d, 19)[0]["fields"]
	assert_eq(f[254], 2, "message_index")
	assert_eq(f[253], START + 480 - 631065600, "timestamp = lap end")
	assert_eq(f[2], START + 300 - 631065600, "start_time")
	assert_eq(f[0], 9, "event lap")
	assert_eq(f[1], 1, "event_type stop")
	assert_eq(f[7], 180050, "total_elapsed_time ms")
	assert_eq(f[8], 170000, "total_timer_time ms")
	assert_eq(f[9], 150025, "total_distance cm")
	assert_eq(f[13], 8330)
	assert_eq(f[14], 10000)
	assert_eq(f[19], 250, "avg_power")
	assert_eq(f[20], 300, "max_power")
	assert_eq(f[17], 88, "avg_cadence")
	assert_eq(f[18], 101)
	assert_eq(f[41], 44928, "total_work J")
	assert_eq(f[24], 0, "lap_trigger manual")
	assert_eq(f[25], 2, "sport cycling")
	assert_eq(f[39], 58, "sub_sport virtual_activity")
	var name: PackedByteArray = Reader.of(d, 19)[0]["dev"][0]
	assert_eq(Reader.dev_string(name), "Wave 2")
	var ids := Reader.of(d, 207)
	assert_eq(ids.size(), 1, "developer_data_id")
	assert_eq(ids[0]["fields"][3], 0, "developer_data_index 0")
	var desc := Reader.of(d, 206)
	assert_eq(desc.size(), 1, "field_description")
	assert_eq(desc[0]["fields"][0], 0)
	assert_eq(desc[0]["fields"][1], 0)
	assert_eq(desc[0]["fields"][2], 0x07, "string")
	assert_eq(desc[0]["fields"][3], "lap_name")


func test_long_utf8_lap_name_is_cut_on_a_character_boundary() -> void:
	var enc := FitEncoder.new()
	var label := "Überholmanöver äöü " + "é".repeat(20)
	enc.lap({"name": label})
	var raw: PackedByteArray = Reader.of(_decode(enc.finish()), 19)[0]["dev"][0]
	assert_eq(raw.size(), 32)
	var text := Reader.dev_string(raw)
	assert_true(label.begins_with(text), "a prefix of the label: %s" % text)
	assert_true(text.to_utf8_buffer().size() <= 31, "room for the terminating zero")


func test_session_and_activity() -> void:
	var enc := FitEncoder.new()
	(
		enc
		. session(
			{
				"start_unix": START,
				"end_unix": START + 600,
				"elapsed_s": 600.0,
				"timer_s": 590.0,
				"distance_m": 5000.0,
				"avg_speed_mps": 8.33,
				"max_speed_mps": 12.0,
				"avg_power_w": 201.0,
				"max_power_w": 410.0,
				"avg_cadence_rpm": 90.0,
				"max_cadence_rpm": 110.0,
				"work_j": 120600.0,
				"first_lap_index": 0,
				"num_laps": 5,
			}
		)
	)
	enc.activity(START + 600, 590.0, 3600)
	var d := _decode(enc.finish())
	var s: Dictionary = Reader.of(d, 18)[0]["fields"]
	assert_eq(s[5], 2, "sport cycling")
	assert_eq(s[6], 58, "sub_sport virtual_activity")
	assert_eq(s[0], 8, "event session")
	assert_eq(s[1], 1, "stop")
	assert_eq(s[2], START - 631065600, "start_time")
	assert_eq(s[7], 600000)
	assert_eq(s[8], 590000)
	assert_eq(s[9], 500000)
	assert_eq(s[20], 201)
	assert_eq(s[21], 410)
	assert_eq(s[18], 90)
	assert_eq(s[19], 110)
	assert_eq(s[48], 120600, "total_work J")
	assert_eq(s[25], 0)
	assert_eq(s[26], 5, "num_laps")
	assert_eq(s[28], 0, "trigger activity_end")
	var a: Dictionary = Reader.of(d, 34)[0]["fields"]
	assert_eq(a[253], START + 600 - 631065600)
	assert_eq(a[0], 590000, "total_timer_time ms")
	assert_eq(a[1], 1, "one session")
	assert_eq(a[2], 0, "manual")
	assert_eq(a[3], 26, "event activity")
	assert_eq(a[4], 1, "stop")
	assert_eq(a[5], START + 600 - 631065600 + 3600, "local_timestamp")
	var enc2 := FitEncoder.new()
	enc2.activity(START, 1.0)
	assert_eq(
		Reader.of(_decode(enc2.finish()), 34)[0]["fields"][5],
		0xFFFFFFFF,
		"no offset: local_timestamp invalid"
	)


func test_each_definition_is_written_once() -> void:
	var enc := FitEncoder.new()
	for i in 10:
		enc.record(START + i, 100.0, 80.0, 5.0, float(i) * 5.0)
	var d := _decode(enc.finish())
	assert_eq((d["definitions"] as Array).size(), 1)
	assert_eq(Reader.of(d, 20).size(), 10)


func test_device_info() -> void:
	var enc := FitEncoder.new()
	enc.device_info(START, 5, 10)
	var f: Dictionary = Reader.of(_decode(enc.finish()), 23)[0]["fields"]
	assert_eq(f[253], START - 631065600)
	assert_eq(f[0], 0, "device_index creator")
	assert_eq(f[2], 255)
	assert_eq(f[4], FitEncoder.PRODUCT_ID)
	assert_eq(f[5], 10, "software_version x100")
	assert_eq(f[27], "Wattlands")


func test_encode_ride_message_order() -> void:
	var ride := {
		"utc_start_unix": START,
		"serial": 3,
		"software_version_x100": 10,
		"local_offset_s": null,
		"records":
		[
			{
				"t": START,
				"power_w": 100.0,
				"cadence_rpm": 80.0,
				"speed_mps": 5.0,
				"distance_m": 0.0
			},
			{
				"t": START + 1,
				"power_w": 110.0,
				"cadence_rpm": 81.0,
				"speed_mps": 5.0,
				"distance_m": 5.0
			},
			{
				"t": START + 2,
				"power_w": 120.0,
				"cadence_rpm": 82.0,
				"speed_mps": 5.0,
				"distance_m": 10.0
			},
		],
		"events": [{"t": START, "running": true}, {"t": START + 2, "running": false}],
		"laps":
		[
			{"index": 0, "start_unix": START, "end_unix": START + 1, "name": "A"},
			{"index": 1, "start_unix": START + 1, "end_unix": START + 2, "name": "B"},
		],
		"session": {"start_unix": START, "end_unix": START + 2, "num_laps": 2},
		"end_unix": START + 2,
		"timer_s": 2.0,
	}
	var d := _decode(FitEncoder.encode_ride(ride))
	var order: Array = []
	for m: Dictionary in d["messages"]:
		order.append(int(m["global"]))
	# file_id, developer data, device_info, timer start, record@0, lap A@1, record@1, record@2,
	# timer stop, lap B, session, activity.
	assert_eq(order, [0, 207, 206, 23, 21, 20, 19, 20, 20, 21, 19, 18, 34])
