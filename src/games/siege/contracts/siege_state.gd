class_name SiegeState
extends SiegeRecord
## The whole Generator Siege game state (G0 contract). The rules (B1, SiegeRules.step) mutate
## it on the host; the module (B2) encodes it into snapshots (SiegeSnapshot) and clients rebuild
## the snapshot part from them; the view and HUD (B3) only read it; the headless sim (B4) drives
## it directly. Deterministic: every random draw goes through `rng` (ctx.rng on the host), and
## every list is kept in a fixed order (riders by slot, pads by number, enemies by spawn).
##
## Fields marked [snap] travel in the 10 Hz snapshot (SiegeSnapshotSchema); everything else is
## host-only bookkeeping (a client keeps its last value or what its events told it).

## Validated content (not serialized).
var content: SiegeContent = null
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
## Pads 1..8 at index pad - 1, always PAD_COUNT entries.
var pads: Array[SiegeTowerState] = []
var enemies: Array[SiegeEnemyState] = []
var zones: Array[SiegeZoneState] = []
## Shots of the last 0.1 s (visuals only).
var shots: Array[SiegeShot] = []
## [snap] (q = size) Spawns waiting for room under the cap.
var queue: Array[SiegeSpawn] = []
## Clients: the snapshot's q (they have no queue entries). Read queued() instead of either.
var queue_len: int = 0
var next_enemy_id: int = 1
var wave: SiegeWaveState = SiegeWaveState.new()

# --- Gate (brief 2.4 "Gate and Breach") --------------------------------------------------------------
## [snap] gate [hp, max, breach_ms]
var gate_hp: float = 100.0
var gate_max: float = 100.0
## Seconds left of a Breach (every tower and perk stops; arrivals vanish; rams pause).
var breach_s: float = 0.0
## [snap] (nb)
var breaches: int = 0
## [snap] (ib) Iron bands bought (0..2): the shop's price and the gate view's bands.
var iron_bands: int = 0

# --- Team economy ------------------------------------------------------------------------------------
## [snap] (gl) Generator level 0..3 (+20% denarii each).
var gen_level: int = 0
## [snap] (pk) SiegeIds.PERK_* bought (team, once each).
var perks: Array[int] = []
var bounty_scale: float = 1.0
## [snap] (w) Team raw watts, a 1 s mean (the drum).
var team_w: float = 0.0
## The last 20 ticks of the team's raw watts (the mean's window).
var team_w_window: Array[float] = []

# --- Results (brief 2.8) ------------------------------------------------------------------------------
## Gate HP and HP / max at each wave end (waves 1..N; the warm-up excluded).
var wave_gate_hp: Array[int] = []
var wave_gate_frac: Array[float] = []
## Leaks and gate damage by road over waves 1..N.
var leaks_by_road: Array[int] = [0, 0, 0]
## [snap] (gd, in 0.1 HP) Gate damage by road over waves 1..N: the shop's "road with the most gate
## damage" (Autopilot and the HUD's recommendation, brief 2.5). Compare roads with gate_damage_dm().
var gate_damage_by_road: Array[float] = [0.0, 0.0, 0.0]
## [snap] (gt) Per road, a bit mask over the enemy types that damaged the gate there over waves
## 1..N (bit 1 << SiegeIds.ENEMY_*): Autopilot's build type reads it (brief 2.5).
var gate_damage_types_by_road: Array[int] = [0, 0, 0]
var rams_total: int = 0
var rams_stopped: int = 0
## Team denarii earned (generator + bounties) from the warm-up to the last wave.
var team_earned: float = 0.0
## The team's planned P_eff in kJ from the warm-up to the last wave (par = 0.75 x it).
var planned_kj: float = 0.0

## Peers whose Overdrive the rules started this tick (OD_PENDING): the module sends each one's
## directive and resolves it (SiegeOverdrive.on_request_result) in the same sim_step.
var od_requests: Array[int] = []


## A fresh state at the session start (brief 2.4): every rider on the generator with the
## starting denarii, pads empty except the starting towers (pad 3 Ballista, pad 4 Scorpion),
## the gate at full HP. `slots` in slot order (ctx.players).
static func create(
	p_content: SiegeContent,
	slots: Array[PlayerSlot],
	p_scaling_mode: String,
	p_rng: RandomNumberGenerator
) -> SiegeState:
	var s := SiegeState.new()
	s.content = p_content
	s.rng = p_rng
	s.shift_id = p_content.shift_id
	s.scaling_mode = p_scaling_mode
	var start := p_content.num("start_denarii", 40.0)
	for p in slots:
		var r := SiegeRiderState.new()
		r.slot = p.slot_index
		r.peer = p.peer_id
		r.is_bot = p.is_bot
		r.autopilot = p.autopilot or p.is_bot
		r.ftp = p.ftp
		r.ftp_verified = p.ftp_verified
		r.denarii = start
		s.riders.append(r)
	for n in range(1, SiegeIds.PAD_COUNT + 1):
		var tw := SiegeTowerState.new()
		tw.pad = n
		s.pads.append(tw)
	for st: Variant in p_content.towers.get("start", []):
		var tw := s.pad(int(st["pad"]))
		tw.type = SiegeIds.tower_code(str(st["type"]))
		tw.cd_s = float(p_content.tower_def(tw.type).get("interval_s", 1.0))
	s.gate_max = p_content.num("gate.hp", 100.0)
	s.gate_hp = s.gate_max
	s.bounty_scale = p_content.num("bounty_scale", 1.0)
	s.waves_total = SiegePlanBuilder.wave_count(p_content.shift)
	return s


# --- Lookups -----------------------------------------------------------------------------------------


