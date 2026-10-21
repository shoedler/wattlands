class_name LocalRider
extends Node
## One rider's trainer stack on this machine (BRIEF 4.1): TrainerDevice -> SafetyGovernor
## -> telemetry, with the GestureRecognizer, W' balance, speed model, effort scaling and the
## ride recorder. One per local human rider and one per bot (bots on the host, with a
## MockTrainer "erg:compliance=1.0" and no recorder). Owned by platform; public API frozen
## after W0. Runs with PROCESS_MODE_ALWAYS and advances only through tick(dt).
##
## Per tick: device.tick(dt) -> new samples feed gestures, W' balance (on raw power), the
## governor (rescue/coasting/warm-up) and the recorder (1 Hz); the speed model integrates
## P_eff on the current applied grade; the governor ticks; telemetry() reflects the latest
## state. Gestures and intents accumulate until taken (take_gestures/take_intents), so a
## 5 Hz telemetry send never loses one.
##
## Details (W1):
## - Time: the rider's platform time starts at 0 in setup() and advances only by tick(dt)
##   (exact microsecond steps). Telemetry.t and every sample handed on are stamped with it:
##   samples queue when the device emits them and are processed in the next tick(), in
##   arrival order, as copies stamped with the rider's time. The governor, the gestures and
##   the recorder therefore share one time base.
## - Per sample: CadenceEstimator.process() -> gestures.set_erg(governor mode is ERG) and
##   gestures.on_sample() -> governor.on_sample(). Per tick: gestures.advance(t) fires the
##   timed gestures (coast, stop_5s, pedal_start) due between samples (W2); W' balance steps on the latest
##   raw power, the trainer-speed distance integrates, the speed model steps on
##   P_eff = power x slot.p_eff_per_w at the governor's applied SIM grade (0 outside SIM),
##   governor.set_course_distance(speed.distance_m), governor.tick(dt), the recorder gets
##   the latest values every tick (RideRecorder keeps one record per second; a cadence or
##   speed the trainer doesn't report, or a stale sample's, is passed as -1 = absent, and a
##   stale sample's power as 0 W), then telemetry_updated.
## - A sample older than STALE_S counts as gone: power, cadence and speed read 0.
## - Telemetry: power_w, cadence_rpm and speed_kmh are the trainer's (raw); effort and
##   p_eff_w follow the session's scaling (p_eff_w == power_w x slot.p_eff_per_w exactly);
##   distance_m integrates the trainer's reported speed; mode, applied_target_w (0 outside
##   ERG), applied_grade_pct (0 outside SIM), gear, clamped_by, rescue, coasting, afk,
##   paused, s_left_105/120 and haptic_pct come from governor.status(); phase_index is the
##   last start_phase(); cadence_age_s counts from the last sample with a cadence.
## - Acks: every directive_applied record from the governor (directives, course grades)
##   is re-emitted and queued for take_acks() as {id, kind, applied, clamped_by, refused
##   (bool), reason, dropped ([{channel, reason}], W2)}; apply_directive() acks exactly once
##   whether or not the governor emits.
## - A stop_5s gesture in a solo session also emits pause_requested("stop_5s"); the
##   governor's own pause_requested (coasting 10 s) is forwarded as is.
## - Bands: set_cadence_band/set_power_band forward to a MockTrainer device and emit
##   cadence_band_changed/power_band_changed on the rider's bus when the band changes. The
##   cool-down clears both.
## - setup() may be called again (for example to turn the menu rider into a session rider):
##   it rebuilds every component around the given device. (W2r2) On the same device object
##   the new governor takes over the old one's trainer-connection state
##   (SafetyGovernor.adopt_connection): the warm-up (BRIEF 4.6.8 counts from the first pedal
##   stroke after the trainer connects, so it continues from the menus into a session and
##   across sessions) and what was last written to the trainer (so the next mode change is
##   ramped from the trainer's real state). (W4) The duration limits and the last ERG/SIM
##   switch carry over the same way (SAF-2, SAF-6). A different device object starts afresh. The
##   device is never freed here; its creator owns it. A ride still recording is finished (stopped and saved) first, with
##   push_warning, so a rebuild never loses a ride. A MockTrainer device gets its bands
##   cleared, its phase reset to -1 and (W2) its profile restarted (restart_profile()), so
##   nothing from an earlier session steers the mock and a profile's at_s, surges, ramps
##   and intervals count from this setup, like the rider's platform time.
## - (W2r2) setup() from inside the rider's own tick (a gesture, sample or governor signal
##   handler, such as a menu pick that starts a session) ends that tick at once: a setup
##   generation counter is read at the start of tick() and checked after every call that can
##   emit, so the rest of the tick never hands the old platform time, sample or gestures to
##   the new governor, gestures or ride (no governor.tick, recorder.record or telemetry).
## - rebind_device(d): a reconnect that hands over a new device object for the same trainer
##   keeps the session (plan, phase, time, queues, recorder) and rebinds the governor and the
##   sample feed to the new object.
## - trainer_reconnected() (W2): the same device object reconnected (FtmsConnectionManager
##   keeps one FtmsTrainer per address, so TrainerService calls this on `reconnected`). The
##   governor restores the last safe mode through its ramped path
##   (SafetyGovernor.on_trainer_reconnected, BRIEF 4.4); everything else is kept.
## - (W4, SAF-1) The rider's own profile is the source of the local human rider's safety
##   values: when setup() gets both a profile and a slot for a human (not a bot), it overwrites
##   the slot's ftp, ftp_verified, haptics_on and haptic_intensity from the profile before
##   configuring the governor (BRIEF 3.3 "ERG targets always come from each rider's own FTP",
##   4.6.7 "each client validates and clamps them locally"). A CLIENT's slot comes from the
##   host's session_start, so the host can never set the client's watt basis, lift the
##   unverified factor or turn opted-out haptics back on; a difference is logged with
##   push_warning. With a null profile the slot is used as given (tests, in-process riders).
## - Lap names: a phase label or lap_marker label that is a strings key is translated (plain
##   text passes through); unlabelled lap phases are CORE_LAP_PHASE, the cool-down
##   CORE_LAP_COOLDOWN.
## - Every set-up rider is listed by LocalRider.live_riders() until shutdown() or freed,
##   so the app can make every trainer safe on exit (BRIEF 4.6.9).

