class_name SiegeSnapshot
extends RefCounted
## Encodes SiegeState into the 10 Hz snapshot (SiegeSnapshotSchema, brief 2.6) and applies one
## on a client. Owner: B2 "module". Every value written is an int; apply() casts everything it
## reads with int(), nested arrays included, so a JSON round trip without int_fields still works.
##
## G0 status: complete for the schema. B2 adds the client's interpolation history (like
## WorkoutSnapHistory: keyed by tick, render clock behind the newest snapshot by their mean
## spacing) without changing encode()'s output.


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
					floori(rd.denarii),
					roundi(rd.p_eff_w),
					roundi(rd.raw_w),
					roundi(rd.cadence_rpm),
					int(rd.rescue),
					int(rd.afk),
				]
			)
		)
	var tw: Array = []
	for t in state.pads:
		if t.built():
			tw.append([t.pad, t.type, t.level, roundi(t.m * 100.0), _ms(t.cd_s)])
	var e: Array = []
	for en in state.enemies:
		e.append(
			[
				en.id,
				en.type,
				en.road,
				roundi(en.prog_m * 10.0),
				roundi(en.lat_m * 10.0),
				ceili(en.hp)
			]
		)
	var z: Array = []
	for zn in state.zones:
		z.append([zn.road, roundi(zn.prog_m * 10.0), _ms(zn.delay_s + zn.ttl_s)])
	var f: Array = []
	for s in state.shots:
		f.append([s.pad, s.targets.duplicate()])
	return {
		"v": SiegeSnapshotSchema.VERSION,
		"tick": state.tick,
		"ph": state.phase_index,
		"pt_ms": _ms(state.phase_elapsed_s),
		"gate": [ceili(state.gate_hp), roundi(state.gate_max), _ms(state.breach_s)],
		"nb": state.breaches,
		"gl": state.gen_level,
		"pk": state.perks.duplicate(),
		"w": roundi(state.team_w),
		"r": r,
		"tw": tw,
		"e": e,
		"z": z,
		"f": f,
		"q": state.queued(),
	}


