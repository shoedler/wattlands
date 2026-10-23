class_name SiegeStressScene
extends Node
## Brief 4 P1 performance check: SiegeView on a synthetic state with 150 enemies, 8 towers and
## 4 wheels, enemies walking their roads for 60 s (they wrap back to the spawn, so the count
## stays at the cap). It logs the mean and 1%-low frame times against the 16.7 ms budget, the
## draw calls and primitives from the Performance monitors against brief 3's budget (<= 250 draw
## calls, <= 400k triangles), then quits.
##
## Run it windowed (vsync is switched off so the numbers are the real cost, not the monitor):
##   tools/godot.sh --timeout=300 --path . res://tests/games/siege/perf/stress_scene.tscn \
##     -- --stress-seconds=60 [--stress-enemies=150] [--stress-size=1920x1080] \
##        [--stress-report=build/siege/stress.json]
## or capture a still of it: tools/screenshot --scene=res://tests/games/siege/perf/stress_scene.tscn
## Headless (no renderer: no draw calls, no frame times) it builds the state and the view, steps
## 30 frames, prints one "siege_stress: headless" line and quits, so the script check and CI can
## run it. The log lines start with "siege_stress:"; the last one is the verdict, and
## "SIEGE_STRESS {json}" carries the numbers.

const ENEMY_CAP := 150
const BUDGET_MS := 1000.0 / 60.0
const DRAW_CALL_BUDGET := 250
const PRIMITIVE_BUDGET := 400000
const TOWER_COUNT := SiegeIds.PAD_COUNT
## Enemy mix of the synthetic crowd (raiders, shield walls, horsemen, rams), by weight.
const MIX: Array[float] = [0.6, 0.12, 0.22, 0.06]
const HEADLESS_FRAMES := 30

## Seconds of wall time to run (--stress-seconds).
var seconds: float = 60.0
var enemy_count: int = ENEMY_CAP
## Quit the tree when done (tests turn it off).
var auto_quit: bool = true
var window_size: Vector2i = Vector2i(1920, 1080)
var report_path: String = ""
var state: SiegeState = null
var map: SiegeMap = null
var view: SiegeView = null
## Frame-to-frame wall time in ms, one per frame.
var frame_ms: PackedFloat32Array = PackedFloat32Array()
var draw_calls: PackedInt32Array = PackedInt32Array()
var primitives: PackedInt32Array = PackedInt32Array()
var verdict: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _start_us: int = 0
var _last_us: int = 0
var _shot_in: float = 0.0
var _done: bool = false
var _headless_frames: int = 0


## The synthetic state: vo2 wave 2 mid-wave with `n_enemies` live enemies spread over the three
## roads, all 8 pads built (levels 0-3), 4 riders on towers and the generator, two zones, a rush.
static func build_state(n_enemies: int = ENEMY_CAP, seed_n: int = 11) -> SiegeState:
	var content := SiegeContent.from_dicts(SiegeContent.read_files(), "vo2")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	var st := SiegeState.create(content, SiegeFixtures.slots(), Wl.FAIR_FTP, rng)
	st.phase_index = 4
	st.role = SiegeIds.ROLE_WAVE
	st.wave_no = 2
	st.phase_kind = Wl.WORK
	st.phase_elapsed_s = 40.0
	st.phase_duration_s = 120.0
	st.phase_remaining_s = 80.0
	st.gate_hp = 80.0
	st.gate_max = 125.0
	st.iron_bands = 1
	st.gen_level = 2
	st.team_w = 1000.0
	var types: Array[int] = [
		SiegeIds.TOWER_BALLISTA, SiegeIds.TOWER_SCORPION, SiegeIds.TOWER_CALTROP
	]
	for n in range(1, TOWER_COUNT + 1):
		var tw := st.pad(n)
		tw.type = types[(n - 1) % 3]
		tw.level = (n - 1) % (SiegeIds.MAX_TOWER_LEVEL + 1)
		tw.m = 0.6 + 0.2 * (n % 4)
		tw.cd_s = 0.3
	var targets: Array[int] = [3, 4, SiegeIds.TARGET_GEN, 6]
	for i in st.riders.size():
		var r := st.riders[i]
		r.target = targets[i]
		r.p_eff_w = 220.0 + 25.0 * i
		r.raw_w = r.p_eff_w * 0.85
		r.cadence_rpm = 88.0 + 4.0 * i
		r.denarii = 40.0 + 11.0 * i
	st.rider_at(0).od_state = SiegeIds.OD_ACTIVE
	st.rider_at(0).od_s = 20.0
	var map_ref := content.map
	var crowd := _crowd(n_enemies, content, map_ref, rng)
	st.enemies.assign(crowd)
	st.next_enemy_id = n_enemies + 1
	for road in SiegeIds.ROAD_COUNT:
		var z := SiegeZoneState.new()
		z.road = road
		z.prog_m = map_ref.road_length(road) * 0.5
		z.ttl_s = 3.0
		z.pos = map_ref.point_at(road, z.prog_m)
		if road < 2:
			st.zones.append(z)
	st.wave.rush_s = 12.0
	return st


