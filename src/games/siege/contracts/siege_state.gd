class_name SiegeState
extends SiegeRecord
## The whole Castellum Rotae game state (contracts/STATE_V2.md). The rules (SiegeRules.step)
## mutate it on the host; the module encodes it into snapshots (SiegeSnapshot) and clients
## rebuild the snapshot part from them; the view and HUD only read it; the headless sim drives
## it directly. Deterministic: every random draw goes through `rng` (ctx.rng on the host), and
## every list is kept in a fixed order (riders by slot, stations by id, pads by number, enemies
## and projectiles by spawn).
##
## Fields marked [snap] travel in the 10 Hz snapshot (SiegeSnapshotSchema); everything else is
## host-only bookkeeping (a client keeps its last value or what its events told it).

## Validated content (not serialized).
var content: SiegeContent = null
## The battlefield (content.path; not serialized).
var path: SiegePath = null
## The session RNG (ctx.rng on the host; null on clients, which never simulate).
var rng: RandomNumberGenerator = null

var shift_id: String = ""
## Wl.FAIR_FTP, Wl.WKG or Wl.RAW (the r factor of the budget B, brief 2.4).
var scaling_mode: String = Wl.FAIR_FTP
## [snap] Game tick of the latest step (frame.tick).
var tick: int = 0
## Game seconds (tick x 0.05).
var t: float = 0.0

# --- The shared phase (frame.phase of any slot; the role comes from PlanPhase.meta) ---------------
## [snap] (ph) Plan phase index; -1 before the first step.
var phase_index: int = -1
## SiegeIds.ROLE_*.
var role: String = SiegeIds.ROLE_NONE
## Wave number 1..N in a wave (the drill's wave is 1), 0 in the warm-up wave; break number n
## in break n; 0 otherwise.
var wave_no: int = 0
var waves_total: int = 0
## Wl.WARMUP / WORK / RECOVERY / COOLDOWN.
var phase_kind: String = ""
## [snap] (pt_ms) Seconds into the phase.
var phase_elapsed_s: float = 0.0
var phase_duration_s: float = 0.0
var phase_remaining_s: float = 0.0
## The last wave has ended (finished("complete") fired).
var done: bool = false

var riders: Array[SiegeRiderState] = []
## Index = station id, always STATION_COUNT entries.
var stations: Array[SiegeStationState] = []
## Pads 1..4 at index pad - 1, always PAD_COUNT entries.
var pads: Array[SiegePadState] = []
var enemies: Array[SiegeEnemyState] = []
## Host only: projectiles in flight (clients replay `shot` events instead).
var projectiles: Array[SiegeProjectile] = []
var tar: SiegeTarState = SiegeTarState.new()
## [snap] (q = size) Spawns waiting for room under the cap.
var queue: Array[SiegeSpawn] = []
## Clients: the snapshot's q (they have no queue entries). Read queued() instead of either.
var queue_len: int = 0
var next_enemy_id: int = 1
var wave: SiegeWaveState = SiegeWaveState.new()

# --- Gate (brief 2.4 "Gate and Breach") --------------------------------------------------------------
## [snap] gate [hp, max, breach_ms]
var gate_hp: float = 130.0
var gate_max: float = 130.0
## Seconds left of a Breach (every station and pad stops; arrivals vanish; rams pause).
var breach_s: float = 0.0
## [snap] (nb)
var breaches: int = 0
## [snap] (ib) Iron bands bought (0..2).
var iron_bands: int = 0

# --- Team economy ------------------------------------------------------------------------------------
## [snap] (ml) Mine level 0..3 (+20% gold each).
var mine_level: int = 0
## [snap] (pk) SiegeIds.PERK_* bought (team, once each).
var perks: Array[int] = []
var bounty_scale: float = 1.0
## [snap] (w) Team raw watts, a 1 s mean.
var team_w: float = 0.0
## The last 20 ticks of the team's raw watts (the mean's window).
var team_w_window: Array[float] = []

# --- Results (brief 2.8) ------------------------------------------------------------------------------
## Gate HP and HP / max at each wave end (waves 1..N; the warm-up excluded).
var wave_gate_hp: Array[int] = []
var wave_gate_frac: Array[float] = []
## Leaks over waves 1..N.
var leaks: int = 0
## [snap] (gd, in 0.1 HP) Gate damage this wave (the curtain's share not included).
var gate_damage: float = 0.0
## Siege engines (rams and towers) that entered, and those destroyed before they reached the gate
## or docked (T4), over the session.
var engines_total: int = 0
var engines_stopped: int = 0
## Team gold earned (mine + bounties) from the warm-up to the last wave.
var team_earned: float = 0.0
## The team's planned P_eff in kJ from the warm-up to the last wave (par = 0.75 x it).
var planned_kj: float = 0.0

