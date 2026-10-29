class_name SiegeSnapshot
extends RefCounted
## Encodes SiegeState into the 10 Hz snapshot (SiegeSnapshotSchema, brief 2.6 v2) and applies one
## on a client. Every value written is an int; apply() casts everything it reads with int(),
## nested arrays included, so a JSON round trip without int_fields still works. Projectiles never
## travel here: clients replay them from `shot` events.


## The snapshot of `state` (host, 10 Hz).
static func encode(state: SiegeState) -> Dictionary:
	var r: Array = []
	for rd in state.riders:
		(
			r
			. append(
				[
					rd.slot,
					rd.target,
					_ms(rd.reconnect_s),
					_ms(rd.od_s) if rd.od_state == SiegeIds.OD_ACTIVE else 0,
					_ms(rd.od_cd_s) if rd.od_state == SiegeIds.OD_COOLDOWN else 0,
					floori(rd.gold),
					roundi(rd.p_eff_w),
					roundi(rd.raw_w),
					roundi(rd.cadence_rpm),
					int(rd.rescue),
					int(rd.afk),
				]
			)
		)
	var st: Array = []
	var dw: Array = []
	for s in state.stations:
		(
			st
			. append(
				[
					s.id,
					s.level,
					_pm(s.wind),
					roundi(wrapf(s.yaw_deg, -180.0, 180.0) * 100.0),
					roundi(s.m * 100.0),
					_pm(s.arm),
				]
			)
		)
		if SiegeIds.is_weapon(s.id):
			dw.append([s.id, roundi(s.damage_wave)])
	var pd: Array = []
	for p in state.pads:
		if p.built():
			(
				pd
				. append(
					[
						p.pad,
						p.type,
						p.level,
						_ms(p.cd_s),
						roundi(wrapf(p.yaw_deg, -180.0, 180.0) * 100.0),
					]
				)
			)
	var e: Array = []
	for en in state.enemies:
		(
			e
			. append(
				[
					en.id,
					en.type,
					roundi(en.prog_m * 10.0),
					roundi(en.lat_m * 10.0),
					ceili(en.hp),
					en.st,
				]
			)
		)
	var tar := state.tar
	var snap := {
		"v": SiegeSnapshotSchema.VERSION,
		"tick": state.tick,
		"ph": state.phase_index,
		"pt_ms": _ms(state.phase_elapsed_s),
		"gate": [ceili(state.gate_hp), roundi(state.gate_max), _ms(state.breach_s)],
		"nb": state.breaches,
		"ib": state.iron_bands,
		"ml": state.mine_level,
		"pk": state.perks.duplicate(),
		"w": roundi(state.team_w),
		"r": r,
		"st": st,
		"pd": pd,
		"tar":
		[
			roundi(tar.cauldron_l * 10.0),
			roundi(tar.curtain_hp * 10.0),
			_pm(tar.coat),
			int(tar.boarded),
		],
		"e": e,
		"q": state.queued(),
		"gd": roundi(state.wave.gate_damage * 10.0),
		"dw": dw,
	}
	if state.wave.rush_s > 0.0:
		snap["ru"] = [1, maxi(state.wave.rush_next - 1, 0), _ms(state.wave.rush_s)]
	var rack := state.station(SiegeIds.STATION_ARROWS).rack
	if rack != 0:
		snap["rk"] = rack
	return snap