static func _crowd(
	n: int, content: SiegeContent, map_ref: SiegeMap, rng: RandomNumberGenerator
) -> Array[SiegeEnemyState]:
	var out: Array[SiegeEnemyState] = []
	for i in n:
		var e := SiegeEnemyState.new()
		e.id = i + 1
		var pick := rng.randf()
		var type := SiegeIds.ENEMY_RAIDERS
		var acc := 0.0
		for k in MIX.size():
			acc += MIX[k]
			if pick <= acc:
				type = k + 1
				break
		e.type = type
		e.road = i % SiegeIds.ROAD_COUNT
		e.prog_m = rng.randf_range(0.0, map_ref.road_length(e.road) - 3.0)
		e.lat_m = rng.randf_range(-1.5, 1.5)
		e.max_hp = float(content.enemy_def(type).get("hp", 20.0))
		e.hp = e.max_hp * rng.randf_range(0.35, 1.0)
		e.place(map_ref)
		out.append(e)
	return out


## Tops the crowd back up to `n` live enemies (new ids), e.g. after a rules step killed some.
static func refill(st: SiegeState, n: int, rng: RandomNumberGenerator) -> void:
	var missing := n - st.enemies.size()
	if missing <= 0:
		return
	for e in _crowd(missing, st.content, st.content.map, rng):
		e.id = st.next_enemy_id
		st.next_enemy_id += 1
		st.enemies.append(e)


## Moves the crowd along its roads by `dt` seconds (enemies that reach the gate go back to the
## spawn, so the count stays), shuffles rider power, and fires a shot every 0.4 s.
static func advance(st: SiegeState, dt: float, rng: RandomNumberGenerator) -> void:
	var map_ref := st.content.map
	for e in st.enemies:
		var speed := float(st.content.enemy_def(e.type).get("speed_mps", 2.0))
		e.prog_m += speed * dt * 2.0
		if e.prog_m >= map_ref.road_length(e.road) - 2.0:
			e.prog_m = rng.randf_range(0.0, 6.0)
			e.hp = e.max_hp
		e.place(map_ref)
	st.tick += 1
	st.t += dt
	st.phase_elapsed_s += dt
	for r in st.riders:
		r.p_eff_w = 240.0 + 60.0 * sin(st.t * 0.7 + float(r.slot))
		r.raw_w = r.p_eff_w * 0.85
		r.cadence_rpm = 90.0 + 8.0 * sin(st.t * 1.3 + float(r.slot))
	for s in st.shots:
		s.age_s += dt
	st.shots.assign(st.shots.filter(func(s: SiegeShot) -> bool: return s.age_s < 0.1))


## One shot from a random built pad at two random enemies (visual only).
static func add_shot(st: SiegeState, rng: RandomNumberGenerator) -> void:
	var s := SiegeShot.new()
	s.pad = rng.randi_range(1, TOWER_COUNT)
	for _k in 2:
		s.targets.append(st.enemies[rng.randi_range(0, st.enemies.size() - 1)].id)
	st.shots.append(s)


