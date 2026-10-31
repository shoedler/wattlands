class_name GameAudioKit
extends Node
## The Node a game talks to (SPEC_AUDIO 1.3): the only class that owns players. A game's adapter calls drive() once per
## frame for each machine, with the `revs` and `rpm` its view draws with, then commit(). Audio never integrates cadence.
## Silent in headless runs and at --sim-speed other than 1: no player, no stream, no error, and every record still kept.
## Sync: every locked file starts with 80 ms of silence. Strokes are planned one horizon ahead and the player starts at
## once from a seek into that silence, which becomes the sub-frame delay (SPEC_AUDIO 2.4; tools/audio/jitter_bench.gd
## measures it). What this cannot do: FTMS reports cadence about once a second, not crank angle (BRIEF 4.5), so the
## sound locks to the on-screen crank exactly and to the rider's feet in rate only.
const PREROLL_S := 0.080
## One mix step of silence always stays before the attack, in case the first mix step of a new playback ramps up.
const ATTACK_GUARD_S := 0.012
const HORIZON_MIN_S := 0.012
const HORIZON_MAX_S := 0.050
const LOCKED_PITCH_MIN := 0.8
const LOCKED_PITCH_MAX := 1.2
const PITCH_MIN := 0.05
const PITCH_MAX := 4.0
const PLAYED_MAX := 4096
const FRAME_ALPHA := 0.1
const NO_LEAD_RISE_DB := 4.0
const OTHER_PRIORITY := 3
const SPOT_PRIORITY := 2
const CUE_PRIORITY := 6
## A cue's duck that leaves these out (SPEC_AUDIO 5, the same defaults as the offline preview).
const DUCK_ATTACK_S := 0.01
const DUCK_RELEASE_S := 0.35
const PAUSE_BED_DB := -9.0
const PAUSE_BED_DB_PER_S := 30.0
const BED_FADE_IN_FROM_DB := -30.0
const BED_FADE_DB_PER_S := 40.0
## Tests read these. Record even when silent.
var silent: bool = true  ## headless, or --sim-speed != 1, or no bank
var force_audio: bool = false  ## the jitter bench only; set before setup()
var preroll_on: bool = true  ## the jitter bench only: false starts every stroke at PREROLL_S, its baseline
## Base sound ids (never the variant file), newest last, when started; thinned strokes are not recorded; a loop once on
## each off-to-on.
var played: Array[String] = []
var played_db: Array[float] = []
var played_t: Array[float] = []  ## kit time the attack is due
var thinned: int = 0
var voiceless: int = 0  ## strokes and events that found no voice to start on (a full pool, nothing it may steal)

var _bank: AudioBank = null
var _seed: int = 0
var _t: float = 0.0
var _frame_s: float = 0.0
var _paused: bool = false
var _machines: Dictionary = {}
var _entries: Dictionary = {}
var _bed: BedSlot = null
var _bed_id: String = ""
var _old_beds: Array[BedSlot] = []
var _bed_params: Dictionary = {}
var _bed_pause_db: float = 0.0
var _pending: Array[Dictionary] = []
var _variant: Dictionary = {}
var _warned: Dictionary = {}
var _last_other_t: float = -INF
var _pools: Dictionary = {}
var _loop_used: int = 0
var _loop_free: Array[AudioStreamPlayer] = []
var _loop_count: int = 0


## One player in a voice pool.
class Voice:
	var player: AudioStreamPlayer
	var priority: int = 0
	var lead: bool = true
	var started: float = 0.0


## The layers of one machine, one `loops` entry or one bed, and the pool slots they hold.
class LoopSet:
	var loop: LayeredLoop
	var bus: String
	var lead: bool = true
	var players: Array[AudioStreamPlayer] = []
	var granted: PackedByteArray = PackedByteArray()
	var denied: PackedByteArray = PackedByteArray()

	func _init(p_loop: LayeredLoop, p_bus: String) -> void:
		loop = p_loop
		bus = p_bus
		players.resize(p_loop.count)
		granted.resize(p_loop.count)
		granted.fill(0)
		denied.resize(p_loop.count)
		denied.fill(0)


## One driven instance of a bank machine.
class MachineSlot:
	var machine: String
	var bus: String
	var voice: CadenceVoice
	var loops: LoopSet
	var revs: float = 0.0
	var rpm: float = 0.0
	var params: Dictionary = {}
	var lead: bool = false
	var driven: bool = false
	var stopping: bool = false