signal telemetry_updated(telemetry: Telemetry)
signal gesture_detected(gesture_name: StringName)
signal rescue_changed(active: bool)
signal afk_changed(afk: bool)
## Coasting 10 s in SOLO (4.6.4) or a stop_5s gesture: the GameHost pauses the game clock.
signal pause_requested(reason: String)
signal directive_applied(record: Dictionary)

## Seconds after which the latest trainer sample no longer counts (power, cadence, speed 0).
const STALE_S := 3.0
## Queue bounds for gestures, intents and acks nobody takes (oldest dropped first).
const MAX_QUEUE := 256

var peer_id: int = 0
var profile: RiderProfile = null
var slot: PlayerSlot = null
var device: TrainerDevice = null
var governor: SafetyGovernor = null
var gestures: GestureRecognizer = null
var wbal: WBalance = null
var speed: SpeedModel = null
## Null for bots and when recording is off.
var recorder: RideRecorderApi = null
var is_bot: bool = false
## The cadence estimator every sample passes through (BRIEF 4.5).
var cadence: CadenceEstimator = null
## True in a multiplayer session (coasting marks AFK, stop_5s is off).
var is_multiplayer: bool = false
## The session's scaling mode (Wl.FAIR_FTP, Wl.WKG or Wl.RAW) for effort.
var scaling_mode: String = Wl.FAIR_FTP
## The bus for band changes, governor status and saved rides; null means the autoload.
var bus: WlEventBus = null

static var _live: Array[WeakRef] = []

var _options: Dictionary = {}
var _gov_params: Dictionary = {}
var _owns_governor: bool = false
var _plan: EffortPlan = null
var _phase_index: int = -1
var _t_us: int = 0
var _pending: Array[TrainerSample] = []
var _last: TrainerSample = null
var _last_sample_t: float = -1.0
var _last_cadence_t: float = -1.0
var _distance_m: float = 0.0
var _gesture_queue: Array[StringName] = []
var _intents: Array = []
var _acks: Array = []
var _game_paused: bool = false
var _cadence_band: Vector2 = Vector2.ZERO
var _power_band: Vector2 = Vector2.ZERO
var _gear: int = 12
var _shut_down: bool = false
var _ready_to_tick: bool = false
var _in_apply: bool = false
var _apply_acked: bool = false
var _ride_path: String = ""
## Bumped by every setup(); tick() stops when a handler it called set the rider up again.
var _setup_gen: int = 0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_unregister()


