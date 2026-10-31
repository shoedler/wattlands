class_name FishingRandom
extends RefCounted
## A small deterministic random stream (xorshift32 over a 32-bit mixed seed; G0 contract).
## Fishing needs independent streams: the pre-roll is "from ctx.seed and the slot index" (brief
## 2.3), and one rider's bites must never shift another rider's pull schedule, so every lane gets
## its own stream derived from ctx.seed. It reads no clock and no global RNG, so a client derives
## the same stream as the host. Only integer shifts, xors and products below 2^63 are used, so it
## is exact on every platform.
##
##   var r := FishingRandom.derive(ctx.seed, slot_index, FishingRandom.STREAM_PREROLL)
##   var w := r.unit()

const STREAM_PREROLL := 1  ## FishingPreroll's per-slot stream
const STREAM_LANE := 2  ## the lane's rules stream (spots, bites, strikes)
const STREAM_PULL := 3  ## the lane's pull scheduler stream

const _M := 0xFFFFFFFF

## The 32-bit state; never 0. Saved in snapshots of the rules state only for debugging.
var state: int = 0x6D2B79F5


## A stream from `seed` and two integers (slot index, stream id).
static func derive(seed: int, a: int, b: int) -> FishingRandom:
	var r := FishingRandom.new()
	var h := mix32(seed & _M)
	h = mix32(h ^ ((seed >> 32) & _M))
	h = mix32(h ^ ((a & 0xFFFF) * 0x9E37 + 0x7F4A))
	h = mix32(h ^ ((b & 0xFFFF) * 0x85EB + 0x2C1B))
	r.state = h if h != 0 else 0x6D2B79F5
	return r


## A 32-bit integer hash (two multiply-xorshift rounds).
static func mix32(x: int) -> int:
	x &= _M
	x ^= x >> 16
	x = (x * 0x45D9F3B) & _M
	x ^= x >> 16
	x = (x * 0x45D9F3B) & _M
	x ^= x >> 16
	return x


## The next 32-bit value, 1..2^32-1.
func next_u32() -> int:
	var x := state
	x ^= (x << 13) & _M
	x ^= x >> 17
	x ^= (x << 5) & _M
	state = x
	return x


## Uniform in [0, 1).
func unit() -> float:
	return float(next_u32() - 1) / 4294967295.0


## Uniform in [lo, hi].
func range_f(lo: float, hi: float) -> float:
	return lo + (hi - lo) * unit()


## Uniform integer in [lo, hi] (inclusive).
func range_i(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + mini(int(unit() * float(hi - lo + 1)), hi - lo)


## An index into `weights` (non-negative numbers) drawn by weight; -1 when every weight is 0.
func pick_weighted(weights: Array) -> int:
	var total := 0.0
	for w: Variant in weights:
		total += maxf(float(w), 0.0)
	if total <= 0.0:
		return -1
	var x := unit() * total
	for i in weights.size():
		x -= maxf(float(weights[i]), 0.0)
		if x < 0.0:
			return i
	return weights.size() - 1
