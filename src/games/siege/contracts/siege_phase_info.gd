class_name SiegePhaseInfo
extends RefCounted
## The shared phase as the rules see it (G0 contract): frame.phase's clock plus the Siege role
## from PlanPhase.meta (SiegePlanBuilder writes it from shifts.json; the rules never infer a
## role from `kind`: the drill's wave is a WARMUP-kind phase that plays as wave 1).

var index: int = -1
## Wl.WARMUP / WORK / RECOVERY / COOLDOWN.
var kind: String = ""
## SiegeIds.ROLE_*.
var role: String = SiegeIds.ROLE_NONE
## Wave number 1..N (waves), break number (breaks), 0 otherwise.
var number: int = 0
## Waves in the shift.
var waves: int = 0
var elapsed_s: float = 0.0
var duration_s: float = 0.0
var remaining_s: float = 0.0
## Game seconds since the plan started.
var plan_elapsed_s: float = 0.0
## Wave-elapsed times of endurance rushes in this phase ([] elsewhere).
var rushes_at_s: Array[float] = []
## The wave's threat mix (SiegeIds.MIX_*).
var mix: String = SiegeIds.MIX_STANDARD
## This wave is the shift's last wave (its end fires finished("complete")).
var last_wave: bool = false


## From the platform's PhaseState and the phase's meta (SiegePlanBuilder.role_of()).
static func from_phase(ps: PhaseState, meta: Dictionary) -> SiegePhaseInfo:
	var p := SiegePhaseInfo.new()
	p.index = ps.index
	p.kind = ps.kind
	p.elapsed_s = ps.elapsed_s
	p.duration_s = ps.duration_s
	p.remaining_s = ps.remaining_s
	p.plan_elapsed_s = ps.plan_elapsed_s
	p.role = str(
		meta.get("role", SiegeIds.ROLE_COOLDOWN if ps.is_cooldown() else SiegeIds.ROLE_NONE)
	)
	p.number = int(meta.get("number", 0))
	p.waves = int(meta.get("waves", 0))
	p.mix = str(meta.get("mix", SiegeIds.MIX_STANDARD))
	p.last_wave = bool(meta.get("last_wave", false))
	for r: Variant in meta.get("rushes_at_s", []):
		p.rushes_at_s.append(float(r))
	return p


func is_wave() -> bool:
	return role == SiegeIds.ROLE_WAVE or role == SiegeIds.ROLE_WARMUP_WAVE


func is_break() -> bool:
	return role == SiegeIds.ROLE_BREAK or role == SiegeIds.ROLE_BUILD_BREAK


func is_cooldown() -> bool:
	return kind == Wl.COOLDOWN or role == SiegeIds.ROLE_COOLDOWN