## Every set-up rider in this process that hasn't been shut down or freed.
static func live_riders() -> Array[LocalRider]:
	var out: Array[LocalRider] = []
	var keep: Array[WeakRef] = []
	for w in _live:
		var r: Object = w.get_ref()
		if r != null and is_instance_valid(r) and r is LocalRider and not (r as LocalRider).is_shut_down():
			out.append(r as LocalRider)
			keep.append(w)
	_live = keep
	return out


## Build the stack. options: {multiplayer (bool), scaling_mode (String), record (bool),
## game_id, content_id, utc_start_unix (int), seed (int), skip_warmup (bool)}.
## W1 additions: governor_profile ("normal" | "ramp_test"), rides_dir (where finish_ride
## saves; default Paths.rides_dir()), and for tests and simulations the injections
## governor (SafetyGovernor), gestures (GestureRecognizer), cadence (CadenceEstimator),
## recorder (RideRecorderApi, or null for none) and bus (WlEventBus).
## A null profile means the defaults; a null slot means profile.to_slot(peer, scaling).
func setup(p_peer_id: int, p_profile: RiderProfile, p_slot: PlayerSlot, p_device: TrainerDevice, p_options: Dictionary = {}) -> void:
	_setup_gen += 1
	# The governor this setup replaces, when it drove the same device object: what belongs to
	# the trainer connection (warm-up, the trainer's written state) carries over (W2r2).
	var prev_gov: SafetyGovernor = null
	if governor != null and is_instance_valid(governor) and device != null and is_instance_valid(device) \
			and device == p_device:
		prev_gov = governor
	_teardown()
	_options = p_options.duplicate()
	peer_id = p_peer_id
	profile = p_profile if p_profile != null else RiderProfile.new()
	is_multiplayer = bool(_options.get("multiplayer", false))
	scaling_mode = str(_options.get("scaling_mode", p_slot.scaling_mode if p_slot != null else Wl.FAIR_FTP))
	slot = p_slot if p_slot != null else profile.to_slot(p_peer_id, scaling_mode)
	is_bot = slot.is_bot
	if p_profile != null and p_slot != null and not slot.is_bot:
		_take_safety_values_from_profile()
	bus = _options.get("bus") as WlEventBus
	device = p_device
	_reset_state()
	if device == null:
		push_error("LocalRider: setup needs a TrainerDevice (peer %d)" % peer_id)
		return
	if device is MockTrainer:
		var mock := device as MockTrainer
		mock.set_cadence_band(0.0, 0.0)
		mock.set_power_band(0.0, 0.0)
		mock.set_phase(-1)
		mock.restart_profile()
	cadence = _options.get("cadence") as CadenceEstimator
	if cadence == null:
		cadence = CadenceEstimator.new()
	gestures = _options.get("gestures") as GestureRecognizer
	if gestures == null:
		gestures = GestureRecognizer.new()
	gestures.configure(ftp_w(), not is_multiplayer)
	wbal = WBalance.create(profile.cp_w, profile.wprime_j)
	speed = SpeedModel.create(slot.rider_mass_kg)
	governor = _options.get("governor") as SafetyGovernor
	if governor == null:
		governor = SafetyGovernor.new()
	_owns_governor = governor.get_parent() == null
	if _owns_governor:
		add_child(governor)
	governor.process_mode = Node.PROCESS_MODE_ALWAYS
	_connect_governor()
	governor.setup(device)
	if prev_gov != null and prev_gov != governor and is_instance_valid(prev_gov):
		governor.adopt_connection(prev_gov)
	_gov_params = _make_governor_params()
	governor.configure(_gov_params.duplicate(true))
	if _options.has("recorder"):
		recorder = _options.get("recorder") as RideRecorderApi
	elif bool(_options.get("record", false)):
		recorder = _new_recorder()
	if recorder != null:
		var utc: int = int(_options.get("utc_start_unix", int(Time.get_unix_time_from_system())))
		recorder.start(str(_options.get("game_id", "")), str(_options.get("content_id", "")), utc, 0.0)
	device.sample_received.connect(_on_sample)
	_ready_to_tick = true
	_register()


