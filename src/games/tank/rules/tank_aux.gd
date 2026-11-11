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
## v4: far enemy id -> seconds until its next shift (enemies.json shift_every_s).
var enemy_shift: Dictionary = {}
## v4: near threat id -> what is left of this step: seconds of a burst or a pause, px of a dash.
var near_left: Dictionary = {}
## v4: the depth lane the next near threat takes (they alternate 0, 1).
var near_lane: int = 0
## v4: the segment's elapsed_s when its stage last restarted (0 before): a near list counts from it.
var stage_from_s: float = 0.0
## v4: the Behemoth's d(range)/dt in m/s this tick (the lead solver reads it).
var boss_rate_mps: float = 0.0
## Enemy shell id -> seconds until it lands (the arrival resolves the hit rolled at fire time).
var shell_left: Dictionary = {}
## The auto-aim's choice this tick (TankAim.current): target, elevation and facing; reset to
## stale at the start of every step.
var aim_valid: bool = false
var aim_target: TankTarget = null
var aim_elev: float = 0.0
var aim_facing: int = TankIds.FACE_RIGHT
## The hangar's drills of the current segment ([{from_s, to_s, drill, targets?}]).
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
## Seconds an `over` asked for before the shell in progress was stowed still counts: that shell
## goes straight back to the boiler when it is stowed (a surge just before the window).
var over_arm_s: float = 0.0
## Hangar drills already started (the aim drill's wrecks stand).
var drill_wrecks: bool = false
## The Behemoth's telegraph length at its start (the HUD's countdown pips read telegraph_s).
var boss_tele_total: float = 0.0
## Seconds since the last Advance enemy was spawned (spawns of one encounter stagger).
var last_spawn_t: float = -100.0

# --- v3 seats, rack and bow guns -------------------------------------------------------------------
## peer -> the game time the rider last landed on a seat (TankSeats.stay_s; 0.3.1 no seat lock).
var seat_since: Dictionary = {}
## peer -> the rider's TankRiderInput of this tick (TankSeats.follows_now, checkpoint_next).
var seat_input: Dictionary = {}
## peer -> the mode of the rider's current plan phase (its trainer: Wl.ERG or Wl.SIM).
var trainer_mode: Dictionary = {}
## peer -> the game time of the rider's last ERG <-> SIM switch (a plan phase of the other mode
## starting; TankSeatPlan.follow keeps them 30 s apart). Absent before the first.
var last_switch_s: Dictionary = {}
## peer -> the mission segment index in which the rider last sat off Drive (the solo loop).
var off_drive_seg: Dictionary = {}
## The ready rack's shells, oldest first (TankIds.SHELL_*; TankSteamState.rack is its size). The
## Gun chambers the oldest; an Overpressure takes the newest back to the boiler.
var rack_types: Array[int] = []
## The Loader's progress on the next shell (pressure %) set aside while an Overpressure builds.
var carry_pct: float = 0.0
## The below-band share of carry_pct (the trickle): it comes back as trickle, never as graded pressure.
var carry_trickle_pct: float = 0.0
## The bow guns' elevation now (degrees, up positive; TankBow slews it to the target).
var bow_deg: float = 0.0
## v4: peer -> {"seat": engine}: the human a bot covers while on reserve (TankBots.cover), and the
## seat it lands back on.
var cover: Dictionary = {}


## The state's aux, created on first use.
static func of(state: TankState) -> TankAux:
	if state.has_meta(META):
		return state.get_meta(META) as TankAux
	var a := TankAux.new()
	a.geo = TankGeometry.load_for(state.content)
	state.set_meta(META, a)
	return a