## A `loops` entry.
class EntrySlot:
	var loops: LoopSet
	var params: Dictionary = {}
	var wanted: bool = false


## The bed playing or fading out.
class BedSlot:
	var bed: AmbienceBed
	var loops: LoopSet
	var fade_db: float = BED_FADE_IN_FROM_DB


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	stop_all()


func setup(bank_path: String, p_seed: int) -> bool:
	return setup_bank(AudioBank.load_bank(bank_path), p_seed)


## The same, from a bank already built (tests, the jitter bench).
func setup_bank(bank: AudioBank, p_seed: int) -> bool:
	stop_all()
	AudioBuses.ensure()
	_bank = bank
	_seed = p_seed
	_connect_pause()
	silent = bank == null or (_quiet_run() and not force_audio)
	if bank == null:
		return false
	if _pools.is_empty():
		_pools = {
			AudioBuses.MACHINES: [] as Array[Voice],
			AudioBuses.SFX: [] as Array[Voice],
			AudioBuses.AMBIENCE: [] as Array[Voice],
		}
	if not silent:
		# A lazy load() on the first stroke would hitch the frame the sync depends on.
		for id: String in bank.sounds:
			for v in bank.variants(id):
				bank.stream(id, v)
	return true


func drive(
	instance: String, machine: String, revs: float, rpm: float, params: Dictionary, lead: bool
) -> void:
	if _bank == null:
		return
	if not _bank.machines.has(machine):
		_warn_once("machine:" + machine, "GameAudioKit: unknown machine '%s'" % machine)
		return
	var slot: MachineSlot = _machines.get(instance)
	if slot == null or slot.machine != machine:
		if slot != null:
			_release_set(slot.loops)
		slot = _new_machine(machine)
		_machines[instance] = slot
	slot.revs = revs
	slot.rpm = rpm
	slot.params = params.duplicate()
	slot.params["rpm"] = rpm
	slot.lead = lead
	slot.driven = true
	slot.stopping = false


func stop_machine(instance: String) -> void:
	var slot: MachineSlot = _machines.get(instance)
	if slot != null:
		slot.stopping = true
		slot.driven = false


## A "loops" entry; call each frame while wanted.
func set_loop(id: String, params: Dictionary, lead: bool = true) -> void:
	if _bank == null:
		return
	if not _bank.loops.has(id):
		_warn_once("loop:" + id, "GameAudioKit: unknown loop '%s'" % id)
		return
	var slot: EntrySlot = _entries.get(id)
	if slot == null:
		var entry: Dictionary = _bank.loops[id]
		slot = EntrySlot.new()
		slot.loops = LoopSet.new(
			LayeredLoop.new(entry.get("layers", [])), str(entry.get("bus", AudioBuses.SFX))
		)
		_entries[id] = slot
	slot.params = params
	slot.loops.lead = lead
	slot.wanted = true


## Crossfades to `bed_id`; "" fades the bed out.
func set_bed(bed_id: String) -> void:
	if _bank == null or bed_id == _bed_id:
		return
	if bed_id != "" and not _bank.beds.has(bed_id):
		_warn_once("bed:" + bed_id, "GameAudioKit: unknown bed '%s'" % bed_id)
		return
	if _bed != null:
		_old_beds.append(_bed)
	_bed = null
	_bed_id = bed_id
	if bed_id != "":
		var spec: Dictionary = _bank.beds[bed_id]
		_bed = BedSlot.new()
		_bed.bed = AmbienceBed.new(spec, SeededRng.derive(_seed, "audio_bed:" + bed_id))
		_bed.loops = LoopSet.new(_bed.bed.loops, AudioBuses.AMBIENCE)


func bed_params(params: Dictionary) -> void:
	_bed_params = params


## An unknown name: push_warning once, no error. lead false adds the cue's other_db, else mix.other_db.
func cue(cue_name: String, vars: Dictionary = {}, lead: bool = true) -> void:
	if _bank == null:
		return
	if not _bank.cues.has(cue_name):
		_warn_once("cue:" + cue_name, "GameAudioKit: unknown cue '%s'" % cue_name)
		return
	var c: Dictionary = _bank.cues[cue_name]
	var trim := 0.0 if lead else float(c.get("other_db", _bank.mix["other_db"]))
	for hit: Dictionary in c.get("hits", []):
		_cue_hit(hit, vars, trim, lead)
	if lead:
		for d: Dictionary in c.get("duck", []):
			AudioBuses.duck(
				str(d.get("bus", "")),
				float(d.get("db", 0.0)),
				float(d.get("attack_s", DUCK_ATTACK_S)),
				float(d.get("release_s", DUCK_RELEASE_S))
			)


