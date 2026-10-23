class_name FishingSnapshot
extends RefCounted
## Encodes FishingState as FishingSnapshotSchema's compact integer form and applies one back
## (brief 2.6). G0 version; fish-module owns this file.


static func encode(st: FishingState) -> Dictionary:
	var rows: Array = []
	for l in st.lanes:
		var f := l.fish
		var hints: Array = []
		if l.state == FishingConst.ST_PICK:
			for i in l.hint_count():
				hints.append(
					[
						int(l.hints[3 * i]),
						roundi(l.hints[3 * i + 1] * 10.0),
						FishingSnapshotSchema.u8(l.hints[3 * i + 2])
					]
				)
		var flags := 0
		if l.rescue:
			flags |= FishingSnapshotSchema.F_RESCUE
		if l.afk or l.stale:
			flags |= FishingSnapshotSchema.F_AFK
		if f.run_active:
			flags |= FishingSnapshotSchema.F_RUN
			if l.fight_slot >= 0 and l.fight_slot < l.slots.size():
				if l.slots[l.fight_slot].run_kind == FishingSpeciesDef.RUN_JUMP:
					flags |= FishingSnapshotSchema.F_JUMP
		if f.replacement:
			flags |= FishingSnapshotSchema.F_REPLACEMENT
		if l.gaff >= 1.0:
			flags |= FishingSnapshotSchema.F_TROPHY
		if l.cadence_stale or l.stale:
			flags |= FishingSnapshotSchema.F_STALE
		if l.frenzy_until_t > st.t:
			flags |= FishingSnapshotSchema.F_FRENZY
		if f.off_line:
			flags |= FishingSnapshotSchema.F_OFF_LINE
		if l.auto_plays():
			flags |= FishingSnapshotSchema.F_FALLBACK
		var row: Array = []
		row.resize(FishingSnapshotSchema.L_COLUMNS)
		row[FishingSnapshotSchema.L_SLOT] = l.slot
		row[FishingSnapshotSchema.L_PHASE] = l.phase_index
		row[FishingSnapshotSchema.L_STATE] = l.state
		row[FishingSnapshotSchema.L_SPECIES] = f.sp
		row[FishingSnapshotSchema.L_D_DM] = roundi(f.d * 10.0)
		row[FishingSnapshotSchema.L_Z_PM] = roundi(f.z * 1000.0)
		row[FishingSnapshotSchema.L_S] = FishingSnapshotSchema.u8(f.s)
		row[FishingSnapshotSchema.L_STRAIN] = FishingSnapshotSchema.u8(l.strain)
		row[FishingSnapshotSchema.L_SLACK] = FishingSnapshotSchema.u8(l.slack)
		row[FishingSnapshotSchema.L_GAFF] = FishingSnapshotSchema.u8(l.gaff)
		row[FishingSnapshotSchema.L_BAND_LO] = l.pub_lo
		row[FishingSnapshotSchema.L_BAND_HI] = l.pub_hi
		row[FishingSnapshotSchema.L_POWER_W] = roundi(l.power_w)
		row[FishingSnapshotSchema.L_CADENCE] = roundi(l.cadence_ema)
		row[FishingSnapshotSchema.L_SELECTED] = l.selected
		row[FishingSnapshotSchema.L_LURE_DM] = roundi(l.lure_d * 10.0)
		row[FishingSnapshotSchema.L_FLAGS] = flags
		row[FishingSnapshotSchema.L_COSMETICS] = l.cosmetics.duplicate()
		row[FishingSnapshotSchema.L_HINTS] = hints
		row[FishingSnapshotSchema.L_STATE_DS] = roundi(l.state_t * 10.0)
		row[FishingSnapshotSchema.L_POINTS] = l.points
		row[FishingSnapshotSchema.L_LANDED] = l.fish_landed
		rows.append(row)
	var board: Array = []
	for i in st.catches.size() / 3:
		board.append([st.catches[3 * i], st.catches[3 * i + 1], st.catches[3 * i + 2]])
	return {
		"v": FishingSnapshotSchema.VERSION,
		"k": st.tick,
		"L": rows,
		"T":
		[
			st.team_points,
			st.team_fish,
			st.hookup_level,
			int(st.trip_over),
			maxi(ceili(st.fishing_end_t - st.t), 0)
		],
		"C": board
	}