## The validated plan (cool-down appended) for the governor.
func set_plan(p_plan: EffortPlan) -> void:
	_plan = p_plan
	_phase_index = -1
	if governor != null:
		governor.set_plan(p_plan)


## The plan given to set_plan (null before).
func plan() -> EffortPlan:
	return _plan


## Drop the plan (W2r2): the session is over but the rider isn't set up again yet (its ride
## still waits to be saved). The governor rides free at SIM grade 0, wind 0
## (SafetyGovernor.clear_plan), the phase is -1 (a MockTrainer's too) and the bands are
## cleared; the recorder keeps recording.
func clear_plan() -> void:
	_plan = null
	_phase_index = -1
	if governor != null and is_instance_valid(governor):
		governor.clear_plan()
	if device is MockTrainer:
		(device as MockTrainer).set_phase(-1)
	set_cadence_band(0.0, 0.0)
	set_power_band(0.0, 0.0)


## Enter plan phase `index` (the GameHost's phase tracking, or a client's `phase` message).
## Laps the recorder when the phase has lap = true or is the cool-down.
func start_phase(index: int) -> void:
	_phase_index = index
	if governor != null:
		governor.start_phase(index)
	if device is MockTrainer:
		(device as MockTrainer).set_phase(index)
	if _plan == null:
		return
	var ph := _plan.phase(index)
	if ph == null:
		return
	var is_cooldown := ph.kind == Wl.COOLDOWN or index == _plan.cooldown_index()
	if (ph.lap or is_cooldown) and _recording():
		recorder.lap(_lap_label(ph, index, is_cooldown), platform_time())
	if is_cooldown:
		set_cadence_band(0.0, 0.0)
		set_power_band(0.0, 0.0)


## A directive for this rider (from the host's DirectiveSink or a `directive` message).
## Returns the governor's applied record.
func apply_directive(directive: EffortDirective) -> Dictionary:
	if governor == null:
		return {}
	_in_apply = true
	_apply_acked = false
	var rec: Dictionary = governor.apply_directive(directive)
	_in_apply = false
	if not _apply_acked and not rec.is_empty():
		_queue_ack(rec)
		directive_applied.emit(rec)
	return rec


func apply_course_grade(grade_pct: float) -> void:
	if governor != null:
		governor.set_course_grade(grade_pct)


## Published cadence band (HUD and MockTrainer band policy; 0, 0 clears).
func set_cadence_band(lo_rpm: float, hi_rpm: float) -> void:
	if not _band_ok(lo_rpm, hi_rpm, "cadence"):
		return
	var band := Vector2(lo_rpm, hi_rpm)
	if band == _cadence_band:
		return
	_cadence_band = band
	if device is MockTrainer:
		(device as MockTrainer).set_cadence_band(lo_rpm, hi_rpm)
	var b := _bus()
	if b != null:
		b.cadence_band_changed.emit(peer_id, lo_rpm, hi_rpm)


## Published power band (HUD gauge in SIM and MockTrainer erg policy; 0, 0 clears).
func set_power_band(lo_w: float, hi_w: float) -> void:
	if not _band_ok(lo_w, hi_w, "power"):
		return
	var band := Vector2(lo_w, hi_w)
	if band == _power_band:
		return
	_power_band = band
	if device is MockTrainer:
		(device as MockTrainer).set_power_band(lo_w, hi_w)
	var b := _bus()
	if b != null:
		b.power_band_changed.emit(peer_id, lo_w, hi_w)


## The current cadence band (x = lo rpm, y = hi rpm; zero when none).
func cadence_band() -> Vector2:
	return _cadence_band


## The current power band (x = lo W, y = hi W; zero when none).
func power_band() -> Vector2:
	return _power_band


func set_game_paused(paused: bool) -> void:
	_game_paused = paused
	if governor != null:
		governor.set_game_paused(paused)
	if _recording():
		recorder.set_timer_running(not paused, platform_time())


## Virtual gear shift (+1/-1) through the governor.
func shift(delta: int) -> void:
	if governor != null:
		_gear = governor.shift(delta)


func panic() -> void:
	if governor != null:
		governor.emergency_safe()


## Leave the panic state (the player resumed).
func resume() -> void:
	if governor != null:
		governor.resume()