func sound(
	sound_id: String, db: float = 0.0, pitch: float = 1.0, bus: String = AudioBuses.SFX
) -> void:
	if _bank == null:
		return
	if not _bank.sounds.has(sound_id):
		_warn_once("sound:" + sound_id, "GameAudioKit: unknown sound '%s'" % sound_id)
		return
	_fire(sound_id, _next_variant(sound_id), db, pitch, bus, CUE_PRIORITY, true)


## Exactly once per frame, after every drive().
func commit(dt: float) -> void:
	_t += dt
	_frame_s = dt if _frame_s <= 0.0 else lerpf(_frame_s, dt, FRAME_ALPHA)
	if _bank == null:
		return
	var horizon := clampf(1.5 * _frame_s, HORIZON_MIN_S, HORIZON_MAX_S)
	var strokes := _drive_machines(horizon, dt)
	strokes.sort_custom(_sooner)
	_start_strokes(strokes)
	_commit_entries(dt)
	_run_pending(dt)
	_update_beds(dt)


func clear_played() -> void:
	played.clear()
	played_db.clear()
	played_t.clear()


## Also on _exit_tree.
func stop_all() -> void:
	for pool: Array[Voice] in _pools.values():
		for v: Voice in pool:
			v.player.stop()
	for slot: MachineSlot in _machines.values():
		_release_set(slot.loops)
	for slot: EntrySlot in _entries.values():
		_release_set(slot.loops)
	if _bed != null:
		_release_set(_bed.loops)
	for b: BedSlot in _old_beds:
		_release_set(b.loops)
	_machines.clear()
	_entries.clear()
	_bed = null
	_bed_id = ""
	_old_beds.clear()
	_pending.clear()


## The voice of a driven instance, null when there is none (tests).
func machine_voice(instance: String) -> CadenceVoice:
	var slot: MachineSlot = _machines.get(instance)
	return slot.voice if slot != null else null


## The layers of a driven instance, null when there is none (tests).
func machine_loop(instance: String) -> LayeredLoop:
	var slot: MachineSlot = _machines.get(instance)
	return slot.loops.loop if slot != null else null


## The layers of a `loops` entry, null before its first set_loop (tests).
func entry_loop(id: String) -> LayeredLoop:
	var slot: EntrySlot = _entries.get(id)
	return slot.loops.loop if slot != null else null


## The running bed, null when there is none (tests).
func current_bed() -> AmbienceBed:
	return _bed.bed if _bed != null else null


## Pool slots in use by loops at this moment (tests).
func loops_in_use() -> int:
	return _loop_used


func _quiet_run() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	return not is_equal_approx(CmdLine.get_float("sim-speed", 1.0), 1.0)


func _connect_pause() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var bus: Node = tree.root.get_node_or_null("EventBus") if tree != null else null
	if bus != null and not bus.is_connected("paused_changed", _on_paused_changed):
		bus.connect("paused_changed", _on_paused_changed)


func _on_paused_changed(paused: bool, _reason: String) -> void:
	_paused = paused


func _new_machine(machine: String) -> MachineSlot:
	var doc: Dictionary = _bank.machines[machine]
	var slot := MachineSlot.new()
	slot.machine = machine
	slot.bus = str(doc.get("bus", AudioBuses.MACHINES))
	slot.voice = CadenceVoice.new(doc.get("events", []))
	slot.loops = LoopSet.new(LayeredLoop.new(doc.get("loops", [])), slot.bus)
	return slot


func _drive_machines(horizon: float, dt: float) -> Array[Dictionary]:
	var has_lead := false
	var others := 0
	for slot: MachineSlot in _machines.values():
		if slot.driven:
			has_lead = has_lead or slot.lead
			others += 0 if slot.lead else 1
	var other_trim := _other_trim(others, has_lead)
	var strokes: Array[Dictionary] = []
	for instance: String in _machines.keys():
		var slot: MachineSlot = _machines[instance]
		if not slot.driven:
			slot.loops.loop.close(dt)
			_sync_loops(slot.loops)
			if slot.stopping and slot.loops.loop.all_off():
				_release_set(slot.loops)
				_machines.erase(instance)
			continue
		slot.driven = false
		var trim := 0.0 if slot.lead else other_trim
		slot.loops.lead = slot.lead
		if _paused or slot.rpm <= CrankClock.STOP_RPM:
			slot.loops.loop.close(dt)
		else:
			slot.loops.loop.update(slot.params, trim, slot.lead, dt)
		_sync_loops(slot.loops)
		var rpm := 0.0 if _paused else slot.rpm
		for ev: Dictionary in slot.voice.plan(slot.revs, rpm, horizon, slot.params, slot.lead):
			ev["lead"] = slot.lead
			ev["bus"] = slot.bus
			ev["db"] = float(ev["db"]) + trim
			if not slot.lead:
				ev["priority"] = mini(int(ev["priority"]), OTHER_PRIORITY)
			strokes.append(ev)
	return strokes