## The mean of the slowest `frac` of `values` (the "1% low" at 0.01).
static func low_mean(values: PackedFloat32Array, frac: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := Array(values)
	sorted.sort()
	var take := maxi(1, ceili(sorted.size() * frac))
	var sum := 0.0
	for i in take:
		sum += float(sorted[sorted.size() - 1 - i])
	return sum / take


## {mean_ms, low1_ms, p99_ms, max_ms, fps, frames} of `values`.
static func frame_stats(values: PackedFloat32Array) -> Dictionary:
	if values.is_empty():
		return {
			"mean_ms": 0.0, "low1_ms": 0.0, "p99_ms": 0.0, "max_ms": 0.0, "fps": 0.0, "frames": 0
		}
	var sum := 0.0
	var mx := 0.0
	for v in values:
		sum += v
		mx = maxf(mx, v)
	var sorted := Array(values)
	sorted.sort()
	var mean_ms := sum / values.size()
	return {
		"mean_ms": mean_ms,
		"low1_ms": low_mean(values, 0.01),
		"p99_ms": float(sorted[mini(int(sorted.size() * 0.99), sorted.size() - 1)]),
		"max_ms": mx,
		"fps": 1000.0 / maxf(mean_ms, 0.001),
		"frames": values.size(),
	}


func _ready() -> void:
	_read_args()
	_rng.seed = 17
	state = build_state(enemy_count)
	map = state.content.map
	view = SiegeView.new()
	view.auto_process = false
	view.bind(state, map)
	add_child(view)
	if DisplayServer.get_name() == "headless":
		set_process(true)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_window().size = window_size
	_start_us = Time.get_ticks_usec()
	print(
		(
			"siege_stress: %d enemies, %d towers, %d wheels, %.0f s, %dx%d, vsync off"
			% [
				state.enemies.size(),
				state.built_pads().size(),
				state.riders.size(),
				seconds,
				window_size.x,
				window_size.y
			]
		)
	)


func _read_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stress-seconds="):
			seconds = float(a.get_slice("=", 1))
		elif a.begins_with("--stress-enemies="):
			enemy_count = clampi(int(a.get_slice("=", 1)), 0, ENEMY_CAP)
		elif a.begins_with("--stress-size="):
			var wh := a.get_slice("=", 1).split("x")
			if wh.size() == 2:
				window_size = Vector2i(int(wh[0]), int(wh[1]))
		elif a.begins_with("--stress-report="):
			report_path = a.get_slice("=", 1)


func _process(delta: float) -> void:
	if _done or state == null:
		return
	var dt := minf(delta, 0.1)
	_shot_in -= dt
	if _shot_in <= 0.0 and not state.enemies.is_empty():
		_shot_in = 0.4
		add_shot(state, _rng)
	advance(state, dt, _rng)
	view.refresh(dt)
	if DisplayServer.get_name() == "headless":
		_headless_frames += 1
		if _headless_frames >= HEADLESS_FRAMES:
			_finish_headless()
		return
	var now := Time.get_ticks_usec()
	if _last_us != 0:
		frame_ms.append((now - _last_us) / 1000.0)
		draw_calls.append(
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		)
		primitives.append(
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		)
	_last_us = now
	if (now - _start_us) / 1000000.0 >= seconds:
		_finish()


func _finish_headless() -> void:
	_done = true
	verdict = {
		"headless": true, "enemies": state.enemies.size(), "towers": state.built_pads().size()
	}
	print(
		(
			(
				"siege_stress: headless: %d enemies, %d towers, %d wheels, %d frames stepped; "
				+ "frame times and draw calls need a window (skipped)"
			)
			% [
				state.enemies.size(),
				state.built_pads().size(),
				state.riders.size(),
				_headless_frames
			]
		)
	)
	if auto_quit:
		get_tree().quit()


func _finish() -> void:
	_done = true
	var fs := frame_stats(frame_ms)
	var dc_max := 0
	var dc_sum := 0
	var pr_max := 0
	var pr_sum := 0
	for i in draw_calls.size():
		dc_max = maxi(dc_max, draw_calls[i])
		dc_sum += draw_calls[i]
		pr_max = maxi(pr_max, primitives[i])
		pr_sum += primitives[i]
	var n := maxi(draw_calls.size(), 1)
	verdict = {
		"headless": false,
		"frames": fs["frames"],
		"mean_ms": fs["mean_ms"],
		"low1_ms": fs["low1_ms"],
		"p99_ms": fs["p99_ms"],
		"max_ms": fs["max_ms"],
		"fps": fs["fps"],
		"budget_ms": BUDGET_MS,
		"draw_calls_mean": dc_sum / n,
		"draw_calls_max": dc_max,
		"draw_call_budget": DRAW_CALL_BUDGET,
		"primitives_mean": pr_sum / n,
		"primitives_max": pr_max,
		"primitive_budget": PRIMITIVE_BUDGET,
		"enemies": state.enemies.size(),
		"towers": state.built_pads().size(),
		"wheels": state.riders.size(),
		"adapter": RenderingServer.get_video_adapter_name(),
	}
	verdict["mean_ok"] = fs["mean_ms"] <= BUDGET_MS
	verdict["low1_ok"] = fs["low1_ms"] <= BUDGET_MS
	verdict["draw_calls_ok"] = dc_max <= DRAW_CALL_BUDGET
	verdict["primitives_ok"] = pr_max <= PRIMITIVE_BUDGET
	print(
		(
			"siege_stress: %d frames, mean %.2f ms (%.0f fps) vs %.1f ms: %s"
			% [
				fs["frames"],
				fs["mean_ms"],
				fs["fps"],
				BUDGET_MS,
				"OK" if verdict["mean_ok"] else "OVER"
			]
		)
	)
	print(
		(
			"siege_stress: 1%% low %.2f ms (p99 %.2f ms, max %.2f ms) vs %.1f ms: %s"
			% [
				fs["low1_ms"],
				fs["p99_ms"],
				fs["max_ms"],
				BUDGET_MS,
				"OK" if verdict["low1_ok"] else "OVER"
			]
		)
	)
	print(
		(
			"siege_stress: draw calls mean %d max %d (budget %d: %s), primitives mean %d max %d (budget %d: %s)"
			% [
				verdict["draw_calls_mean"],
				dc_max,
				DRAW_CALL_BUDGET,
				"OK" if verdict["draw_calls_ok"] else "OVER",
				verdict["primitives_mean"],
				pr_max,
				PRIMITIVE_BUDGET,
				"OK" if verdict["primitives_ok"] else "OVER"
			]
		)
	)
	var all_ok: bool = verdict["mean_ok"] and verdict["low1_ok"] and verdict["draw_calls_ok"]
	print("siege_stress: %s on %s" % ["PASS" if all_ok else "OVER BUDGET", verdict["adapter"]])
	print("SIEGE_STRESS " + JSON.stringify(verdict))
	if report_path != "":
		var f := FileAccess.open(report_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(verdict, "\t"))
	if auto_quit:
		get_tree().quit()