## Re-configure the governor with `extra` merged over the parameters setup() gave it (for
## example {"profile": "ramp_test"} for the FTP test).
func configure_governor(extra: Dictionary) -> void:
	_gov_params.merge(extra, true)
	if governor != null:
		governor.configure(_gov_params.duplicate(true))


## The parameters the governor was last configured with (a copy).
func governor_params() -> Dictionary:
	return _gov_params.duplicate(true)


## The rider's FTP in watts (the slot's, else the profile's).
func ftp_w() -> float:
	if slot != null and slot.ftp > 0.0:
		return slot.ftp
	return profile.ftp_w if profile != null else 200.0


## Platform seconds since setup() (advanced only by tick).
func platform_time() -> float:
	return float(_t_us) / 1000000.0


func is_shut_down() -> bool:
	return _shut_down


## A reconnect handed over a new device object for the same trainer: keep everything (plan,
## phase, time, queues, recorder, governor state) and rebind the governor and the sample
## feed to `p_device`. Samples queued from the old object are dropped. The caller owns both
## devices. Before setup() it does nothing but push_error.
func rebind_device(p_device: TrainerDevice) -> void:
	if p_device == null or not _ready_to_tick:
		push_error("LocalRider: rebind_device needs a set-up rider and a device (peer %d)" % peer_id)
		return
	if p_device == device:
		return
	if device != null and is_instance_valid(device) and device.sample_received.is_connected(_on_sample):
		device.sample_received.disconnect(_on_sample)
	device = p_device
	_pending.clear()
	if governor != null and is_instance_valid(governor):
		governor.setup(device)
	device.sample_received.connect(_on_sample)


## The same trainer reconnected on the same device object (FtmsConnectionManager.reconnected):
## the governor restores the last safe mode through its ramped path (BRIEF 4.4, 4.5, 4.6.2;
## SafetyGovernor.on_trainer_reconnected). Plan, phase, time, queues and recorder are kept.
## Does nothing before setup() or after shutdown().
func trainer_reconnected() -> void:
	if not _ready_to_tick or _shut_down:
		return
	if governor != null and is_instance_valid(governor):
		governor.on_trainer_reconnected()


## Advance by dt platform seconds.
func tick(dt: float) -> void:
	if not _ready_to_tick or dt <= 0.0:
		return
	if not is_instance_valid(device) or not is_instance_valid(governor):
		push_warning("LocalRider: peer %d lost its device or governor; not ticking" % peer_id)
		_ready_to_tick = false
		return
	_t_us += roundi(dt * 1000000.0)
	var t := platform_time()
	# A handler of a signal this tick emits (a sample, a gesture, a governor signal) may set
	# the rider up again (a menu pick that starts a session). The rest of this tick belongs to
	# the old setup: it must not feed this tick's platform time into the new governor, ride
	# or gestures, so the tick stops as soon as the generation changes.
	var gen := _setup_gen
	device.tick(dt)
	if gen != _setup_gen:
		return
	while not _pending.is_empty():
		var raw: TrainerSample = _pending.pop_front()
		_process_sample(raw, t)
		if gen != _setup_gen:
			return
	_queue_gestures(gestures.advance(t))
	if gen != _setup_gen:
		return
	var p := _power(t)
	wbal.step(p, dt)
	var v_kmh := _speed_kmh(t)
	_distance_m += v_kmh / 3.6 * dt
	var st := _status()
	var grade := float(st.get("applied_grade_pct", 0.0)) if str(st.get("mode", Wl.OFF)) == Wl.SIM else 0.0
	speed.step(dt, p * slot.p_eff_per_w, grade)
	governor.set_course_distance(speed.distance_m)
	governor.tick(dt)
	if gen != _setup_gen:
		return
	if _recording() and not _shut_down:
		recorder.record(t, p, _recorded_cadence(t), _recorded_speed(t))
	telemetry_updated.emit(_build_telemetry())


## Latest telemetry (a fresh object each call; gestures/intents not included).
func telemetry() -> Telemetry:
	return _build_telemetry()


## Gestures since the last call.
func take_gestures() -> Array[StringName]:
	var out: Array[StringName] = _gesture_queue.duplicate()
	_gesture_queue.clear()
	return out


