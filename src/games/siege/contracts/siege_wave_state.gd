class_name SiegeWaveState
extends SiegeRecord
## The current phase's wave bookkeeping in SiegeState.wave (host only; reset at every phase
## start by the rules). Clients learn what they show from events (wave_start, rush, push, dock)
## and from the phase clock.

## Total threat B for this wave (brief 2.4; warm-up 0.4 x B; endurance rushes take 8% each).
var budget: float = 0.0
## Threat not yet spawned (groups draw from it).
var budget_left: float = 0.0
## Threat dropped because no staging ground could still reach the gate in time.
var dropped: float = 0.0
## Seconds until the next group (seeded 6..12 s); groups stop 60 s before the wave ends.
var spawn_in_s: float = 0.0
## Threat owed to the next formation(s): each group adds its share, and formations spawn while
## it covers the next one's threat.
var group_acc: float = 0.0
## The next formation's type (drawn in advance so the expected split follows the mix; 0: none).
var next_type: int = 0
## Siege engines still to enter this wave: [[type, enter_at_s, prog_m, hp_frac, escort], ...]
## (wave seconds; prog where it enters).
var engines: Array = []
## Engines that entered and engines destroyed before they reached the gate or docked (T4).
var engines_in: int = 0
var engines_stopped: int = 0
## Endurance rushes: index of the next rush in rushes_at_s, seconds left of the current rush
## (> 0: on) and its threat still to spawn.
var rush_next: int = 0
var rush_s: float = 0.0
var rush_budget_left: float = 0.0
## The rush's account and its next formation type (like group_acc / next_type).
var rush_acc: float = 0.0
var rush_type: int = 0
## Leaks and gate damage this wave (results, T3).
var leaks: int = 0
var gate_damage: float = 0.0
## Last teaching toast minute shown in the warm-up wave.
var toast_min: int = 0