# --- The shared receipt (brief 2.4 "Shop") ------------------------------------------------------------
## [snap] (rc) The items picked in this break and not yet bought, in the order they were added.
## Bought in that order when the break ends; each picker's gold for them is held meanwhile.
var receipt: Array[SiegeReceiptLine] = []

## Peers whose Overdrive the rules started this tick (OD_PENDING): the module sends each one's
## directive and resolves it (SiegeOverdrive.on_request_result) in the same sim_step.
var od_requests: Array[int] = []


## A fresh state at the session start (brief 2.4): every rider on the mine with the starting
## gold, pad 1 with its Scorpion, the cauldrons full, the gate at full HP. `slots` in slot order
## (ctx.players).
static func create(
	p_content: SiegeContent,
	slots: Array[PlayerSlot],
	p_scaling_mode: String,
	p_rng: RandomNumberGenerator
) -> SiegeState:
	var s := SiegeState.new()
	s.content = p_content
	s.path = p_content.path
	s.rng = p_rng
	s.shift_id = p_content.shift_id
	s.scaling_mode = p_scaling_mode
	var start := p_content.num("start_gold", 40.0)
	for p in slots:
		var r := SiegeRiderState.new()
		r.slot = p.slot_index
		r.peer = p.peer_id
		r.is_bot = p.is_bot
		r.autopilot = p.autopilot or p.is_bot
		r.ftp = p.ftp
		r.ftp_verified = p.ftp_verified
		# WKG's r before any telemetry of >= 50 W: the slot's own ratio (the host has every
		# rider's), not 1.0 (ADR "WKG warm-up budget").
		r.r_wkg = p.p_eff_per_w if p.p_eff_per_w > 0.0 else 1.0
		r.gold = start
		s.riders.append(r)
	s.init_fixed()
	for st: Variant in (p_content.stations.get("pads", {}) as Dictionary).get("start", []):
		var pd := s.pad(int(st["pad"]))
		pd.type = SiegeIds.pad_code(str(st["type"]))
		pd.cd_s = 0.0
	s.gate_max = p_content.num("gate.hp", 130.0)
	s.gate_hp = s.gate_max
	s.bounty_scale = p_content.num("bounty_scale", 1.0)
	s.waves_total = SiegePlanBuilder.wave_count(p_content.shift)
	s.tar.cauldron_max_l = s.cauldron_max()
	s.tar.cauldron_l = s.tar.cauldron_max_l
	s.tar.curtain_max = s.curtain_max()
	return s


## The five stations and four pads at their starting yaw (missing ones are added; existing ones
## are kept). Fixtures and from_dict call it too.
func init_fixed() -> void:
	while stations.size() < SiegeIds.STATION_COUNT:
		var st := SiegeStationState.new()
		st.id = stations.size()
		if path != null and st.id < path.station_yaw0_deg.size():
			st.yaw_deg = path.station_yaw0_deg[st.id]
		stations.append(st)
	while pads.size() < SiegeIds.PAD_COUNT:
		var pd := SiegePadState.new()
		pd.pad = pads.size() + 1
		pads.append(pd)


# --- Lookups -----------------------------------------------------------------------------------------


## The rider of `peer`, or null.
func rider(peer: int) -> SiegeRiderState:
	for r in riders:
		if r.peer == peer:
			return r
	return null


## The rider in slot index `slot`, or null.
func rider_at(slot: int) -> SiegeRiderState:
	for r in riders:
		if r.slot == slot:
			return r
	return null


## Station 0..4.
func station(id: int) -> SiegeStationState:
	return stations[id]


## Pad 1..4.
func pad(n: int) -> SiegePadState:
	return pads[n - 1]


func built_pads() -> Array[int]:
	var out: Array[int] = []
	for pd in pads:
		if pd.built():
			out.append(pd.pad)
	return out


## The live enemy with `id`, or null.
func enemy(id: int) -> SiegeEnemyState:
	if id <= 0:
		return null
	# Enemies keep their spawn order, so ids ascend; a miss still reads them all in case they don't.
	var lo := 0
	var hi := enemies.size() - 1
	while lo <= hi:
		var mid := (lo + hi) >> 1
		var at := enemies[mid]
		if at.id == id:
			return at
		if at.id < id:
			lo = mid + 1
		else:
			hi = mid - 1
	for e in enemies:
		if e.id == id:
			return e
	return null