## mix.other_db, the doubling for more than two others, and +4 dB when no one here leads (no seat, a spectator).
func _other_trim(others: int, has_lead: bool) -> float:
	var trim := float(_bank.mix["other_db"])
	if others > 2:
		trim += float(_bank.mix["other_doubling_db"]) * log(others / 2.0) / log(2.0)
	return trim + (0.0 if has_lead else NO_LEAD_RISE_DB)


## Sorted by at_s. Lead strokes always pass. Non-lead strokes pass only with mix.other_min_gap_s since the last one:
## first come in at_s order, so thinning is deterministic.
func _start_strokes(strokes: Array[Dictionary]) -> void:
	var gap := float(_bank.mix["other_min_gap_s"])
	for ev: Dictionary in strokes:
		var at_s: float = ev["at_s"]
		var at := _t + at_s
		var lead: bool = ev["lead"]
		if not lead:
			if at - _last_other_t < gap:
				thinned += 1
				continue
			_last_other_t = at
		var id: String = ev["sound"]
		_record(id, float(ev["db"]), at)
		if silent:
			continue
		var stream := _bank.stream(id, int(ev["variant"]))
		if stream != null:
			_start_locked(
				stream,
				at_s,
				float(ev["db"]),
				float(ev["pitch"]),
				str(ev["bus"]),
				int(ev["priority"]),
				lead
			)


## Starting a locked stroke, the sub-frame step (SPEC_AUDIO 2.4). Godot has no scheduled play: play() takes effect on
## the next mix step, so the file's own silence is the delay. The guard shifts every stroke equally: it is not jitter.
func _start_locked(
	stream: AudioStream,
	at_s: float,
	db: float,
	pitch: float,
	bus: String,
	priority: int = CUE_PRIORITY,
	lead: bool = true
) -> void:
	var p := clampf(pitch, LOCKED_PITCH_MIN, LOCKED_PITCH_MAX)
	var wait := maxf(at_s - AudioServer.get_time_to_next_mix(), 0.0)
	var from := clampf(PREROLL_S - (wait + ATTACK_GUARD_S) * p, 0.0, PREROLL_S)
	if not preroll_on:
		from = PREROLL_S
	var player := _voice(bus, priority, lead)
	if player == null:
		voiceless += 1
		return
	player.stream = stream
	player.bus = bus
	player.volume_db = db
	player.pitch_scale = p
	player.play(from)


func _start_plain(
	stream: AudioStream,
	db: float,
	pitch: float,
	bus: String,
	priority: int,
	lead: bool,
) -> void:
	var player := _voice(bus, priority, lead)
	if player == null:
		voiceless += 1
		return
	player.stream = stream
	player.bus = bus
	player.volume_db = db
	player.pitch_scale = clampf(pitch, PITCH_MIN, PITCH_MAX)
	player.play(0.0)


func _fire(
	id: String, variant: int, db: float, pitch: float, bus: String, priority: int, lead: bool
) -> void:
	_record(id, db, _t)
	if silent:
		return
	var stream := _bank.stream(id, variant)
	if stream == null:
		return
	if _bank.is_locked(id):
		_start_locked(stream, 0.0, db, pitch, bus, priority, lead)
	else:
		_start_plain(stream, db, pitch, bus, priority, lead)


func _cue_hit(hit: Dictionary, vars: Dictionary, trim: float, lead: bool) -> void:
	var delay := float(hit.get("delay_s", 0.0)) + _var(vars, hit.get("delay_var", ""), 0.0)
	var pitch := float(hit.get("pitch", 1.0)) * _var(vars, hit.get("pitch_var", ""), 1.0)
	var db := float(hit.get("db", 0.0)) + _var(vars, hit.get("db_var", ""), 0.0) + trim
	var id := str(hit.get("sound", ""))
	var bus := str(hit.get("bus", AudioBuses.SFX))
	var priority := int(hit.get("priority", CUE_PRIORITY))
	var variant := _next_variant(id)
	if delay <= 0.0:
		_fire(id, variant, db, pitch, bus, priority, lead)
		return
	var entry := {
		"left": delay,
		"sound": id,
		"variant": variant,
		"db": db,
		"pitch": pitch,
		"bus": bus,
		"priority": priority,
		"lead": lead,
	}
	_pending.append(entry)


