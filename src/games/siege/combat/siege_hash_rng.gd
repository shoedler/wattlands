class_name SiegeHashRng
extends RefCounted
## A tiny deterministic RNG for per-projectile spread (docs/games/siege.md 2.4 "Projectiles"):
## the host draws one seed per shot from ctx.rng, every arrow of a volley takes its spread from
## this generator seeded with it, and clients replaying the `shot` event get identical arcs.
## 32-bit xorshift; floats in [0, 1).

var _s: int = 1


func _init(seed_value: int = 1) -> void:
	_s = seed_value & 0xffffffff
	if _s == 0:
		_s = 0x9e3779b9


func next_u32() -> int:
	var x := _s
	x ^= (x << 13) & 0xffffffff
	x ^= x >> 17
	x ^= (x << 5) & 0xffffffff
	_s = x & 0xffffffff
	return _s


func randf01() -> float:
	return float(next_u32()) / 4294967296.0


func range_f(a: float, b: float) -> float:
	return a + (b - a) * randf01()


## A normal draw (Box-Muller), mean 0, deviation `sigma`.
func gauss(sigma: float) -> float:
	var u1 := maxf(randf01(), 1e-9)
	var u2 := randf01()
	return sqrt(-2.0 * log(u1)) * cos(TAU * u2) * sigma