## Riders routed to station `id` (reconnecting ones included): the caps count these.
func routed_count(id: int) -> int:
	var n := 0
	for r in riders:
		if r.target == id:
			n += 1
	return n


## Riders whose output reaches station `id` now (SiegeRiderState.delivering()), in slot order.
func riders_on(id: int) -> Array[SiegeRiderState]:
	var out: Array[SiegeRiderState] = []
	for r in riders:
		if r.target == id and r.delivering():
			out.append(r)
	return out


## The rider cap of station `id` (stations.json: mine 2, ballista 1, onager 2, arrows 2, tar 1).
func station_cap(id: int) -> int:
	if content == null:
		return 2
	return int(content.station_def(id).get("cap", 2))


## Station `id`'s range band now: [lo, hi] metres from its pivot on the ground, hi x 1.25 after
## upgrade 2. Zero for the mine and the tar works.
func range_band(id: int) -> Vector2:
	if content == null or not SiegeIds.is_weapon(id):
		return Vector2.ZERO
	var b := content.range_band(id)
	if stations.size() > id and stations[id].level >= 2:
		b.y *= content.st_num("upgrade_range_mult", 1.25)
	return b


## True when world point `p` lies in station `id`'s range band (horizontal distance).
func in_band(id: int, p: Vector3) -> bool:
	if path == null:
		return false
	var b := range_band(id)
	var at := path.station_pos[id]
	var d2 := (p.x - at.x) * (p.x - at.x) + (p.y - at.y) * (p.y - at.y)
	return d2 >= b.x * b.x and d2 <= b.y * b.y and b.y > 0.0


## A built pad's range band [lo, hi] (hi x 1.25 after its upgrade 2). Zero for an empty pad.
func pad_band(n: int) -> Vector2:
	var pd := pad(n)
	if not pd.built() or content == null:
		return Vector2.ZERO
	var def := content.pad_def(pd.type)
	var r: Variant = def.get("range_m", [0, 0])
	var b := Vector2(float(r[0]), float(r[1]))
	if pd.level >= 2:
		b.y *= float(def.get("range_mult", 1.25))
	return b


## The cauldrons' capacity: 300 L, +100 with the Spare cauldron.
func cauldron_max() -> float:
	if content == null:
		return 300.0
	var c := content.st_num("stations.tar.cauldron_l", 300.0)
	if perks.has(SiegeIds.PERK_CAULDRON):
		c += content.st_num("stations.tar.spare_cauldron_l", 100.0)
	return c


## The curtain's capacity: 200 HP, +25% after the tar works' upgrade 2.
func curtain_max() -> float:
	if content == null:
		return 200.0
	var c := content.st_num("stations.tar.curtain_max", 200.0)
	if stations.size() > SiegeIds.STATION_TAR and stations[SiegeIds.STATION_TAR].level >= 2:
		c *= content.st_num("upgrade_range_mult", 1.25)
	return c


## Overdrive's prompt "their station has an enemy in range" (brief 2.4): a weapon with a live
## enemy in its band; the tar works with a ram or siege tower within 60 m of the gate; never the
## mine.
func target_hot(target: int) -> bool:
	if path == null:
		return false
	if SiegeIds.is_weapon(target):
		for e in enemies:
			if e.alive() and in_band(target, e.pos):
				return true
		return false
	if target == SiegeIds.STATION_TAR:
		var reach := content.num("autopilot.tar_engine_m", 60.0) if content != null else 60.0
		for e in enemies:
			if e.alive() and SiegeIds.is_engine(e.type) and path.dist_to_gate(e.prog_m) <= reach:
				return true
	return false


## Live enemies per type code (index = code; the HUD's remaining-enemies line).
func alive_by_type() -> Array[int]:
	var out: Array[int] = [0, 0, 0, 0, 0, 0]
	for e in enemies:
		if e.st != SiegeIds.EN_RETREAT and e.type > 0 and e.type < out.size():
			out[e.type] += 1
	return out


## The docked siege tower, or null.
func docked_tower() -> SiegeEnemyState:
	for e in enemies:
		if e.type == SiegeIds.ENEMY_TOWER and e.st == SiegeIds.EN_DOCKED and e.hp > 0.0:
			return e
	return null


## Spawns waiting under the cap (host: the queue; clients: the snapshot's q).
func queued() -> int:
	return maxi(queue.size(), queue_len)