## Queue a game intent from this rider (ctx.intents.send, local_intents).
func push_intent(intent: Dictionary) -> void:
	_intents.append(intent.duplicate(true))
	_trim(_intents)


## Intents since the last call.
func take_intents() -> Array:
	var out := _intents
	_intents = []
	return out


## Directive acks since the last call (for Telemetry.acks).
func take_acks() -> Array:
	var out := _acks
	_acks = []
	return out


## A FIT lap from the game's lap_marker (a strings key is translated).
func lap(label: String) -> void:
	if _recording():
		recorder.lap(_text(label), platform_time())


## Stop the recorder and write the FIT and summary. Returns the FIT path or "".
## A second call returns the first path without saving again.
func finish_ride() -> String:
	if recorder == null:
		return ""
	if _ride_path != "":
		return _ride_path
	if recorder.is_recording():
		recorder.stop(platform_time())
	_ride_path = recorder.save(str(_options.get("rides_dir", "")))
	if _ride_path != "":
		var b := _bus()
		if b != null:
			b.ride_saved.emit(_ride_path, recorder.summary())
	return _ride_path


## Governor shutdown (SIM flat, then Stop) and device release.
## Idempotent. Afterwards the rider is off live_riders(), gestures and recording stop, and
## tick() keeps ticking the device and governor only so the safe commands can go out.
func shutdown() -> void:
	if _shut_down:
		return
	_shut_down = true
	if governor != null:
		governor.shutdown()
	_unregister()


# --- internals -------------------------------------------------------------------------


func _reset_state() -> void:
	_t_us = 0
	_pending.clear()
	_last = null
	_last_sample_t = -1.0
	_last_cadence_t = -1.0
	_distance_m = 0.0
	_gesture_queue.clear()
	_intents = []
	_acks = []
	_game_paused = false
	_cadence_band = Vector2.ZERO
	_power_band = Vector2.ZERO
	_gear = 12
	_plan = null
	_phase_index = -1
	_shut_down = false
	_ride_path = ""
	recorder = null


func _teardown() -> void:
	if _recording():
		push_warning("LocalRider: peer %d was set up again while recording; saving that ride first" % peer_id)
		finish_ride()
	_ready_to_tick = false
	if device != null and is_instance_valid(device) and device.sample_received.is_connected(_on_sample):
		device.sample_received.disconnect(_on_sample)
	if governor != null and is_instance_valid(governor):
		_disconnect_governor()
		if _owns_governor and governor.get_parent() == self:
			remove_child(governor)
			governor.queue_free()
	governor = null
	_owns_governor = false
	_unregister()


## SAF-1 (W4): the local human's ftp, ftp_verified, haptics_on and haptic_intensity come from
## the rider's own profile, whatever the slot (a host's copy on a CLIENT) said.
func _take_safety_values_from_profile() -> void:
	var own_intensity := profile.haptic_intensity_pct / 100.0
	var differs := absf(slot.ftp - profile.ftp_w) >= 1.0 or slot.ftp_verified != profile.ftp_verified 		or slot.haptics_on != profile.haptics_on or absf(slot.haptic_intensity - own_intensity) > 1e-6
	if differs:
		push_warning("LocalRider: peer %d's slot said FTP %s W (verified %s), haptics %s at %s; using the rider's own profile: FTP %s W (verified %s), haptics %s at %s" % [
			peer_id, str(slot.ftp), str(slot.ftp_verified), str(slot.haptics_on), str(slot.haptic_intensity),
			str(profile.ftp_w), str(profile.ftp_verified), str(profile.haptics_on), str(own_intensity)])
	slot.ftp = profile.ftp_w
	slot.ftp_verified = profile.ftp_verified
	slot.haptics_on = profile.haptics_on
	slot.haptic_intensity = own_intensity


func _make_governor_params() -> Dictionary:
	var max_w := int(device.power_range().get("max_w", 1800))
	return {
		"ftp_w": ftp_w(),
		"ftp_verified": slot.ftp_verified,
		"difficulty_pct": profile.difficulty_pct,
		"grade_min_pct": profile.grade_min_pct,
		"grade_max_pct": profile.grade_max_pct,
		"haptics_on": slot.haptics_on,
		"haptic_intensity": slot.haptic_intensity,
		"skip_warmup": bool(_options.get("skip_warmup", profile.skip_warmup)),
		"multiplayer": is_multiplayer,
		"weight_kg": profile.weight_kg,
		"trainer_max_w": max_w,
		"profile": str(_options.get("governor_profile", "normal")),
	}


