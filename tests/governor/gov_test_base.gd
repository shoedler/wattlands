extends GutTest
## Shared helpers for the governor suites (not collected by GUT: no test_ prefix).
## Default rider: FTP 200 W verified, warm-up skipped, so each suite isolates its own rule;
## suites that test warm-up or the unverified factor configure them explicitly.

const Rig := preload("res://tests/governor/gov_rig.gd")
const ScriptedDevice := preload("res://tests/governor/scripted_device.gd")
const DT := Wl.SIM_DT

const BASE_PARAMS := {"ftp_w": 200.0, "ftp_verified": true, "skip_warmup": true}


## A rig with BASE_PARAMS overridden by `params`, around `device` (a ScriptedDevice when null).
func make_rig(params: Dictionary = {}, device: TrainerDevice = null) -> Rig:
	var dev: TrainerDevice = device if device != null else ScriptedDevice.new()
	var p := BASE_PARAMS.duplicate()
	p.merge(params, true)
	var rig := Rig.new(dev, p)
	autofree(rig.gov)
	autofree(dev)
	return rig


## A ScriptedDevice whose rider follows the ERG target exactly (power = target).
func follower(cadence: float = 90.0) -> TrainerDevice:
	var d := ScriptedDevice.new()
	d.erg_follow = 1.0
	d.cadence_rpm = cadence
	return d


func erg(kind: String, pct: float, dur: float, label: String = "") -> PlanPhase:
	return PlanPhase.erg(kind, pct, dur, label)


func sim(source: String, dur: float, kind: String = Wl.WORK) -> PlanPhase:
	return PlanPhase.sim(kind, source, dur)


func cooldown() -> PlanPhase:
	return PlanPhase.erg(Wl.COOLDOWN, 50.0, 180.0, "Cool-down").with_lap()


## A plan whose last phase is the appended cool-down (as the PlanValidator leaves it).
func plan_with_cooldown(phases: Array) -> EffortPlan:
	var plan := EffortPlan.of(phases)
	plan.add(cooldown())
	plan.cooldown_appended = true
	return plan


func dev_of(rig: Rig) -> TrainerDevice:
	return rig.device


## The first trace entry (rig.keep_trace) where pred(status) is true, or {}.
func first_where(rig: Rig, pred: Callable) -> Dictionary:
	for s: Dictionary in rig.trace:
		if pred.call(s):
			return s
	return {}


## Assert two times match within half a tick.
func assert_time(actual: float, expected: float, msg: String = "") -> void:
	assert_almost_eq(actual, expected, DT * 0.5, msg)
