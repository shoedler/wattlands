class_name PhaseState
extends RefCounted
## A rider's current plan phase as the game sees it in `frame.phase[peer]`
## (BRIEF 3.6). Contract, frozen after W0. Times are game sim seconds (the game's
## sim clock stops while paused).

var index: int = -1
var kind: String = ""
var mode: String = ""
## Seconds since this phase started.
var elapsed_s: float = 0.0
## Nominal length (fixed phases: their length).
var duration_s: float = 0.0
var open_ended: bool = false
var min_s: float = 0.0
var max_s: float = 0.0
var label: String = ""
## Planned ERG target now, % FTP (0 in SIM phases).
var planned_pct: float = 0.0
## Seconds until the platform ends the phase on its own: duration_s - elapsed for fixed
## phases, max_s - elapsed for open-ended ones. Never negative.
var remaining_s: float = 0.0
## Total phases in this rider's plan (cool-down included once appended).
var count: int = 0
## Game seconds since this rider's plan started (sum of finished phases + elapsed_s).
var plan_elapsed_s: float = 0.0
## How the previous phase ended (Wl.ENDED_*), "" for the first phase.
var prev_ended_by: String = ""


func is_cooldown() -> bool:
	return kind == Wl.COOLDOWN


func to_dict() -> Dictionary:
	return {
		"index": index,
		"kind": kind,
		"mode": mode,
		"elapsed_s": elapsed_s,
		"duration_s": duration_s,
		"open_ended": open_ended,
		"min_s": min_s,
		"max_s": max_s,
		"label": label,
		"planned_pct": planned_pct,
		"remaining_s": remaining_s,
		"count": count,
		"plan_elapsed_s": plan_elapsed_s,
		"prev_ended_by": prev_ended_by,
	}


static func from_dict(d: Dictionary) -> PhaseState:
	var s := PhaseState.new()
	s.index = int(d.get("index", -1))
	s.kind = str(d.get("kind", ""))
	s.mode = str(d.get("mode", ""))
	s.elapsed_s = float(d.get("elapsed_s", 0.0))
	s.duration_s = float(d.get("duration_s", 0.0))
	s.open_ended = bool(d.get("open_ended", false))
	s.min_s = float(d.get("min_s", 0.0))
	s.max_s = float(d.get("max_s", 0.0))
	s.label = str(d.get("label", ""))
	s.planned_pct = float(d.get("planned_pct", 0.0))
	s.remaining_s = float(d.get("remaining_s", 0.0))
	s.count = int(d.get("count", 0))
	s.plan_elapsed_s = float(d.get("plan_elapsed_s", 0.0))
	s.prev_ended_by = str(d.get("prev_ended_by", ""))
	return s