func _var(vars: Dictionary, key: Variant, fallback: float) -> float:
	var k := str(key)
	return float(vars[k]) if k != "" and vars.has(k) else fallback


func _next_variant(id: String) -> int:
	var v: int = _variant.get(id, 0)
	_variant[id] = v + 1
	return v


## Delayed cues are held while paused. A bed spot's follow-ups are not: the bed plays on under the pause, on its own
## timers, so holding them would only save up its bursts for the moment the road is silent on resume (SPEC_AUDIO 2.5).
func _run_pending(dt: float) -> void:
	if _pending.is_empty():
		return
	var keep: Array[Dictionary] = []
	for p: Dictionary in _pending:
		if _paused and not p.has("spot"):
			keep.append(p)
			continue
		p["left"] = float(p["left"]) - dt
		if float(p["left"]) > 0.0:
			keep.append(p)
			continue
		_fire(
			p["sound"],
			p["variant"],
			p["db"],
			p["pitch"],
			p["bus"],
			p["priority"],
			p["lead"],
		)
	_pending = keep


## Paused, they close like a machine's loops, whatever the adapter still asks for: its view keeps running under a pause.
func _commit_entries(dt: float) -> void:
	for id: String in _entries.keys():
		var slot: EntrySlot = _entries[id]
		if slot.wanted and not _paused:
			var trim := 0.0 if slot.loops.lead else float(_bank.mix["other_db"])
			slot.loops.loop.update(slot.params, trim, slot.loops.lead, dt)
		else:
			slot.loops.loop.close(dt)
		slot.wanted = false
		_sync_loops(slot.loops)


func _update_beds(dt: float) -> void:
	var target := PAUSE_BED_DB if _paused else 0.0
	_bed_pause_db = move_toward(_bed_pause_db, target, PAUSE_BED_DB_PER_S * dt)
	for i in range(_old_beds.size() - 1, -1, -1):
		var old := _old_beds[i]
		old.fade_db = move_toward(old.fade_db, LayeredLoop.OFF_DB, BED_FADE_DB_PER_S * dt)
		old.bed.loops.update(_bed_params, old.fade_db + _bed_pause_db, true, dt)
		_sync_loops(old.loops)
		if old.fade_db <= LayeredLoop.OFF_DB and old.bed.loops.all_off():
			_release_set(old.loops)
			_old_beds.remove_at(i)
	if _bed == null:
		return
	_bed.fade_db = move_toward(_bed.fade_db, 0.0, BED_FADE_DB_PER_S * dt)
	_bed.bed.trim_db = _bed.fade_db + _bed_pause_db
	for spot: Dictionary in _bed.bed.update(_bed_params, dt):
		_bed_spot(spot)
	_sync_loops(_bed.loops)


func _bed_spot(spot: Dictionary) -> void:
	var at_s: float = spot["at_s"]
	if at_s > 0.0:
		var entry := {
			"left": at_s,
			"sound": spot["sound"],
			"variant": spot["variant"],
			"db": spot["db"],
			"pitch": spot["pitch"],
			"bus": AudioBuses.AMBIENCE,
			"priority": SPOT_PRIORITY,
			"lead": true,
			"spot": true,
		}
		_pending.append(entry)
		return
	_fire(
		spot["sound"],
		spot["variant"],
		spot["db"],
		spot["pitch"],
		AudioBuses.AMBIENCE,
		SPOT_PRIORITY,
		true
	)


## The pure layer state onto pool slots and players. The instance count is not known at setup, so the cap is enforced
## here: a non-lead layer that finds the pool full stays off (thinned + 1); a lead layer takes a non-lead's player.
func _sync_loops(group: LoopSet) -> void:
	var loop := group.loop
	for i in loop.count:
		var wants := loop.on[i] != 0
		if not wants:
			group.denied[i] = 0
			if group.granted[i] != 0:
				_release_layer(group, i)
			continue
		if group.granted[i] == 0 and not _grant_layer(group, i):
			continue
		var player := group.players[i]
		if player != null:
			player.volume_db = loop.db[i]
			player.pitch_scale = clampf(loop.pitch[i], PITCH_MIN, PITCH_MAX)


