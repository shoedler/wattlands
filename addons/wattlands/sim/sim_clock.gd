class_name SimClock
extends RefCounted
## The platform's fixed-step clock (BRIEF 3.6, 6): everything advances in 0.05 s steps.
## Two times run side by side: platform time (always runs: trainer I/O, governor, mock
## riders, telemetry) and game time (stops while the session is paused, BRIEF 4.1).
## --sim-speed=x runs x steps per 0.05 s of wall time; it never touches Engine.time_scale.
## Headless simulations call step() in a loop instead of advance().

const DT := Wl.SIM_DT
## Upper bound of steps advance() returns for one wall-clock frame (avoids a spiral).
const MAX_STEPS_PER_FRAME := 4000

var sim_speed: float = 1.0
var platform_tick: int = 0
var game_tick: int = 0
var game_paused: bool = false
var _acc: float = 0.0


static func create(p_sim_speed: float = 1.0) -> SimClock:
	var c := SimClock.new()
	c.sim_speed = maxf(p_sim_speed, 0.0)
	return c


## Feed wall-clock seconds; returns how many fixed steps are now due (call step() that
## many times).
func advance(wall_delta_s: float) -> int:
	_acc += maxf(wall_delta_s, 0.0) * sim_speed
	var n := int(floor(_acc / DT + 1e-9))
	if n > MAX_STEPS_PER_FRAME:
		n = MAX_STEPS_PER_FRAME
		_acc = 0.0
	else:
		_acc -= n * DT
	return n


## One fixed step: platform time always advances, game time unless paused.
func step() -> void:
	platform_tick += 1
	if not game_paused:
		game_tick += 1


func platform_time() -> float:
	return platform_tick * DT


func game_time() -> float:
	return game_tick * DT


func set_game_paused(paused: bool) -> void:
	game_paused = paused


func reset() -> void:
	platform_tick = 0
	game_tick = 0
	game_paused = false
	_acc = 0.0