## Records `applied` HP of gate damage by an enemy of `type` on `road` (waves only; the combat
## calls it where it adds to gate_damage_by_road).
func note_gate_damage(road: int, type: int, applied: float) -> void:
	if road < 0 or road >= gate_damage_by_road.size():
		return
	gate_damage_by_road[road] += applied
	if applied > 0.0:
		gate_damage_types_by_road[road] |= 1 << type


## Gate damage on `road` in 0.1 HP, the resolution the snapshot carries: a client and the host
## rank the roads identically through it.
func gate_damage_dm(road: int) -> int:
	return roundi(gate_damage_by_road[road] * 10.0)


## True when an enemy of `type` has damaged the gate on `road` over waves 1..N.
func gate_damaged_by(road: int, type: int) -> bool:
	return (gate_damage_types_by_road[road] & (1 << type)) != 0


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


## Pad 1..8.
func pad(n: int) -> SiegeTowerState:
	return pads[n - 1]


func built_pads() -> Array[int]:
	var out: Array[int] = []
	for tw in pads:
		if tw.built():
			out.append(tw.pad)
	return out


## The live enemy with `id`, or null.
func enemy(id: int) -> SiegeEnemyState:
	for e in enemies:
		if e.id == id:
			return e
	return null


## Riders routed to `target` (reconnecting ones included): the 2-rider limit counts these.
func routed_count(target: int) -> int:
	var n := 0
	for r in riders:
		if r.target == target:
			n += 1
	return n


## Riders whose output reaches `target` now (SiegeRiderState.delivering()), in slot order.
func riders_on(target: int) -> Array[SiegeRiderState]:
	var out: Array[SiegeRiderState] = []
	for r in riders:
		if r.target == target and r.delivering():
			out.append(r)
	return out


## A built pad's reach in metres: its tower's range_m (the Caltrop thrower's throw range), x1.25
## from upgrade 2. 0 for an empty pad.
func tower_range_m(n: int) -> float:
	var tw := pad(n)
	if not tw.built() or content == null:
		return 0.0
	var r := float(content.tower_def(tw.type).get("range_m", 0.0))
	return r * 1.25 if tw.level >= 2 else r


## Enemy HP within reach of pad `n` (Autopilot's routing measure, brief 2.5). Retreating enemies
## don't count.
func enemy_hp_in_range(n: int) -> float:
	var reach := tower_range_m(n)
	if reach <= 0.0 or content == null or content.map == null:
		return 0.0
	var at := content.map.pad_pos(n)
	var r2 := reach * reach
	var hp := 0.0
	for e in enemies:
		if e.st != SiegeIds.EN_RETREAT and e.pos.distance_squared_to(at) <= r2:
			hp += e.hp
	return hp


## The Overdrive prompt's "their target has an enemy in range": a built pad with enemy HP in reach.
func target_hot(target: int) -> bool:
	return SiegeIds.is_pad(target) and enemy_hp_in_range(target) > 0.0


## Live enemies per type code (index = code; the HUD's remaining-enemies line).
func alive_by_type() -> Array[int]:
	var out: Array[int] = [0, 0, 0, 0, 0]
	for e in enemies:
		if e.st != SiegeIds.EN_RETREAT:
			out[e.type] += 1
	return out


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


## The peers to send an Overdrive directive for, emptied (the module calls it once per tick).
func take_od_requests() -> Array[int]:
	var out := od_requests.duplicate()
	od_requests.clear()
	return out


# --- Serialization (fixtures, debugging) ----------------------------------------------------------------


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["riders"] = riders.map(func(x: SiegeRecord) -> Dictionary: return x.to_dict())
	d["pads"] = pads.map(func(x: SiegeRecord) -> Dictionary: return x.to_dict())
	d["enemies"] = enemies.map(func(x: SiegeRecord) -> Dictionary: return x.to_dict())
	d["zones"] = zones.map(func(x: SiegeRecord) -> Dictionary: return x.to_dict())
	d["shots"] = shots.map(func(x: SiegeRecord) -> Dictionary: return x.to_dict())
	d["queue"] = queue.map(func(x: SiegeRecord) -> Dictionary: return x.to_dict())
	d["wave"] = wave.to_dict()
	return d


## A state from to_dict() output (or a JSON fixture). `p_content` is attached (positions of
## enemies and zones are recomputed from it when it has a map).
static func from_dict(d: Dictionary, p_content: SiegeContent = null) -> SiegeState:
	var s := SiegeState.new()
	s.load_dict(d)
	s.content = p_content
	for x: Variant in d.get("riders", []):
		s.riders.append(SiegeRiderState.new().load_dict(x) as SiegeRiderState)
	for x: Variant in d.get("pads", []):
		s.pads.append(SiegeTowerState.new().load_dict(x) as SiegeTowerState)
	for x: Variant in d.get("enemies", []):
		s.enemies.append(SiegeEnemyState.new().load_dict(x) as SiegeEnemyState)
	for x: Variant in d.get("zones", []):
		s.zones.append(SiegeZoneState.new().load_dict(x) as SiegeZoneState)
	for x: Variant in d.get("shots", []):
		s.shots.append(SiegeShot.new().load_dict(x) as SiegeShot)
	for x: Variant in d.get("queue", []):
		s.queue.append(SiegeSpawn.new().load_dict(x) as SiegeSpawn)
	if d.get("wave") is Dictionary:
		s.wave.load_dict(d["wave"])
	while s.pads.size() < SiegeIds.PAD_COUNT:
		var tw := SiegeTowerState.new()
		tw.pad = s.pads.size() + 1
		s.pads.append(tw)
	if p_content != null and p_content.map != null:
		for e in s.enemies:
			e.place(p_content.map)
		for z in s.zones:
			z.pos = p_content.map.point_at(z.road, z.prog_m)
	return s