## Overwrites `st` from `snap` (ints cast here whatever Protocol.decode did).
static func apply(st: FishingState, snap: Dictionary) -> void:
	if FishingSnapshotSchema.check(snap) != "":
		push_warning("fishing: snapshot ignored: %s" % FishingSnapshotSchema.check(snap))
		return
	st.tick = int(snap["k"])
	st.t = st.tick * Wl.SIM_DT
	for row: Array in snap["L"]:
		var l := st.lane(int(row[FishingSnapshotSchema.L_SLOT]))
		if l == null:
			continue
		var f := l.fish
		l.phase_index = int(row[FishingSnapshotSchema.L_PHASE])
		l.state = int(row[FishingSnapshotSchema.L_STATE])
		f.sp = int(row[FishingSnapshotSchema.L_SPECIES])
		f.d = int(row[FishingSnapshotSchema.L_D_DM]) / 10.0
		f.z = int(row[FishingSnapshotSchema.L_Z_PM]) / 1000.0
		f.s = FishingSnapshotSchema.unit(row[FishingSnapshotSchema.L_S])
		l.strain = FishingSnapshotSchema.unit(row[FishingSnapshotSchema.L_STRAIN])
		l.slack = FishingSnapshotSchema.unit(row[FishingSnapshotSchema.L_SLACK])
		l.gaff = FishingSnapshotSchema.unit(row[FishingSnapshotSchema.L_GAFF])
		l.pub_lo = int(row[FishingSnapshotSchema.L_BAND_LO])
		l.pub_hi = int(row[FishingSnapshotSchema.L_BAND_HI])
		l.power_w = float(int(row[FishingSnapshotSchema.L_POWER_W]))
		l.cadence_ema = float(int(row[FishingSnapshotSchema.L_CADENCE]))
		l.selected = int(row[FishingSnapshotSchema.L_SELECTED])
		l.lure_d = int(row[FishingSnapshotSchema.L_LURE_DM]) / 10.0
		var flags := int(row[FishingSnapshotSchema.L_FLAGS])
		l.rescue = flags & FishingSnapshotSchema.F_RESCUE != 0
		l.afk = flags & FishingSnapshotSchema.F_AFK != 0
		f.run_active = flags & FishingSnapshotSchema.F_RUN != 0
		f.replacement = flags & FishingSnapshotSchema.F_REPLACEMENT != 0
		f.off_line = flags & FishingSnapshotSchema.F_OFF_LINE != 0
		l.cadence_stale = flags & FishingSnapshotSchema.F_STALE != 0
		var cos: Array = row[FishingSnapshotSchema.L_COSMETICS]
		for i in mini(cos.size(), 4):
			l.cosmetics[i] = int(cos[i])
		l.hints.clear()
		for h: Variant in row[FishingSnapshotSchema.L_HINTS]:
			l.hints.append(float(int(h[0])))
			l.hints.append(int(h[1]) / 10.0)
			l.hints.append(FishingSnapshotSchema.unit(h[2]))
		l.state_t = int(row[FishingSnapshotSchema.L_STATE_DS]) / 10.0
		l.points = int(row[FishingSnapshotSchema.L_POINTS])
		l.fish_landed = int(row[FishingSnapshotSchema.L_LANDED])
	var tm: Array = snap["T"]
	st.team_points = int(tm[FishingSnapshotSchema.T_POINTS])
	st.team_fish = int(tm[FishingSnapshotSchema.T_FISH])
	st.hookup_level = int(tm[FishingSnapshotSchema.T_HOOKUP])
	st.trip_over = int(tm[FishingSnapshotSchema.T_TRIP_OVER]) != 0
	st.catches.clear()
	for c: Variant in snap["C"]:
		for v: Variant in c:
			st.catches.append(int(v))
