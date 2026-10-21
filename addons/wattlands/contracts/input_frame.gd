class_name InputFrame
extends RefCounted
## What the GameHost passes to `GameModule.sim_step(dt, frame)` every 0.05 s on the host
## or in solo play (BRIEF 3.6). Contract, frozen after W0.

## Game sim tick (stops while paused).
var tick: int = 0
## Game sim time in seconds (tick * Wl.SIM_DT).
var t: float = 0.0
## peer_id (int) -> Telemetry: the latest telemetry of every rider in ctx.players,
## with Autopilot intents merged in for bots and Autopilot players.
var players: Dictionary = {}
## peer_id (int) -> PhaseState: each rider's current phase.
var phase: Dictionary = {}


func telemetry(peer: int) -> Telemetry:
	return players.get(peer, null)


func phase_of(peer: int) -> PhaseState:
	return phase.get(peer, null)
