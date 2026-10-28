class_name TankAux
extends RefCounted
## Host-only bookkeeping the rules need beyond TankState (brief 2.4; owner: rules). It is never
## serialized, never sent and never read by the director, the view or the HUD: a snapshot carries
## everything a client needs, and clients never simulate. It rides on the state as object metadata
## (TankAux.of), so the frozen TankState contract stays as it is. Everything here is a pure
## function of the seed and the inputs, so two runs with the same seed agree.

const META := &"tank_aux"

## rigs.json through TankGeometry (muzzles, hit boxes; v3: the tank's own from the content's
## tanks.json, TankGeometry.load_for), loaded once per state.
var geo: TankGeometry = null
## The target list of this tick (TankTargets.build), nearest-first order is not implied.
var targets: Array[TankTarget] = []
## Enemy id -> its world velocity in px/s this tick (the lead solver and keep-station read it).
var enemy_vx: Dictionary = {}
## Enemy id -> its logical distance from the hull's nearer end (kept apart from x so that the
## hull moving first in a tick does not eat into an enemy keeping station).
var enemy_dist: Dictionary = {}
## Enemy id -> seconds it has held its station (a raider with linger_s leaves after that long).
var enemy_age: Dictionary = {}
## Enemy id -> true once it broke off and is rolling away (it fires no more and is removed, with no
## kill credit, when it is off screen).
var enemy_leaving: Dictionary = {}
## Enemy id -> shots fired (a destroyer alternates the side it shifts to).
var enemy_shots: Dictionary = {}
## Enemy id -> true once its flank shot (enemies.json flank, the light tank's) has been fired.
var enemy_flank_done: Dictionary = {}
## Running telegraphs (TankEvade): shooter id -> {held: {slot: s}, able: {slot: true}}.
var evade: Dictionary = {}
## Enemy shell id -> seconds until it lands (the arrival resolves the hit rolled at fire time).
var shell_left: Dictionary = {}
## The auto-aim's choice this tick (TankAim.current): target, elevation and facing; reset to
## stale at the start of every step.
var aim_valid: bool = false
var aim_target: TankTarget = null
var aim_elev: float = 0.0
var aim_facing: int = TankIds.FACE_RIGHT
## The depot's drills of the current segment ([{from_s, to_s, drill, targets?}]).
var drills: Array = []
## The target the rider cycled to by hand stays the auto-aim's target until it falls.
var manual_target: bool = false
## An enemy stands on screen (the dynamo's stabilizer drain and the Lights' searchlight load, this
## tick).
var enemy_in_range: bool = false
## Some shootable target stands on screen.
var any_target: bool = false
## Joules counted toward Overpressure while the sprint rule held.
var over_j: float = 0.0
## Depot drills already started (the aim drill's wrecks stand).
var drill_wrecks: bool = false
## The Behemoth's telegraph length at its start (the HUD's countdown pips read telegraph_s).
var boss_tele_total: float = 0.0
## Seconds since the last Advance enemy was spawned (spawns of one encounter stagger).
var last_spawn_t: float = -100.0

# --- v3 seats, rack and bow guns -------------------------------------------------------------------
## peer -> the plan phase index the seat lock last saw (a new one is a plan boundary).
var seat_phase: Dictionary = {}
## peer -> the game time of the rider's last plan boundary (the seat lock counts from it).
var seat_since: Dictionary = {}
## The ready rack's shells, oldest first (TankIds.SHELL_*; TankSteamState.rack is its size). The
## Gun chambers the oldest; an Overpressure takes the newest back to the boiler.
var rack_types: Array[int] = []
## The Loader's progress on the next shell (pressure %) set aside while an Overpressure builds.
var carry_pct: float = 0.0
## The bow guns' elevation now (degrees, up positive; TankBow slews it to the target).
var bow_deg: float = 0.0


## The state's aux, created on first use.
static func of(state: TankState) -> TankAux:
	if state.has_meta(META):
		return state.get_meta(META) as TankAux
	var a := TankAux.new()
	a.geo = TankGeometry.load_for(state.content)
	state.set_meta(META, a)
	return a
