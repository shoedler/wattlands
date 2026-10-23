extends GutTest
## HeartRateParser: the Heart Rate Measurement characteristic 0x2A37 (flags, uint8 or uint16
## bpm, sensor contact, energy expended, RR intervals ignored).


func test_uint8_heart_rate() -> void:
	var m := HeartRateParser.parse(PackedByteArray([0x00, 72]))
	assert_true(m["ok"])
	assert_eq(m["bpm"], 72)
	assert_false(m["contact_supported"])
	assert_eq(m["energy_j"], -1)


func test_uint16_heart_rate() -> void:
	# flags bit 0: 0x012C = 300 bpm, little-endian.
	var m := HeartRateParser.parse(PackedByteArray([0x01, 0x2C, 0x01]))
	assert_true(m["ok"])
	assert_eq(m["bpm"], 300)


func test_sensor_contact_bits() -> void:
	var with_contact := HeartRateParser.parse(PackedByteArray([0x06, 140]))
	assert_true(with_contact["contact_supported"])
	assert_true(with_contact["contact"])
	var without := HeartRateParser.parse(PackedByteArray([0x04, 0]))
	assert_true(without["contact_supported"])
	assert_false(without["contact"])
	var unsupported := HeartRateParser.parse(PackedByteArray([0x02, 90]))
	assert_false(unsupported["contact_supported"], "bit 1 alone means nothing")


func test_energy_and_rr_intervals() -> void:
	# uint8 bpm 151, energy 0x0102 = 258 kJ, then two RR intervals (ignored).
	var m := HeartRateParser.parse(PackedByteArray([0x18, 151, 0x02, 0x01, 0x00, 0x04, 0x10, 0x04]))
	assert_true(m["ok"])
	assert_eq(m["bpm"], 151)
	assert_eq(m["energy_j"], 258000)


func test_uint16_with_rr_only() -> void:
	var m := HeartRateParser.parse(PackedByteArray([0x11, 0x5A, 0x00, 0x20, 0x03]))
	assert_eq(m["bpm"], 90)
	assert_eq(m["energy_j"], -1)


func test_short_data_is_rejected_with_a_warning() -> void:
	assert_false(HeartRateParser.parse(PackedByteArray())["ok"])
	assert_false(HeartRateParser.parse(PackedByteArray([0x00]))["ok"])
	assert_false(HeartRateParser.parse(PackedByteArray([0x01, 0x50]))["ok"], "uint16 needs 2 bytes")
	assert_false(HeartRateParser.parse(PackedByteArray([0x08, 80, 0x01]))["ok"], "energy cut off")