## Overwrites the snapshot part of `state` from `snap` (clients). Riders are matched by slot,
## stations by id, pads by number; enemies are rebuilt (positions from state.path when present).
static func apply(state: SiegeState, snap: Dictionary) -> void:
	state.init_fixed()
	state.tick = int(snap.get("tick", state.tick))
	state.phase_index = int(snap.get("ph", state.phase_index))
	state.phase_elapsed_s = int(snap.get("pt_ms", 0)) / 1000.0
	var g: Array = snap.get("gate", [])
	if g.size() == 3:
		state.gate_hp = float(int(g[SiegeSnapshotSchema.G_HP]))
		state.gate_max = float(int(g[SiegeSnapshotSchema.G_MAX]))
		state.breach_s = int(g[SiegeSnapshotSchema.G_BREACH_MS]) / 1000.0
	state.breaches = int(snap.get("nb", 0))
	state.iron_bands = int(snap.get("ib", 0))
	state.mine_level = int(snap.get("ml", 0))
	state.perks.clear()
	for p: Variant in snap.get("pk", []):
		state.perks.append(int(p))
	state.team_w = float(int(snap.get("w", 0)))
	_riders(state, snap.get("r", []))
	_stations(state, snap.get("st", []), snap.get("dw", []))
	_pads(state, snap.get("pd", []))
	_tar(state, snap.get("tar", []))
	_enemies(state, snap.get("e", []))
	state.queue_len = int(snap.get("q", 0))
	state.wave.gate_damage = int(snap.get("gd", 0)) / 10.0
	state.station(SiegeIds.STATION_ARROWS).rack = int(snap.get("rk", 0))
	var ru: Variant = snap.get("ru")
	if ru is Array and (ru as Array).size() > SiegeSnapshotSchema.RU_INDEX:
		var left_ms := (
			int(ru[SiegeSnapshotSchema.RU_LEFT_MS])
			if (ru as Array).size() > SiegeSnapshotSchema.RU_LEFT_MS
			else 1000
		)
		state.wave.rush_s = (
			maxf(left_ms / 1000.0, 0.001) if int(ru[SiegeSnapshotSchema.RU_ON]) != 0 else 0.0
		)
		state.wave.rush_next = int(ru[SiegeSnapshotSchema.RU_INDEX]) + 1
	else:
		state.wave.rush_s = 0.0


static func _riders(state: SiegeState, rows: Variant) -> void:
	for row: Variant in rows if rows is Array else []:
		if not (row is Array) or (row as Array).size() < SiegeSnapshotSchema.R_LEN:
			continue
		var rd := state.rider_at(int(row[SiegeSnapshotSchema.R_SLOT]))
		if rd == null:
			continue
		rd.target = clampi(int(row[SiegeSnapshotSchema.R_TARGET]), 0, SiegeIds.STATION_COUNT - 1)
		rd.reconnect_s = int(row[SiegeSnapshotSchema.R_RECONNECT_MS]) / 1000.0
		rd.od_s = int(row[SiegeSnapshotSchema.R_OD_MS]) / 1000.0
		rd.od_cd_s = int(row[SiegeSnapshotSchema.R_OD_CD_MS]) / 1000.0
		rd.od_state = (
			SiegeIds.OD_ACTIVE
			if rd.od_s > 0.0
			else (SiegeIds.OD_COOLDOWN if rd.od_cd_s > 0.0 else SiegeIds.OD_READY)
		)
		rd.gold = float(int(row[SiegeSnapshotSchema.R_GOLD]))
		rd.p_eff_w = float(int(row[SiegeSnapshotSchema.R_P_EFF_W]))
		rd.raw_w = float(int(row[SiegeSnapshotSchema.R_RAW_W]))
		rd.cadence_rpm = float(int(row[SiegeSnapshotSchema.R_CADENCE]))
		rd.rescue = int(row[SiegeSnapshotSchema.R_RESCUE]) != 0
		rd.afk = int(row[SiegeSnapshotSchema.R_AFK]) != 0