func _connect_governor() -> void:
	governor.rescue_changed.connect(_on_rescue_changed)
	governor.afk_changed.connect(_on_afk_changed)
	governor.pause_requested.connect(_on_pause_requested)
	governor.directive_applied.connect(_on_directive_applied)
	governor.status_changed.connect(_on_governor_status)


func _disconnect_governor() -> void:
	for pair: Array in [
		[governor.rescue_changed, _on_rescue_changed],
		[governor.afk_changed, _on_afk_changed],
		[governor.pause_requested, _on_pause_requested],
		[governor.directive_applied, _on_directive_applied],
		[governor.status_changed, _on_governor_status],
	]:
		var sig: Signal = pair[0]
		var cb: Callable = pair[1]
		if sig.is_connected(cb):
			sig.disconnect(cb)


func _new_recorder() -> RideRecorderApi:
	var rides := AutoloadLookup.rides()
	if rides == null:
		push_warning("LocalRider: no Rides service; peer %d rides unrecorded" % peer_id)
		return null
	return rides.new_recorder()


func _on_sample(sample: TrainerSample) -> void:
	if sample != null:
		_pending.append(sample)


func _process_sample(raw: TrainerSample, t: float) -> void:
	var s := TrainerSample.new()
	s.t = t
	s.power_w = raw.power_w
	s.cadence_rpm = raw.cadence_rpm
	s.speed_kmh = raw.speed_kmh
	s.distance_m = raw.distance_m
	s.flags = raw.flags
	var processed := cadence.process(s)
	if processed != null:
		s = processed
	_last = s
	_last_sample_t = t
	if s.has_cadence():
		_last_cadence_t = t
	gestures.set_erg(str(_status().get("mode", Wl.OFF)) == Wl.ERG)
	var gen := _setup_gen
	_queue_gestures(gestures.on_sample(s))
	if gen != _setup_gen:
		return
	governor.on_sample(s)


func _queue_gestures(fired: Array[StringName]) -> void:
	if _shut_down:
		return
	var gen := _setup_gen
	for g in fired:
		if gen != _setup_gen:
			# A handler set the rider up again: the rest belongs to the old setup.
			return
		_gesture_queue.append(g)
		_trim_gestures()
		gesture_detected.emit(g)
		if gen != _setup_gen:
			return
		if g == Wl.G_STOP_5S and not is_multiplayer:
			pause_requested.emit("stop_5s")


func _fresh(t: float) -> bool:
	return _last != null and t - _last_sample_t <= STALE_S + 1e-9


func _power(t: float) -> float:
	return maxf(_last.power_w, 0.0) if _fresh(t) else 0.0


func _cadence(t: float) -> float:
	return _last.cadence_rpm if _fresh(t) and _last.has_cadence() else 0.0


func _speed_kmh(t: float) -> float:
	return _last.speed_kmh if _fresh(t) and _last.has_speed() else 0.0


## For the recorder: -1 (absent) when the trainer reports no cadence or the sample is stale.
func _recorded_cadence(t: float) -> float:
	return _last.cadence_rpm if _fresh(t) and _last.has_cadence() else -1.0


func _recorded_speed(t: float) -> float:
	return _last.speed_kmh if _fresh(t) and _last.has_speed() else -1.0


func _status() -> Dictionary:
	return governor.status() if governor != null else {}


