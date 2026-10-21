extends GutTest
## RoomCode (BRIEF 5.2): six Crockford Base32 characters, displayed as K7Q-X2M; input is
## case-insensitive, ignores dashes and spaces, maps O to 0 and I or L to 1.


func test_normalize_case_dashes_and_spaces() -> void:
	assert_eq(RoomCode.normalize("K7QX2M"), "K7QX2M")
	assert_eq(RoomCode.normalize("k7q-x2m"), "K7QX2M")
	assert_eq(RoomCode.normalize(" k7q x2m "), "K7QX2M")
	assert_eq(RoomCode.normalize("K-7-Q-X-2-M"), "K7QX2M")
	assert_eq(RoomCode.normalize("k7q\tx2m"), "K7QX2M")


func test_normalize_maps_lookalikes() -> void:
	assert_eq(RoomCode.normalize("OOOOOO"), "000000")
	assert_eq(RoomCode.normalize("oIlL0a"), "0111" + "0A")
	assert_eq(RoomCode.normalize("ILO-ilo"), "110110")


func test_normalize_rejects_invalid_characters() -> void:
	assert_eq(RoomCode.normalize("K7QX2U"), "", "U is not in the Crockford alphabet")
	assert_eq(RoomCode.normalize("K7QX2!"), "")
	assert_eq(RoomCode.normalize("K7Q_X2M"), "")
	assert_eq(RoomCode.normalize("K7QX2Ä"), "")


func test_normalize_rejects_wrong_lengths() -> void:
	assert_eq(RoomCode.normalize(""), "")
	assert_eq(RoomCode.normalize("---"), "")
	assert_eq(RoomCode.normalize("K7QX2"), "")
	assert_eq(RoomCode.normalize("K7QX2MM"), "")
	assert_eq(RoomCode.normalize("K7Q-X2M-1"), "")


func test_is_valid() -> void:
	assert_true(RoomCode.is_valid("k7q-x2m"))
	assert_false(RoomCode.is_valid("k7q-x2"))
	assert_false(RoomCode.is_valid("UUUUUU"))


func test_format() -> void:
	assert_eq(RoomCode.format("K7QX2M"), "K7Q-X2M")
	assert_eq(RoomCode.format("k7qx2m"), "K7Q-X2M")
	assert_eq(RoomCode.format("k7q x2m"), "K7Q-X2M")
	assert_eq(RoomCode.format("K7Q-X2M"), "K7Q-X2M")
	assert_eq(RoomCode.format("io1lo0"), "101-100")
	assert_eq(RoomCode.format("nope"), "nope", "invalid input comes back unchanged")


func test_random_codes_are_valid() -> void:
	var rng := SeededRng.make(1234)
	for i in 200:
		var code := RoomCode.random(rng)
		assert_eq(code.length(), NetMessages.CODE_LENGTH)
		assert_eq(RoomCode.normalize(code), code, code)
		for ch in code:
			assert_true(NetMessages.CODE_ALPHABET.contains(ch))


func test_random_codes_are_deterministic_by_seed() -> void:
	var a := SeededRng.make(77)
	var b := SeededRng.make(77)
	var c := SeededRng.make(78)
	var seq_a: Array[String] = []
	var seq_b: Array[String] = []
	var seq_c: Array[String] = []
	for i in 10:
		seq_a.append(RoomCode.random(a))
		seq_b.append(RoomCode.random(b))
		seq_c.append(RoomCode.random(c))
	assert_eq(seq_a, seq_b)
	assert_ne(seq_a, seq_c)


func test_alphabet() -> void:
	assert_eq(NetMessages.CODE_ALPHABET, "0123456789ABCDEFGHJKMNPQRSTVWXYZ")
	assert_eq(NetMessages.CODE_ALPHABET.length(), 32)
	assert_eq(NetMessages.CODE_LENGTH, 6)
	for ch in "ILOU":
		assert_false(NetMessages.CODE_ALPHABET.contains(ch), ch)
