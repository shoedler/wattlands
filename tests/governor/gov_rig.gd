extends RefCounted
## Test rig: one SafetyGovernor around a device, ticked in LocalRider's order
## (device.tick, samples -> governor.on_sample, governor.tick) in fixed 0.05 s steps.
## Records every directive_applied record, every governor signal and, when keep_trace is
## on, the status after every tick.

const DT := Wl.SIM_DT

var device: TrainerDevice = null
var gov: SafetyGovernor = null
var t: float = 0.0
var records: Array[Dictionary] = []
## [{t, name, value}] for rescue_changed, coasting_changed, pause_requested, afk_changed,
## warmup_changed, panic_changed and ramp_test_ended.
var events: Array[Dictionary] = []
var trace: Array[Dictionary] = []
var keep_trace: bool = false


func _init(p_device: TrainerDevice, params: Dictionary = {}) -> void:
	device = p_device
	gov = SafetyGovernor.new()
	gov.configure(params)
	gov.setup(device)
	device.sample_received.connect(gov.on_sample)
	gov.directive_applied.connect(func(r: Dictionary) -> void: records.append(r))
	gov.rescue_changed.connect(func(v: bool) -> void: _event("rescue_changed", v))
	gov.coasting_changed.connect(func(v: bool) -> void: _event("coasting_changed", v))
	gov.pause_requested.connect(func(v: String) -> void: _event("pause_requested", v))
	gov.afk_changed.connect(func(v: bool) -> void: _event("afk_changed", v))
	gov.warmup_changed.connect(func(v: bool) -> void: _event("warmup_changed", v))
	gov.panic_changed.connect(func(v: bool) -> void: _event("panic_changed", v))
	gov.ramp_test_ended.connect(func(v: String) -> void: _event("ramp_test_ended", v))


## Plan from phases and enter phase 0.
func start(phases: Array, start_index: int = 0) -> void:
	gov.set_plan(EffortPlan.of(phases))
	gov.start_phase(start_index)


## One platform tick. `t` advances first, so events raised during the tick carry the tick's
## time (the governor's own platform time).
func step() -> void:
	t += DT
	device.tick(DT)
	gov.tick(DT)
	if keep_trace:
		var s := gov.status()
		s["rig_t"] = t
		trace.append(s)


func run(seconds: float) -> void:
	for i in roundi(seconds / DT):
		step()


## Step until cond() is true (checked after each step) or max_s passes; returns the time
## at which it became true, or -1.
func run_until(cond: Callable, max_s: float) -> float:
	for i in roundi(max_s / DT):
		step()
		if cond.call():
			return t
	return -1.0


func s() -> Dictionary:
	return gov.status()


func applied_w() -> int:
	return int(gov.status()["applied_target_w"])


func directive(fields: Dictionary) -> Dictionary:
	return gov.apply_directive(EffortDirective.from_dict(fields))


func events_named(event_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if e["name"] == event_name:
			out.append(e)
	return out


func nodes() -> Array[Node]:
	return [gov, device]


func _event(event_name: String, value: Variant) -> void:
	events.append({"t": t, "name": event_name, "value": value})
