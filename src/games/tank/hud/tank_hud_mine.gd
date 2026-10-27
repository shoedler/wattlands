class_name TankHudMine
extends TankHudCtl
## "My numbers", the bottom-left plate (222 x 94 art px; brief 3.6): the station (engine icon,
## name and job, the in-band lamp), the watts as a key number coloured by state (warm paper in
## band, desaturated blue under with an up arrow, orange-red over with a down arrow) with the %FTP
## and a power gauge against the band (shaded, a 1 px needle), the cadence as a key number over its
## band gauge, ONE instruction line in large type (TankHudModel.instruction: HOLD 152-210 W, SPIN
## 60+ RPM, SURGE 240+ W 0:04, LATCH, RESERVE), and W' and the virtual gear as small bars (the
## gear lit in SIM). The local rider's numbers come from their own telemetry (set_telemetry), the
## bands from the HudLayer (power_band_of, cadence_band_of) and the plan. The spec sets
## shows_power: this plate always shows raw W and %FTP.

const W := 222
const H := 94
const CAD_LO := 30.0
const CAD_HI := 150.0
const WPRIME_J := 20000.0
const GEAR_MAX := 24
const ARROW_UP := ["..#..", ".###.", "#####"]
const ARROW_DOWN := ["#####", ".###.", "..#.."]

var m: Dictionary = {}


## The local rider's numbers: their telemetry when the HUD sends one, else the rider state.
func numbers(r: TankRiderState) -> Dictionary:
	var n := {
		"w": r.raw_w,
		"cad": r.cadence_rpm,
		"pct": r.ftp_pct,
		"wbal": WPRIME_J,
		"gear": 12,
		"mode": TankHudModel.plan_mode(st(), r.engine),
		"target": _plan_target_w(r),
	}
	if tm != null:
		n["w"] = tm.power_w
		n["cad"] = tm.cadence_rpm
		n["pct"] = tm.ftp_pct if tm.ftp_pct > 0.0 else 100.0 * tm.power_w / maxf(r.ftp, 1.0)
		n["wbal"] = tm.wbal_j
		n["gear"] = tm.gear
		if tm.mode == Wl.ERG or tm.mode == Wl.SIM:
			n["mode"] = tm.mode
		n["target"] = float(tm.applied_target_w) if tm.mode == Wl.ERG else 0.0
	return n


## The ERG target in W when no telemetry says it (the rider's target_pct from the host, else the
## dynamo's bank target or the plan entry's target_pct); 0 in SIM.
func _plan_target_w(r: TankRiderState) -> float:
	var s := st()
	if TankHudModel.plan_mode(s, r.engine) != Wl.ERG:
		return 0.0
	if r.target_pct > 0.0:
		return r.target_pct / 100.0 * r.ftp
	if r.engine == TankIds.ENGINE_DYNAMO:
		var d := s.station(TankIds.ENGINE_DYNAMO) as TankDynamoState
		if d != null:
			return TankHudModel.bank_target_pct(s, d.bank) / 100.0 * r.ftp
	if s.content != null:
		var e := s.content.plan_entry(r.engine, s.seg.seg)
		return float(e.get("target_pct", 0.0)) / 100.0 * r.ftp
	return 0.0


func refresh() -> void:
	var r := local_rider()
	if r == null or r.engine == "":
		m = {}
		return
	var n := numbers(r)
	var published := Vector2.ZERO
	var cb := Vector2.ZERO
	var hl := hud_layer()
	if hl != null:
		published = hl.power_band_of(r.peer)
		cb = hl.cadence_band_of(r.peer)
	var band := TankHudModel.band_w(st(), r, str(n["mode"]), float(n["target"]), published)
	var line := TankHudModel.instruction(
		st(), r, {"mode": n["mode"], "cad": n["cad"], "band": band, "cband": cb}
	)
	var w := float(n["w"])
	var state := 0
	if not r.in_band:
		state = 1 if band.y > 0.0 and w > band.y else -1
	var text := ""
	if str(line["key"]) != "":
		text = tx(str(line["key"]), line["args"])
		if float(line["left_s"]) > 0.0:
			text += "  " + D.clock(float(line["left_s"]))
	m = {
		"engine": r.engine,
		"w": w,
		"pct": float(n["pct"]),
		"cad": float(n["cad"]),
		"band": band,
		"cband": cb if cb.y > 0.0 else Vector2(TankHudModel.DEFAULT_RPM, 120.0),
		"in_band": r.in_band,
		"state": state,
		"kind": str(line["kind"]),
		"line": text,
		"urgent": bool(line["urgent"]),
		"wbal": clampf(float(n["wbal"]) / WPRIME_J, 0.0, 1.0),
		"gear": int(n["gear"]),
		"sim": str(n["mode"]) == Wl.SIM,
	}