## Overwrites the snapshot part of `state` from `snap` (clients). Riders are matched by slot;
## enemies, zones and shots are rebuilt (positions from state.content.map when present).
static func apply(state: SiegeState, snap: Dictionary) -> void:
	state.tick = int(snap.get("tick", state.tick))
	state.phase_index = int(snap.get("ph", state.phase_index))
	state.phase_elapsed_s = int(snap.get("pt_ms", 0)) / 1000.0
	var g: Array = snap.get("gate", [])
	if g.size() == 3:
		state.gate_hp = float(int(g[SiegeSnapshotSchema.G_HP]))
		state.gate_max = float(int(g[SiegeSnapshotSchema.G_MAX]))
		state.breach_s = int(g[SiegeSnapshotSchema.G_BREACH_MS]) / 1000.0
	state.breaches = int(snap.get("nb", 0))
	state.gen_level = int(snap.get("gl", 0))
	state.perks.clear()
	for p: Variant in snap.get("pk", []):
		state.perks.append(int(p))
	state.team_w = float(int(snap.get("w", 0)))
	for row: Variant in snap.get("r", []):
		if not (row is Array) or (row as Array).size() < SiegeSnapshotSchema.R_LEN:
			continue
		var rd := state.rider_at(int(row[SiegeSnapshotSchema.R_SLOT]))
		if rd == null:
			continue
		rd.target = int(row[SiegeSnapshotSchema.R_TARGET])
		rd.reconnect_s = int(row[SiegeSnapshotSchema.R_RECONNECT_MS]) / 1000.0
		rd.od_s = int(row[SiegeSnapshotSchema.R_OD_MS]) / 1000.0
		rd.od_cd_s = int(row[SiegeSnapshotSchema.R_OD_CD_MS]) / 1000.0
		rd.od_state = (
			SiegeIds.OD_ACTIVE
			if rd.od_s > 0.0
			else (SiegeIds.OD_COOLDOWN if rd.od_cd_s > 0.0 else SiegeIds.OD_READY)
		)
		rd.denarii = float(int(row[SiegeSnapshotSchema.R_DENARII]))
		rd.p_eff_w = float(int(row[SiegeSnapshotSchema.R_P_EFF_W]))
		rd.raw_w = float(int(row[SiegeSnapshotSchema.R_RAW_W]))
		rd.cadence_rpm = float(int(row[SiegeSnapshotSchema.R_CADENCE]))
		rd.rescue = int(row[SiegeSnapshotSchema.R_RESCUE]) != 0
		rd.afk = int(row[SiegeSnapshotSchema.R_AFK]) != 0
	for t in state.pads:
		t.type = SiegeIds.TOWER_NONE
		t.level = 0
		t.m = 0.0
		t.cd_s = 0.0
	for row: Variant in snap.get("tw", []):
		if not (row is Array) or (row as Array).size() < SiegeSnapshotSchema.TW_LEN:
			continue
		var n := int(row[SiegeSnapshotSchema.TW_PAD])
		if not SiegeIds.is_pad(n) or state.pads.size() < n:
			continue
		var t := state.pad(n)
		t.type = int(row[SiegeSnapshotSchema.TW_TYPE])
		t.level = int(row[SiegeSnapshotSchema.TW_LEVEL])
		t.m = int(row[SiegeSnapshotSchema.TW_M_X100]) / 100.0
		t.cd_s = int(row[SiegeSnapshotSchema.TW_CD_MS]) / 1000.0
	var map: SiegeMap = state.content.map if state.content != null else null
	state.enemies.clear()
	for row: Variant in snap.get("e", []):
		if not (row is Array) or (row as Array).size() < SiegeSnapshotSchema.E_LEN:
			continue
		var en := SiegeEnemyState.new()
		en.id = int(row[SiegeSnapshotSchema.E_ID])
		en.type = int(row[SiegeSnapshotSchema.E_TYPE])
		en.road = int(row[SiegeSnapshotSchema.E_ROAD])
		en.prog_m = int(row[SiegeSnapshotSchema.E_PROG_DM]) / 10.0
		en.lat_m = int(row[SiegeSnapshotSchema.E_LAT_DM]) / 10.0
		en.hp = float(int(row[SiegeSnapshotSchema.E_HP]))
		var def: Dictionary = state.content.enemy_def(en.type) if state.content != null else {}
		en.max_hp = maxf(float(def.get("hp", en.hp)), en.hp)
		if map != null and en.road >= 0 and en.road < map.road_count():
			en.place(map)
		state.enemies.append(en)
	state.zones.clear()
	var zone_s := 4.0
	if state.content != null:
		zone_s = float(state.content.tower_def(SiegeIds.TOWER_CALTROP).get("zone_s", 4.0))
	for row: Variant in snap.get("z", []):
		if not (row is Array) or (row as Array).size() < SiegeSnapshotSchema.Z_LEN:
			continue
		var zn := SiegeZoneState.new()
		zn.road = int(row[SiegeSnapshotSchema.Z_ROAD])
		zn.prog_m = int(row[SiegeSnapshotSchema.Z_PROG_DM]) / 10.0
		var left := int(row[SiegeSnapshotSchema.Z_TTL_MS]) / 1000.0
		zn.ttl_s = minf(left, zone_s)
		zn.delay_s = maxf(left - zone_s, 0.0)
		if map != null and zn.road >= 0 and zn.road < map.road_count():
			zn.pos = map.point_at(zn.road, zn.prog_m)
		state.zones.append(zn)
	state.shots.clear()
	for row: Variant in snap.get("f", []):
		if not (row is Array) or (row as Array).size() < 2:
			continue
		var s := SiegeShot.new()
		s.pad = int(row[SiegeSnapshotSchema.F_PAD])
		for id: Variant in (
			row[SiegeSnapshotSchema.F_TARGETS]
			if row[SiegeSnapshotSchema.F_TARGETS] is Array
			else []
		):
			s.targets.append(int(id))
		state.shots.append(s)
	state.queue_len = int(snap.get("q", 0))


static func _ms(s: float) -> int:
	return maxi(roundi(s * 1000.0), 0)
