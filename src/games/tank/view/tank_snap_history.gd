class_name TankSnapHistory
extends SnapHistory
## What moves between snapshots, keyed by the host's game time (snapshot tick x Wl.SIM_DT): the
## hull's x (the camera), the boss's range, every enemy's x, every shell's position and every rider's
## watts and cadence. TankView pushes one entry per snapshot a client applies (TankGame.
## snapshot_applied) and one per sim tick it sees on the host or SOLO, then draws the world at
## TankRenderClock.render_t, a little behind the newest entry (brief 2.6: 100 ms interpolation).
## The view only reads this; times come from ticks, never from a clock. Like WorkoutSnapHistory.

## Rows, oldest first: {"t", "tick", "hull": float, "br": the boss's range_m, "e": {id: x},
## "er": {id: range_m}, "s": {id: Vector2}, "sl": {id: left_s},
## "r": {peer: Vector2(raw_w, cadence_rpm)}}.


## The newest entry's tick (-1 when empty).
func newest_tick() -> int:
	return int(entries.back()["tick"]) if not entries.is_empty() else -1


## Records `state` at host tick `tick`.
func push(tick: int, state: TankState) -> void:
	var t := float(tick) * Wl.SIM_DT
	var enemies := {}
	var ranges := {}
	for e in state.enemies:
		enemies[e.id] = e.x_px
		ranges[e.id] = e.range_m
	var shells := {}
	var lefts := {}
	for s in state.shells:
		shells[s.id] = Vector2(s.x, s.y)
		lefts[s.id] = s.left_s
	var riders := {}
	for r in state.riders:
		riders[r.peer] = Vector2(r.raw_w, r.cadence_rpm)
	add(
		t,
		{
			"tick": tick,
			"hull": state.hull.x_px,
			"br": state.boss.range_m,
			"e": enemies,
			"er": ranges,
			"s": shells,
			"sl": lefts,
			"r": riders
		}
	)


func hull_x_at(t: float, fallback: float) -> float:
	return float(sample(t, "hull", null, fallback))


func enemy_x_at(id: int, t: float, fallback: float) -> float:
	return float(sample(t, "e", id, fallback))


## v4: a far enemy's range (m) at host time `t`.
func enemy_range_at(id: int, t: float, fallback: float) -> float:
	return float(sample(t, "er", id, fallback))


## v4: the Behemoth's range (m) at host time `t`.
func boss_range_at(t: float, fallback: float) -> float:
	return float(sample(t, "br", null, fallback))


## v4: a far shell's seconds until it lands at host time `t`.
func shell_left_at(id: int, t: float, fallback: float) -> float:
	return float(sample(t, "sl", id, fallback))


func shell_at(id: int, t: float, fallback: Vector2) -> Vector2:
	return sample(t, "s", id, fallback) as Vector2


## (raw watts, cadence rpm) of `peer` at host time `t`.
func rider_at(peer: int, t: float, fallback: Vector2) -> Vector2:
	return sample(t, "r", peer, fallback) as Vector2
