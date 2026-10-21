extends GutTest
## FitCrc: the FIT SDK's CRC-16 (BRIEF 3.8, 7.1) against known vectors and an independent
## bit-by-bit reference (CRC-16/ARC, reflected polynomial 0xA001, initial 0).


## Bitwise reference implementation, independent of FitCrc's nibble table.
static func _reference(bytes: PackedByteArray) -> int:
	var crc := 0
	for b in bytes:
		crc ^= b
		for i in 8:
			if crc & 1:
				crc = (crc >> 1) ^ 0xA001
			else:
				crc >>= 1
	return crc & 0xFFFF


func test_check_value() -> void:
	# The CRC catalogue's check value for CRC-16/ARC (the FIT CRC) over "123456789".
	assert_eq(FitCrc.compute("123456789".to_ascii_buffer()), 0xBB3D)


func test_known_vectors() -> void:
	assert_eq(FitCrc.compute(PackedByteArray()), 0x0000, "empty")
	assert_eq(FitCrc.compute(PackedByteArray([0x00])), 0x0000, "one zero byte")
	assert_eq(FitCrc.compute("A".to_ascii_buffer()), 0x30C0, "A")
	assert_eq(
		FitCrc.compute(PackedByteArray([0xFF, 0xFF])), _reference(PackedByteArray([0xFF, 0xFF]))
	)


func test_matches_bitwise_reference_on_seeded_data() -> void:
	var rng := SeededRng.make(42)
	for n in [1, 2, 3, 13, 64, 257, 1000]:
		var data := PackedByteArray()
		for i in n:
			data.append(rng.randi_range(0, 255))
		assert_eq(FitCrc.compute(data), _reference(data), "length %d" % n)


func test_incremental_equals_whole() -> void:
	var data := "Wattlands FIT CRC".to_utf8_buffer()
	var crc := 0
	for b in data:
		crc = FitCrc.update(crc, b)
	assert_eq(crc, FitCrc.compute(data))
	var split := FitCrc.compute(data, 7, -1, FitCrc.compute(data, 0, 7))
	assert_eq(split, FitCrc.compute(data), "continuing from a partial CRC")


func test_crc_appended_little_endian_gives_zero() -> void:
	# A property of reflected CRCs: data followed by its CRC (little endian) has CRC 0.
	var data := "123456789".to_ascii_buffer()
	var crc := FitCrc.compute(data)
	data.append(crc & 0xFF)
	data.append(crc >> 8)
	assert_eq(FitCrc.compute(data), 0)


func test_file_is_valid_detects_corruption() -> void:
	var enc := FitEncoder.new()
	enc.file_id(1_800_000_000, 7)
	var bytes := enc.finish()
	assert_true(FitCrc.file_is_valid(bytes))
	var body := bytes.duplicate()
	body[20] ^= 0x01
	assert_false(FitCrc.file_is_valid(body), "a flipped data bit breaks the file CRC")
	var head := bytes.duplicate()
	head[2] ^= 0x01
	assert_false(FitCrc.file_is_valid(head), "a flipped header bit breaks the header CRC")
	assert_false(FitCrc.file_is_valid(bytes.slice(0, 10)), "truncated")