static func _stations(state: SiegeState, rows: Variant, dw: Variant) -> void:
	for row: Variant in rows if rows is Array else []:
		if not (row is Array) or (row as Array).size() < SiegeSnapshotSchema.ST_LEN:
			continue
		var id := int(row[SiegeSnapshotSchema.ST_ID])
		if not SiegeIds.is_station(id):
			continue
		var s := state.station(id)
		s.level = int(row[SiegeSnapshotSchema.ST_LEVEL])
		s.wind = int(row[SiegeSnapshotSchema.ST_WIND_PM]) / 1000.0
		s.yaw_deg = int(row[SiegeSnapshotSchema.ST_YAW_CDEG]) / 100.0
		s.m = int(row[SiegeSnapshotSchema.ST_M_X100]) / 100.0
		s.arm = int(row[SiegeSnapshotSchema.ST_ARM_PM]) / 1000.0
	for row: Variant in dw if dw is Array else []:
		if not (row is Array) or (row as Array).size() < SiegeSnapshotSchema.DW_LEN:
			continue
		var id := int(row[SiegeSnapshotSchema.DW_STATION])
		if SiegeIds.is_station(id):
			state.station(id).damage_wave = float(int(row[SiegeSnapshotSchema.DW_DAMAGE]))


static func _pads(state: SiegeState, rows: Variant) -> void:
	for p in state.pads:
		p.type = SiegeIds.PAD_NONE
		p.level = 0
		p.cd_s = 0.0
	for row: Variant in rows if rows is Array else []:
		if not (row is Array) or (row as Array).size() < SiegeSnapshotSchema.PD_LEN:
			continue
		var n := int(row[SiegeSnapshotSchema.PD_PAD])
		if not SiegeIds.is_pad(n):
			continue
		var p := state.pad(n)
		p.type = int(row[SiegeSnapshotSchema.PD_TYPE])
		p.level = int(row[SiegeSnapshotSchema.PD_LEVEL])
		p.cd_s = int(row[SiegeSnapshotSchema.PD_CD_MS]) / 1000.0
		p.yaw_deg = int(row[SiegeSnapshotSchema.PD_YAW_CDEG]) / 100.0


static func _tar(state: SiegeState, row: Variant) -> void:
	state.tar.cauldron_max_l = state.cauldron_max()
	state.tar.curtain_max = state.curtain_max()
	if not (row is Array) or (row as Array).size() < SiegeSnapshotSchema.TAR_LEN:
		return
	state.tar.cauldron_l = int(row[SiegeSnapshotSchema.TAR_CAULDRON_DL]) / 10.0
	state.tar.curtain_hp = int(row[SiegeSnapshotSchema.TAR_CURTAIN_DHP]) / 10.0
	state.tar.coat = int(row[SiegeSnapshotSchema.TAR_COAT_PM]) / 1000.0
	state.tar.boarded = int(row[SiegeSnapshotSchema.TAR_BOARDED]) != 0


static func _enemies(state: SiegeState, rows: Variant) -> void:
	state.enemies.clear()
	for row: Variant in rows if rows is Array else []:
		if not (row is Array) or (row as Array).size() < SiegeSnapshotSchema.E_LEN:
			continue
		var en := SiegeEnemyState.new()
		en.id = int(row[SiegeSnapshotSchema.E_ID])
		en.type = int(row[SiegeSnapshotSchema.E_TYPE])
		en.prog_m = int(row[SiegeSnapshotSchema.E_PROG_DM]) / 10.0
		en.lat_m = int(row[SiegeSnapshotSchema.E_LAT_DM]) / 10.0
		en.hp = float(int(row[SiegeSnapshotSchema.E_HP]))
		en.st = int(row[SiegeSnapshotSchema.E_ST])
		var def: Dictionary = state.content.enemy_def(en.type) if state.content != null else {}
		en.max_hp = maxf(float(def.get("hp", en.hp)), en.hp)
		en.speed_mps = float(def.get("speed_mps", 0.0)) if en.st == SiegeIds.EN_WALK else 0.0
		if state.path != null:
			en.place(state.path)
		state.enemies.append(en)


static func _ms(s: float) -> int:
	return maxi(roundi(s * 1000.0), 0)


static func _pm(f: float) -> int:
	return clampi(roundi(f * 1000.0), 0, 1000)