func paint() -> void:
	if m.is_empty():
		return
	D.plate(self, Rect2(0, 0, W, H))
	var eng := str(m["engine"])
	_header(eng)
	_watts()
	_cadence()
	D.rect(self, Rect2(4, 56, W - 8, 1), D.FRAME_IN)
	var line := str(m["line"])
	if line != "":
		var col := D.AMBER
		if bool(m["urgent"]):
			col = D.OVER if int(floorf(st().t * 4.0)) % 2 == 0 else D.AMBER
		elif str(m["kind"]) == TankHudModel.DO_RESERVE:
			col = D.DIM
		D.text(self, 6, 60, line, col, 2)
	_reserve_and_gear()


func _header(eng: String) -> void:
	D.icon(self, eng, Vector2(6, 5), D.AMBER)
	var name_key := "TANK_HUD_ENG_" + eng.to_upper()
	var x := 16.0 + D.tall(self, 16, 4, tx(name_key).to_upper(), D.AMBER)
	var job := D.fit_tall(tx("TANK_HUD_JOB_" + eng.to_upper()), W - 20.0 - x - 5.0)
	D.tall(self, x + 5, 4, job, D.DIM)
	D.lamp(self, Vector2(W - 11, 6), bool(m["in_band"]), D.GOOD)
	D.rect(self, Rect2(4, 16, W - 8, 1), D.FRAME_IN)


## The watts coloured by state, the arrow toward the band, the %FTP and the gauge.
func _watts() -> void:
	var w := float(m["w"])
	var band: Vector2 = m["band"]
	var state := int(m["state"])
	var col := D.NUM
	if state < 0:
		col = D.UNDER
	elif state > 0:
		col = D.OVER
	var bw := D.big(self, 6, 19, str(roundi(w)), col)
	if state != 0:
		D.pixels(self, ARROW_UP if state < 0 else ARROW_DOWN, Vector2(6 + bw + 3, 22), col)
	D.tall(self, 6 + bw + 3, 32, tx("TANK_HUD_W"), D.DIM)
	D.tall_r(self, 106, 20, "%d%%" % roundi(float(m["pct"])), D.DIM)
	D.tall_r(self, 106, 32, tx("TANK_HUD_FTP"), D.DIM)
	var hi := band.y if band.y > 0.0 else band.x * 1.15
	var top := maxf(hi * 1.5, maxf(w * 1.05, 100.0))
	var lo_f := band.x / top
	var hi_f := (band.y if band.y > 0.0 else top) / top
	D.gauge(self, Rect2(6, 47, 101, 5), lo_f, hi_f, w / top, col, 4)
	D.rect(self, Rect2(111, 19, 1, 34), D.FRAME_IN)


func _cadence() -> void:
	var cad := float(m["cad"])
	var cb: Vector2 = m["cband"]
	var cw := D.big(self, 117, 19, str(roundi(cad)), D.NUM)
	D.tall(self, 117 + cw + 3, 32, tx("TANK_HUD_RPM"), D.DIM)
	var in_c := cad >= cb.x and cad <= cb.y
	D.gauge(
		self,
		Rect2(117, 47, W - 6 - 117, 5),
		inverse_lerp(CAD_LO, CAD_HI, cb.x),
		inverse_lerp(CAD_LO, CAD_HI, cb.y),
		inverse_lerp(CAD_LO, CAD_HI, cad),
		D.NUM if in_c else D.UNDER,
		4
	)


func _reserve_and_gear() -> void:
	D.rect(self, Rect2(4, 76, W - 8, 1), D.FRAME_IN)
	D.tall(self, 6, 80, tx("TANK_HUD_WPRIME"), D.DIM)
	var wb := float(m["wbal"])
	D.bar(self, Rect2(30, 82, 76, 5), wb, D.BRASS if wb > 0.25 else D.OVER)
	var sim := bool(m["sim"])
	D.tall(self, 117, 80, tx("TANK_HUD_GEAR"), D.DIM)
	var g := int(m["gear"])
	D.tall_r(self, 158, 80, str(g) if sim else "-", D.TEXT if sim else D.DIM)
	var gr := Rect2(163, 82, W - 6 - 163, 5)
	D.rect(self, gr, D.TRACK)
	if sim:
		var gw := roundf(gr.size.x * clampf(float(g) / GEAR_MAX, 0.0, 1.0))
		D.rect(self, Rect2(gr.position, Vector2(gw, gr.size.y)), D.BRASS)
	var i := 4
	while i < GEAR_MAX:
		var gx := gr.position.x + roundf(gr.size.x * i / float(GEAR_MAX))
		D.rect(self, Rect2(gx, gr.position.y, 1, gr.size.y), D.PANEL)
		i += 4