func _build_telemetry() -> Telemetry:
	var tel := Telemetry.new()
	tel.peer_id = peer_id
	var t := platform_time()
	tel.t = t
	if not _ready_to_tick:
		tel.phase_index = _phase_index
		return tel
	var p := _power(t)
	var ftp := ftp_w()
	tel.power_w = p
	tel.cadence_rpm = _cadence(t)
	tel.speed_kmh = _speed_kmh(t)
	tel.effort = EffortScaling.effort(scaling_mode, p, ftp, profile.weight_kg)
	tel.p_eff_w = p * slot.p_eff_per_w
	tel.wbal_j = wbal.wbal_j
	tel.ftp_pct = EffortScaling.ftp_pct(p, ftp)
	var st := _status()
	tel.mode = str(st.get("mode", Wl.OFF))
	tel.applied_target_w = int(st.get("applied_target_w", 0)) if tel.mode == Wl.ERG else 0
	tel.applied_grade_pct = float(st.get("applied_grade_pct", 0.0)) if tel.mode == Wl.SIM else 0.0
	tel.gear = int(st.get("gear", _gear))
	var clamps: Variant = st.get("clamped_by", [])
	if clamps is Array:
		for c: Variant in clamps:
			tel.clamped_by.append(str(c))
	tel.rescue = bool(st.get("rescue", false))
	tel.coasting = bool(st.get("coasting", false))
	tel.afk = bool(st.get("afk", false))
	tel.paused = bool(st.get("paused", false)) or _game_paused
	tel.s_left_105 = float(st.get("s_left_105", 300.0))
	tel.s_left_120 = float(st.get("s_left_120", 60.0))
	tel.haptic_pct = float(st.get("haptic_pct", 0.0))
	tel.distance_m = _distance_m
	tel.phase_index = _phase_index
	tel.connected = true
	tel.age_s = 0.0
	tel.cadence_age_s = t - _last_cadence_t if _last_cadence_t >= 0.0 else t
	return tel


func _queue_ack(rec: Dictionary) -> void:
	var applied: Variant = rec.get("applied", {})
	var clamps: Variant = rec.get("clamped_by", [])
	var clamp_list: Array = []
	if clamps is Array:
		for c: Variant in clamps:
			clamp_list.append(str(c))
	var dropped: Array = []
	var d: Variant = rec.get("dropped", [])
	if d is Array:
		for e: Variant in d:
			if e is Dictionary:
				dropped.append({"channel": str((e as Dictionary).get("channel", "")),
					"reason": str((e as Dictionary).get("reason", ""))})
	_acks.append({
		"id": rec.get("id", 0),
		"kind": rec.get("kind", ""),
		"applied": (applied as Dictionary).duplicate(true) if applied is Dictionary else {},
		"clamped_by": clamp_list,
		"refused": bool(rec.get("refused", false)),
		"reason": str(rec.get("reason", "")),
		"dropped": dropped,
	})
	_trim(_acks)


func _on_directive_applied(record: Dictionary) -> void:
	if _in_apply:
		_apply_acked = true
	_queue_ack(record)
	directive_applied.emit(record)


func _on_rescue_changed(active: bool) -> void:
	rescue_changed.emit(active)


func _on_afk_changed(afk: bool) -> void:
	afk_changed.emit(afk)


func _on_pause_requested(reason: String) -> void:
	pause_requested.emit(reason)


func _on_governor_status(st: Dictionary) -> void:
	if is_bot:
		return
	var b := _bus()
	if b != null:
		b.governor_status.emit(peer_id, st)


func _recording() -> bool:
	return recorder != null and recorder.is_recording()


func _lap_label(ph: PlanPhase, index: int, is_cooldown: bool) -> String:
	if ph.label != "":
		return _text(ph.label)
	if is_cooldown:
		return _text("CORE_LAP_COOLDOWN")
	return _text("CORE_LAP_PHASE").replace("{n}", str(index + 1))


## A strings key's text, or `s` itself when it isn't a key (plain text passes through).
static func _text(s: String) -> String:
	return String(TranslationServer.translate(s))


func _band_ok(lo: float, hi: float, what: String) -> bool:
	if is_nan(lo) or is_nan(hi) or lo < 0.0 or hi < lo:
		push_error("LocalRider: bad %s band [%s, %s]" % [what, str(lo), str(hi)])
		return false
	return true


func _trim_gestures() -> void:
	while _gesture_queue.size() > MAX_QUEUE:
		_gesture_queue.remove_at(0)


static func _trim(q: Array) -> void:
	while q.size() > MAX_QUEUE:
		q.remove_at(0)


func _bus() -> WlEventBus:
	return bus if bus != null else AutoloadLookup.bus()


func _register() -> void:
	for w in _live:
		if w.get_ref() == self:
			return
	_live.append(weakref(self))


func _unregister() -> void:
	var keep: Array[WeakRef] = []
	for w in _live:
		var r: Object = w.get_ref()
		if r != null and r != self:
			keep.append(w)
	_live = keep