func in_wave() -> bool:
	return role == SiegeIds.ROLE_WAVE or role == SiegeIds.ROLE_WARMUP_WAVE


## The shop is open in every break, the build break included.
func shop_open() -> bool:
	return role == SiegeIds.ROLE_BREAK or role == SiegeIds.ROLE_BUILD_BREAK


func in_cooldown() -> bool:
	return role == SiegeIds.ROLE_COOLDOWN


func rush_on() -> bool:
	return wave.rush_s > 0.0


# --- The receipt ---------------------------------------------------------------------------------------


## The receipt's line for `item` at `at`, or null.
func receipt_line(item: String, at: int) -> SiegeReceiptLine:
	for line in receipt:
		if line.item == item and line.at == at:
			return line
	return null


## Gold of the rider in `slot` held by their lines on the receipt.
func held_by(slot: int) -> int:
	var n := 0
	for line in receipt:
		if line.slot == slot:
			n += line.cost
	return n


## The receipt's total.
func receipt_total() -> int:
	var n := 0
	for line in receipt:
		n += line.cost
	return n


## What `r` can still put on the receipt: their gold less what it already holds (never below 0).
func spendable(r: SiegeRiderState) -> float:
	return maxf(r.gold - float(held_by(r.slot)), 0.0)


## The slots that vote on the receipt: the riders who are connected (bots always), in slot order.
func voter_slots() -> Array[int]:
	var out: Array[int] = []
	for r in riders:
		if r.connected:
			out.append(r.slot)
	return out


## The vote on `line` as it stands: the connected riders vote, the picker counts yes.
func vote_on(line: SiegeReceiptLine) -> TeamVote:
	return TeamVote.from_wire(voter_slots(), line.no)


## The peers to send an Overdrive directive for, emptied (the module calls it once per tick).
func take_od_requests() -> Array[int]:
	var out := od_requests.duplicate()
	od_requests.clear()
	return out


# --- Serialization (fixtures, debugging) ----------------------------------------------------------------


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["riders"] = riders.map(func(x: SiegeRecord) -> Dictionary: return x.to_dict())
	d["stations"] = stations.map(func(x: SiegeRecord) -> Dictionary: return x.to_dict())
	d["pads"] = pads.map(func(x: SiegeRecord) -> Dictionary: return x.to_dict())
	d["enemies"] = enemies.map(func(x: SiegeRecord) -> Dictionary: return x.to_dict())
	d["projectiles"] = projectiles.map(func(x: SiegeRecord) -> Dictionary: return x.to_dict())
	d["queue"] = queue.map(func(x: SiegeRecord) -> Dictionary: return x.to_dict())
	d["receipt"] = receipt.map(func(x: SiegeRecord) -> Dictionary: return x.to_dict())
	d["tar"] = tar.to_dict()
	d["wave"] = wave.to_dict()
	return d


## A state from to_dict() output (or a JSON fixture). `p_content` is attached (enemy positions
## are recomputed from its path).
static func from_dict(d: Dictionary, p_content: SiegeContent = null) -> SiegeState:
	var s := SiegeState.new()
	s.load_dict(d)
	s.content = p_content
	s.path = p_content.path if p_content != null else null
	for x: Variant in d.get("riders", []):
		s.riders.append(SiegeRiderState.new().load_dict(x) as SiegeRiderState)
	for x: Variant in d.get("stations", []):
		s.stations.append(SiegeStationState.new().load_dict(x) as SiegeStationState)
	for x: Variant in d.get("pads", []):
		s.pads.append(SiegePadState.new().load_dict(x) as SiegePadState)
	for x: Variant in d.get("enemies", []):
		s.enemies.append(SiegeEnemyState.new().load_dict(x) as SiegeEnemyState)
	for x: Variant in d.get("projectiles", []):
		s.projectiles.append(SiegeProjectile.new().load_dict(x) as SiegeProjectile)
	for x: Variant in d.get("queue", []):
		s.queue.append(SiegeSpawn.new().load_dict(x) as SiegeSpawn)
	for x: Variant in d.get("receipt", []):
		s.receipt.append(SiegeReceiptLine.new().load_dict(x) as SiegeReceiptLine)
	if d.get("tar") is Dictionary:
		s.tar.load_dict(d["tar"])
	if d.get("wave") is Dictionary:
		s.wave.load_dict(d["wave"])
	s.init_fixed()
	if s.path != null:
		for e in s.enemies:
			e.place(s.path)
	return s