func _grant_layer(group: LoopSet, i: int) -> bool:
	var limit := int(_bank.mix["max_loop_players"])
	if _loop_used >= limit and not (group.lead and _steal_loop()):
		if group.denied[i] == 0:
			group.denied[i] = 1
			thinned += 1
		return false
	_loop_used += 1
	group.granted[i] = 1
	group.denied[i] = 0
	var layer := group.loop.layer(i)
	var id := str(layer.get("sound", ""))
	_record(id, group.loop.db[i], _t)
	if silent:
		return true
	var stream := _bank.stream(id, 0)
	if stream == null:
		return true
	var player := _take_loop_player()
	player.stream = stream
	player.bus = group.bus
	player.volume_db = group.loop.db[i]
	player.pitch_scale = clampf(group.loop.pitch[i], PITCH_MIN, PITCH_MAX)
	player.play(0.0)
	group.players[i] = player
	return true


func _steal_loop() -> bool:
	for slot: MachineSlot in _machines.values():
		if slot.lead:
			continue
		for i in slot.loops.loop.count:
			if slot.loops.granted[i] != 0:
				_release_layer(slot.loops, i)
				slot.loops.denied[i] = 1
				thinned += 1
				return true
	return false


func _release_layer(group: LoopSet, i: int) -> void:
	group.granted[i] = 0
	_loop_used -= 1
	var player := group.players[i]
	if player != null:
		player.stop()
		_loop_free.append(player)
		group.players[i] = null


func _release_set(group: LoopSet) -> void:
	for i in group.loop.count:
		if group.granted[i] != 0:
			_release_layer(group, i)


func _take_loop_player() -> AudioStreamPlayer:
	if not _loop_free.is_empty():
		return _loop_free.pop_back()
	var player := AudioStreamPlayer.new()
	player.name = "Loop%d" % _loop_count
	_loop_count += 1
	add_child(player)
	return player


## Ambience spots, Sfx and UI, or the machines' pool (which a bench's own bus also uses).
func _pool_key(bus: String) -> String:
	if bus == AudioBuses.AMBIENCE:
		return AudioBuses.AMBIENCE
	return AudioBuses.SFX if bus == AudioBuses.SFX or bus == AudioBuses.UI else AudioBuses.MACHINES


func _pool_cap(key: String) -> int:
	match key:
		AudioBuses.AMBIENCE:
			return int(_bank.mix["spot_voices"])
		AudioBuses.SFX:
			return int(_bank.mix["sfx_voices"])
	return int(_bank.mix["machine_voices"])


func _voice(bus: String, priority: int, lead: bool) -> AudioStreamPlayer:
	var key := _pool_key(bus)
	var pool: Array[Voice] = _pools[key]
	var chosen: Voice = null
	for v: Voice in pool:
		if not v.player.playing:
			chosen = v
			break
	if chosen == null and pool.size() < _pool_cap(key):
		chosen = Voice.new()
		chosen.player = AudioStreamPlayer.new()
		chosen.player.name = "%s%d" % [key, pool.size()]
		add_child(chosen.player)
		pool.append(chosen)
	if chosen == null and key != AudioBuses.AMBIENCE:  # bed spots are dropped if the spot pool is full
		chosen = _steal_voice(pool, priority, lead)
	if chosen == null:
		return null
	chosen.priority = priority
	chosen.lead = lead
	chosen.started = _t
	return chosen.player


## Oldest voice of lowest priority on that bus; never a higher priority, and a lead stroke never for a non-lead one.
func _steal_voice(pool: Array[Voice], priority: int, lead: bool) -> Voice:
	var best: Voice = null
	for v: Voice in pool:
		if v.priority > priority or (v.lead and not lead):
			continue
		if (
			best == null
			or v.priority < best.priority
			or (v.priority == best.priority and v.started < best.started)
		):
			best = v
	return best


func _record(id: String, db: float, at: float) -> void:
	played.append(id)
	played_db.append(db)
	played_t.append(at)
	if played.size() > PLAYED_MAX:
		played.remove_at(0)
		played_db.remove_at(0)
		played_t.remove_at(0)


func _warn_once(key: String, text: String) -> void:
	if not _warned.has(key):
		_warned[key] = true
		push_warning(text)


static func _sooner(a: Dictionary, b: Dictionary) -> bool:
	return float(a["at_s"]) < float(b["at_s"])
