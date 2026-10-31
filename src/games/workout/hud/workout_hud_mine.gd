class_name WorkoutHudMine
extends WorkoutHudCtl
## "My numbers", the bottom-left plate (222 x 94 art px): the trainer's mode, the heart rate and the
## in-band lamp; the watts as a key number coloured by state with the %FTP and a gauge against the
## band; the cadence as a key number over its gauge with a crank icon that turns 1:1 with the rider's
## legs; one instruction line in large type; W' and the virtual gear. The watts are a 3 s mean through
## HudRiderNumbers (GAME_SDK 10.4), never the latest 1 Hz sample. Always raw W and %FTP (shows_power).

const W := 222
const H := 94
const ARROW_UP := ["..#..", ".###.", "#####"]
const ARROW_DOWN := ["#####", ".###.", "..#.."]
const HEART_ROWS: Array[String] = [".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."]
const HEART := Color("#d0635a")
const HR_RIGHT := 202.0

var numbers: HudRiderNumbers = HudRiderNumbers.new()


func set_telemetry(t: Telemetry) -> void:
	super.set_telemetry(t)
	numbers.feed(t)


func refresh() -> void:
	var r := rider()
	if r == null:
		m = {}
		return
	var hud := hud_layer()
	var published := hud.power_band_of(r.peer_id) if hud != null else Vector2.ZERO
	var cadence_band := hud.cadence_band_of(r.peer_id) if hud != null else Vector2.ZERO
	var weight := HudRiderNumbers.opted_in_weight_kg(hud.wkg_weight_kg if hud != null else -1.0)
	var i := WorkoutHudModel.phase_index(st(), r)
	var band := WorkoutHudModel.power_band(st(), i, r, tm, published)
	numbers.ftp_w = r.ftp
	numbers.set_band(band.x, band.y)
	m = WorkoutHudModel.mine(game, numbers, tm, cadence_band, weight)


func paint() -> void:
	if m.is_empty():
		return
	D.plate(self, Rect2(0, 0, W, H))
	_header()
	_watts()
	_cadence()
	D.rect(self, Rect2(4, 56, W - 8, 1), D.FRAME_IN)
	var line := str(m["line"])
	if line != "":
		var col := D.AMBER
		if bool(m["urgent"]):
			col = D.OVER if int(floorf(st().plan_t * 4.0)) % 2 == 0 else D.AMBER
		D.text(self, 6, 60, line, col, 2)
	_reserve_and_gear()


func _header() -> void:
	D.tall(self, 6, 4, str(m["mode"]), D.AMBER)
	var hs := int(m["hr_state"])
	if hs != HudRiderNumbers.HR_NONE:
		var bpm := str(m["hr"])
		var w := D.tall_r(
			self, HR_RIGHT, 4, bpm, D.TEXT if hs == HudRiderNumbers.HR_LIVE else D.DIM
		)
		D.pixels(self, HEART_ROWS, Vector2(HR_RIGHT - w - 10.0, 5), HEART)
	D.lamp(self, Vector2(W - 11, 6), bool(m["in_band"]), D.GOOD)
	D.rect(self, Rect2(4, 16, W - 8, 1), D.FRAME_IN)


func _watts() -> void:
	var state := int(m["band_state"])
	var col := D.NUM
	if state == HudRiderNumbers.UNDER:
		col = D.UNDER
	elif state == HudRiderNumbers.OVER:
		col = D.OVER
	var bw := D.big(self, 6, 19, str(m["watts"]), col)
	if state != HudRiderNumbers.IN_BAND:
		var arrow := ARROW_UP if state == HudRiderNumbers.UNDER else ARROW_DOWN
		D.pixels(self, arrow, Vector2(6 + bw + 3, 22), col)
	var wkg := str(m["wkg"])
	var ftp := tx("WORKOUT_HUD_FTP")
	if wkg != "":
		D.tall_r(self, 106, 20, "%s %s" % [m["pct"], ftp], D.DIM)
		var wkg_w := D.tall_r(self, 106, 32, wkg, D.DIM)
		if 6.0 + bw + 8.0 < 106.0 - wkg_w:
			D.tall(self, 6 + bw + 3, 32, tx("WORKOUT_HUD_W"), D.DIM)
	else:
		D.tall_r(self, 106, 20, str(m["pct"]), D.DIM)
		D.tall_r(self, 106, 32, ftp, D.DIM)
		D.tall(self, 6 + bw + 3, 32, tx("WORKOUT_HUD_W"), D.DIM)
	D.gauge(
		self,
		Rect2(6, 47, 101, 5),
		float(m["gauge_lo"]),
		float(m["gauge_hi"]),
		float(m["gauge_v"]),
		col,
		4
	)
	D.rect(self, Rect2(111, 19, 1, 34), D.FRAME_IN)


func _cadence() -> void:
	var dim := bool(m["cadence_dim"])
	var col := D.DIM if dim else D.NUM
	var cw := D.big(self, 117, 19, str(m["cadence"]), col)
	D.tall(self, 117 + cw + 3, 32, tx("WORKOUT_HUD_RPM"), D.DIM)
	D.crank(self, int(m["crank_frame"]), Vector2(W - 6 - D.CRANK_CELL, 20), col)
	D.gauge(
		self,
		Rect2(117, 47, W - 6 - 117, 5),
		float(m["cadence_lo"]),
		float(m["cadence_hi"]),
		float(m["cadence_v"]),
		D.DIM if dim else (D.NUM if bool(m["cadence_in"]) else D.UNDER),
		4
	)


func _reserve_and_gear() -> void:
	D.rect(self, Rect2(4, 76, W - 8, 1), D.FRAME_IN)
	var lw := D.tall(self, 6, 80, tx("WORKOUT_HUD_WPRIME"), D.DIM)
	var wb := float(m["wbal"])
	var low := bool(m["wbal_low"])
	var bx := roundf(6.0 + lw + 4.0)
	D.bar(self, Rect2(bx, 82, 62.0 - bx, 5), maxf(wb, 0.0), D.OVER if low else D.AMBER)
	var pct := str(m["wbal_pct"])
	if low:
		pct = "%s %s" % [tx("WORKOUT_HUD_LOW"), pct]
	D.tall_r(self, 106, 80, pct, D.OVER if low else D.DIM)
	var lit := bool(m["gear_lit"])
	D.tall(self, 117, 80, tx("WORKOUT_HUD_GEAR"), D.DIM)
	D.tall_r(self, 158, 80, str(m["gear"]), D.TEXT if lit else D.DIM)
	var gr := Rect2(163, 82, W - 6 - 163, 5)
	D.bar(self, gr, float(m["gear_f"]), D.AMBER)
	var i := 4
	while i < WorkoutHudModel.GEAR_MAX:
		var gx := gr.position.x + roundf(gr.size.x * i / float(WorkoutHudModel.GEAR_MAX))
		D.rect(self, Rect2(gx, gr.position.y, 1, gr.size.y), D.PANEL)
		i += 4
