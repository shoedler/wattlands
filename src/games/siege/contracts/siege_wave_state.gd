class_name SiegeWaveState
extends SiegeRecord
## The current phase's wave bookkeeping in SiegeState.wave (host only; reset at every phase
## start by the rules). Clients learn what they show from events (wave_start, roads, rush, push)
## and from the phase clock. G0 contract.

## Total threat B for this wave (brief 2.4; warm-up 0.4 x B; endurance rushes take 8% each).
var budget: float = 0.0
## Threat not yet spawned (groups draw from it).
var budget_left: float = 0.0
## Seconds until the next group (seeded 6..12 s); groups stop 60 s before the wave ends.
var spawn_in_s: float = 0.0
## Road ids active now (min(3, slots)); with fewer than 3, they rotate every 30..60 s (seeded).
var active_roads: Array[int] = []
## The announced next road set (a roads event with a 5 s horn), applied when horn_s reaches 0.
var next_roads: Array[int] = []
var horn_s: float = 0.0
var rotate_in_s: float = 0.0
## The ram push (60 s left) has started.
var push_done: bool = false
## Endurance rushes: index of the next rush in rushes_at_s, seconds left of the current rush
## (> 0: on) and its threat still to spawn.
var rush_next: int = 0
var rush_s: float = 0.0
var rush_budget_left: float = 0.0
## Leaks and gate damage this wave (results, T3).
var leaks: int = 0
var gate_damage: float = 0.0
## Rams that entered and rams destroyed before reaching the gate (T4).
var rams: int = 0
var rams_stopped: int = 0
## Last teaching toast minute shown in the warm-up wave.
var toast_min: int = 0
