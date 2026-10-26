class_name FishingSnapshot
extends RefCounted
## Encodes FishingState as FishingSnapshotSchema's compact integer form (v2) and applies one back.
## encode() runs on the host at 10 Hz; apply() overwrites a client's state with everything the
## schema carries, so one snapshot fully restores a rejoining client (its peers, world and
## content come from its own configure). Every number is cast with int() whatever
## Protocol.decode() did. The client's fish has no slot: the jump flag sets fish.jumping.

const S = preload("res://src/games/fishing/contracts/fishing_snapshot_schema.gd")


static func encode(st: FishingState) -> Dictionary:
	var rows: Array = []
	for r in st.riders:
		rows.append(_row(st, r))
	var board: Array = []
	for i in st.catches.size() / 4:
		board.append(
			[st.catches[4 * i], st.catches[4 * i + 1], st.catches[4 * i + 2], st.catches[4 * i + 3]]
		)
	return {
		"v": S.VERSION,
		"k": st.tick,
		"R": rows,
		"T":
		[
			S.MODE_ROAM if st.roam else S.MODE_WORKOUT,
			ceili(st.time_left_s() - 1e-6) if not st.time_up else 0,
			int(st.time_up),
			st.team_points,
			st.team_fish,
			st.hookup_level,
		],
		"C": board
	}


static func _row(st: FishingState, r: FishingRiderState) -> Array:
	var f := r.fish
	var hints: Array = []
	if r.action == FishingConst.A_MENU:
		for i in r.hint_count():
			hints.append(
				[
					int(r.hints[4 * i]),
					roundi(r.hints[4 * i + 1] * 10.0),
					roundi(r.hints[4 * i + 2] * 10.0),
					S.u8(r.hints[4 * i + 3])
				]
			)
	var fighting := r.in_fight() and f.sp >= 0
	var row: Array = []
	row.resize(S.R_COLUMNS)
	row[S.R_SLOT] = r.slot
	row[S.R_X_DM] = roundi(r.x_m * 10.0)
	row[S.R_HEADING] = r.heading
	row[S.R_SPEED_CMS] = roundi(r.v_mps * 100.0)
	row[S.R_PITCH_DD] = roundi(r.pitch_deg * 10.0)
	row[S.R_WAKE] = S.u8(r.wake)
	row[S.R_THROTTLE] = clampi(roundi(100.0 * r.p_eff_w / FishingConst.P_EFF_REF_W), 0, 255)
	row[S.R_ACTION] = r.action
	row[S.R_SELECTED] = r.selected if r.action == FishingConst.A_MENU else -1
	row[S.R_MENU] = r.menu.duplicate() if r.action == FishingConst.A_MENU else []
	row[S.R_SPECIES] = f.sp if fighting else r.target_sp
	row[S.R_FISH_DX_DM] = roundi(r.fish_dx() * 10.0) if fighting else 0
	row[S.R_FISH_DEPTH_DM] = roundi(f.depth_m() * 10.0) if fighting else 0
	row[S.R_LURE_DX_DM] = roundi(r.lure_dx * 10.0)
	row[S.R_LURE_DEPTH_DM] = roundi(r.lure_depth * 10.0)
	row[S.R_LINE_DM] = roundi(r.line_m() * 10.0)
	row[S.R_STRAIN] = S.u8(r.strain)
	row[S.R_SLACK] = S.u8(r.slack)
	row[S.R_GAFF] = S.u8(r.gaff)
	row[S.R_STAMINA] = S.u8(f.s) if fighting else 0
	row[S.R_BAND_LO] = r.pub_lo
	row[S.R_BAND_HI] = r.pub_hi
	row[S.R_POWER_W] = roundi(r.power_w)
	row[S.R_CADENCE] = roundi(r.cadence_ema)
	row[S.R_FLAGS] = flags(st, r)
	row[S.R_POINTS] = r.points
	row[S.R_LANDED] = r.fish_landed
	row[S.R_COSMETICS] = r.cosmetics.duplicate()
	row[S.R_HINTS] = hints
	row[S.R_STATE_DS] = roundi(r.state_t * 10.0)
	row[S.R_FURTHEST_DM] = roundi(r.furthest_x_m * 10.0)
	row[S.R_BRAKE] = S.u8(r.brake)
	row[S.R_HEAVE_CM] = roundi(r.heave_m * 100.0)
	row[S.R_PLANE] = S.u8(r.plane)
	row[S.R_TOW] = S.u8(r.tow_n / FishingConst.TOW_MAX_N)
	row[S.R_PROP_CM] = roundi(r.prop_depth_m * 100.0)
	row[S.R_REEL] = S.u8(r.reel) if fighting else 0
	return row


static func flags(st: FishingState, r: FishingRiderState) -> int:
	var fl := 0
	if r.rescue or r.rescue_now:
		fl |= S.F_RESCUE
	if r.is_afk():
		fl |= S.F_AFK
	if r.cadence_stale or r.stale:
		fl |= S.F_STALE
	if r.paused:
		fl |= S.F_PAUSED
	if r.p_eff_w > FishingConst.SPRINT_P_FRAC * FishingConst.P_EFF_REF_W:
		fl |= S.F_SPRINT
	var f := r.fish
	if r.in_fight() and f.run_active:
		fl |= S.F_RUN
		if f.jumping:
			fl |= S.F_JUMP
	if r.gaff >= 1.0:
		fl |= S.F_TROPHY
	if r.in_fight() and f.replacement:
		fl |= S.F_REPLACEMENT
	if r.in_fight() and f.off_line:
		fl |= S.F_OFF_LINE
	if r.auto_plays():
		fl |= S.F_AUTO
	if r.pedal_nav:
		fl |= S.F_PEDAL_NAV
	if st.roam and r.phase_kind == Wl.WARMUP:
		fl |= S.F_WARMUP
	if r.is_bot:
		fl |= S.F_BOT
	if r.in_fight() and r.surging:
		fl |= S.F_SURGE
	return fl


