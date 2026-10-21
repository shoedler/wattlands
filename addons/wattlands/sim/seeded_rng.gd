class_name SeededRng
extends RefCounted
## Seeded randomness helpers (BRIEF 3.6 determinism). Games use ctx.rng (a
## RandomNumberGenerator seeded by the platform); everything else that needs randomness
## (MockTrainer jitter, bots, cosmetic view noise) derives its own seeded generator here.
## Never use global randi()/randf() or an unseeded RandomNumberGenerator in rules.


## A RandomNumberGenerator with a fixed seed.
static func make(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


## A stable sub-seed for `salt` (e.g. "mock:slot2"), independent of call order.
static func derive(seed: int, salt: String) -> int:
	var h := ("%d|%s" % [seed, salt]).sha256_buffer()
	var v := 0
	for i in 8:
		v = (v << 8) | h[i]
	return v & 0x7FFFFFFFFFFFFFFF


static func range_f(rng: RandomNumberGenerator, lo: float, hi: float) -> float:
	return lo + (hi - lo) * rng.randf()


static func range_i(rng: RandomNumberGenerator, lo: int, hi_inclusive: int) -> int:
	return rng.randi_range(lo, hi_inclusive)


static func chance(rng: RandomNumberGenerator, p: float) -> bool:
	return rng.randf() < p


static func pick(rng: RandomNumberGenerator, items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[rng.randi_range(0, items.size() - 1)]


## Index chosen with probability proportional to `weights` (non-negative). -1 if all zero.
static func weighted_index(rng: RandomNumberGenerator, weights: Array) -> int:
	var total := 0.0
	for w: Variant in weights:
		total += maxf(float(w), 0.0)
	if total <= 0.0:
		return -1
	var x := rng.randf() * total
	for i in weights.size():
		x -= maxf(float(weights[i]), 0.0)
		if x < 0.0:
			return i
	return weights.size() - 1


## Fisher-Yates shuffle in place, deterministic for a given rng state.
static func shuffle(rng: RandomNumberGenerator, items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp


## Gaussian sample (Box-Muller via RandomNumberGenerator.randfn).
static func normal(rng: RandomNumberGenerator, mean: float, sd: float) -> float:
	return rng.randfn(mean, sd)
