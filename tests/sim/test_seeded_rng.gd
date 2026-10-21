extends GutTest
## SeededRng (BRIEF 3.6 determinism): seeded generators, stable derived seeds, weighted
## choice and shuffles that depend only on the seed.


func _draws(rng: RandomNumberGenerator, n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(rng.randi())
	return out


func test_same_seed_same_sequence() -> void:
	assert_eq(_draws(SeededRng.make(42), 50), _draws(SeededRng.make(42), 50))


func test_different_seed_different_sequence() -> void:
	assert_ne(_draws(SeededRng.make(42), 50), _draws(SeededRng.make(43), 50))


func test_derive_is_stable() -> void:
	assert_eq(SeededRng.derive(7, "mock:slot2"), SeededRng.derive(7, "mock:slot2"))
	# Golden value: the low 63 bits of the first 8 bytes (big-endian) of sha256("7|mock:slot2").
	# Pinned so derived seeds (and every seeded report) stay the same across versions.
	assert_eq(SeededRng.derive(7, "mock:slot2"), 7030618490390505409)


func test_derive_depends_on_salt_and_seed() -> void:
	var base := SeededRng.derive(7, "mock:slot2")
	assert_ne(base, SeededRng.derive(7, "mock:slot3"))
	assert_ne(base, SeededRng.derive(8, "mock:slot2"))
	assert_ne(SeededRng.derive(0, "a"), SeededRng.derive(0, "b"))


func test_derive_is_non_negative() -> void:
	for i in 64:
		assert_true(SeededRng.derive(i, "salt%d" % i) >= 0)
	assert_true(SeededRng.derive(-5, "neg") >= 0)


func test_derived_generators_are_independent_of_call_order() -> void:
	var a1 := SeededRng.make(SeededRng.derive(99, "a"))
	var b1 := SeededRng.make(SeededRng.derive(99, "b"))
	var first_a := _draws(a1, 10)
	var first_b := _draws(b1, 10)
	var b2 := SeededRng.make(SeededRng.derive(99, "b"))
	var a2 := SeededRng.make(SeededRng.derive(99, "a"))
	assert_eq(_draws(b2, 10), first_b)
	assert_eq(_draws(a2, 10), first_a)


func test_range_helpers_stay_in_bounds() -> void:
	var rng := SeededRng.make(5)
	var seen_lo := false
	var seen_hi := false
	for i in 2000:
		var f := SeededRng.range_f(rng, 0.9, 1.1)
		assert_true(f >= 0.9 and f <= 1.1)
		var n := SeededRng.range_i(rng, 3, 5)
		assert_true(n >= 3 and n <= 5)
		seen_lo = seen_lo or n == 3
		seen_hi = seen_hi or n == 5
	assert_true(seen_lo and seen_hi, "range_i includes both ends")


func test_chance_extremes() -> void:
	var rng := SeededRng.make(11)
	for i in 100:
		assert_false(SeededRng.chance(rng, 0.0))
		assert_true(SeededRng.chance(rng, 1.0))


func test_pick() -> void:
	var rng := SeededRng.make(3)
	assert_null(SeededRng.pick(rng, []))
	assert_eq(SeededRng.pick(rng, ["only"]), "only")
	var items := ["a", "b", "c"]
	for i in 50:
		assert_has(items, SeededRng.pick(rng, items))


func test_weighted_index_edge_cases() -> void:
	var rng := SeededRng.make(1)
	assert_eq(SeededRng.weighted_index(rng, []), -1)
	assert_eq(SeededRng.weighted_index(rng, [0, 0, 0]), -1)
	assert_eq(SeededRng.weighted_index(rng, [-1.0, -2.0]), -1, "negative weights count as 0")
	for i in 200:
		assert_eq(SeededRng.weighted_index(rng, [0, 0, 5]), 2)
		assert_eq(SeededRng.weighted_index(rng, [-3.0, 2.0, 0.0]), 1)


func test_weighted_index_follows_weights() -> void:
	var rng := SeededRng.make(2024)
	var counts := [0, 0]
	var n := 4000
	for i in n:
		counts[SeededRng.weighted_index(rng, [1.0, 3.0])] += 1
	var frac := float(counts[1]) / float(n)
	assert_between(frac, 0.71, 0.79, "weight 3 of 4")


func test_weighted_index_is_deterministic() -> void:
	var a := SeededRng.make(77)
	var b := SeededRng.make(77)
	var w := [0.5, 1.0, 2.0, 0.25]
	for i in 100:
		assert_eq(SeededRng.weighted_index(a, w), SeededRng.weighted_index(b, w))


func test_shuffle_is_a_deterministic_permutation() -> void:
	var original: Array = []
	for i in 20:
		original.append(i)
	var a := original.duplicate()
	var b := original.duplicate()
	SeededRng.shuffle(SeededRng.make(9), a)
	SeededRng.shuffle(SeededRng.make(9), b)
	assert_eq(a, b, "same seed, same order")
	assert_ne(a, original, "20 items almost surely move")
	var sorted := a.duplicate()
	sorted.sort()
	assert_eq(sorted, original, "a permutation of the input")
	var c := original.duplicate()
	SeededRng.shuffle(SeededRng.make(10), c)
	assert_ne(c, a, "another seed, another order")


func test_shuffle_small_arrays() -> void:
	var rng := SeededRng.make(1)
	var empty: Array = []
	SeededRng.shuffle(rng, empty)
	assert_eq(empty, [])
	var one := ["x"]
	SeededRng.shuffle(rng, one)
	assert_eq(one, ["x"])


func test_normal_is_deterministic() -> void:
	var a := SeededRng.make(4)
	var b := SeededRng.make(4)
	for i in 20:
		assert_eq(SeededRng.normal(a, 10.0, 2.0), SeededRng.normal(b, 10.0, 2.0))