## Overwrites `st` from `snap` (ints cast here whatever Protocol.decode did).
static func apply(st: FishingState, snap: Dictionary) -> void:
	var why := S.check(snap)
	if why != "":
		push_warning("fishing: snapshot ignored: %s" % why)
		return
	st.tick = int(snap["k"])
	st.t = st.tick * Wl.SIM_DT
	for row: Array in snap["R"]:
		var r := st.rider(int(row[S.R_SLOT]))
		if r != null:
			_apply_row(r, row)
	var tm: Array = snap["T"]
	st.roam = int(tm[S.T_MODE]) == S.MODE_ROAM
	st.time_up = int(tm[S.T_OVER]) != 0
	if not st.time_up:
		st.play_end_t = st.t + float(int(tm[S.T_TIME_LEFT_S]))
	st.team_points = int(tm[S.T_POINTS])
	st.team_fish = int(tm[S.T_FISH])
	st.hookup_level = int(tm[S.T_HOOKUP])
	st.catches.clear()
	for c: Variant in snap["C"]:
		for v: Variant in c:
			st.catches.append(int(v))


static func _apply_row(r: FishingRiderState, row: Array) -> void:
	var f := r.fish
	r.x_m = int(row[S.R_X_DM]) / 10.0
	r.heading = 1 if int(row[S.R_HEADING]) >= 0 else -1
	r.v_mps = int(row[S.R_SPEED_CMS]) / 100.0
	r.pitch_deg = int(row[S.R_PITCH_DD]) / 10.0
	r.wake = S.unit(row[S.R_WAKE])
	r.p_eff_w = int(row[S.R_THROTTLE]) * FishingConst.P_EFF_REF_W / 100.0
	var action := int(row[S.R_ACTION])
	if action != r.action:
		r.action = action
	r.selected = int(row[S.R_SELECTED])
	r.menu.clear()
	for m: Variant in row[S.R_MENU]:
		r.menu.append(int(m))
	var sp := int(row[S.R_SPECIES])
	var fighting := r.in_fight()
	r.target_sp = sp
	f.sp = sp if fighting else FishingConst.SP_NONE
	var dx := int(row[S.R_FISH_DX_DM]) / 10.0
	f.d = absf(dx)
	var depth := int(row[S.R_FISH_DEPTH_DM]) / 10.0
	f.hook_depth_m = maxf(depth, 1.0)
	f.z = depth / f.hook_depth_m
	r.lure_dx = int(row[S.R_LURE_DX_DM]) / 10.0
	r.lure_depth = int(row[S.R_LURE_DEPTH_DM]) / 10.0
	r.strain = S.unit(row[S.R_STRAIN])
	r.slack = S.unit(row[S.R_SLACK])
	r.gaff = S.unit(row[S.R_GAFF])
	f.s = S.unit(row[S.R_STAMINA])
	r.pub_lo = int(row[S.R_BAND_LO])
	r.pub_hi = int(row[S.R_BAND_HI])
	r.power_w = float(int(row[S.R_POWER_W]))
	r.cadence_ema = float(int(row[S.R_CADENCE]))
	var fl := int(row[S.R_FLAGS])
	r.rescue = fl & S.F_RESCUE != 0
	r.afk = fl & S.F_AFK != 0
	r.cadence_stale = fl & S.F_STALE != 0
	r.paused = fl & S.F_PAUSED != 0
	f.run_active = fl & S.F_RUN != 0
	f.jumping = fl & S.F_JUMP != 0
	f.replacement = fl & S.F_REPLACEMENT != 0
	f.off_line = fl & S.F_OFF_LINE != 0
	r.pedal_nav = fl & S.F_PEDAL_NAV != 0
	if fl & S.F_WARMUP != 0:
		r.phase_kind = Wl.WARMUP
	elif r.phase_kind == Wl.WARMUP:
		r.phase_kind = Wl.FREE
	r.points = int(row[S.R_POINTS])
	r.fish_landed = int(row[S.R_LANDED])
	var cos: Array = row[S.R_COSMETICS]
	for i in mini(cos.size(), 4):
		r.cosmetics[i] = int(cos[i])
	r.hints.clear()
	for h: Variant in row[S.R_HINTS]:
		r.hints.append(float(int(h[S.H_SPECIES])))
		r.hints.append(int(h[S.H_DX_DM]) / 10.0)
		r.hints.append(int(h[S.H_DEPTH_DM]) / 10.0)
		r.hints.append(S.unit(h[S.H_SIZE]))
	r.state_t = int(row[S.R_STATE_DS]) / 10.0
	r.furthest_x_m = int(row[S.R_FURTHEST_DM]) / 10.0
	r.brake = S.unit(row[S.R_BRAKE])
	r.heave_m = int(row[S.R_HEAVE_CM]) / 100.0
	r.plane = S.unit(row[S.R_PLANE])
	r.planing = r.plane >= 0.5
	r.tow_n = S.unit(row[S.R_TOW]) * FishingConst.TOW_MAX_N
	r.prop_depth_m = int(row[S.R_PROP_CM]) / 100.0
	r.reel = S.unit(row[S.R_REEL])
	r.surging = fl & S.F_SURGE != 0


## JSON.stringify byte length of `snap` (the size GAME_SDK 12 measures; cap 2048 at 4 riders).
static func byte_size(snap: Dictionary) -> int:
	return JSON.stringify(snap).to_utf8_buffer().size()
