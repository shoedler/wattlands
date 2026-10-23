class_name FishingState
extends FishingRecord
## The whole simulation state of a trip (G0 contract): one FishingLaneState per slot, in slot
## order, plus the team's catch board. FishingRules.new_state builds it on every peer at configure
## time; the host steps it; clients overwrite it from snapshots.

var tick: int = 0
## Game seconds since the session started (tick x 0.05).
var t: float = 0.0
var trip_id: String = ""
var trip_kind: String = ""
## Game time fishing ends (ride out + fishing_s; scheduled trips: the last planned Landing's
## nominal end) and the latest a fight may end (fishing end + 5 min).
var fishing_end_t: float = 0.0
var overrun_end_t: float = 0.0
## The trip's nominal length without the cool-down (the view's day cycle).
var trip_total_s: float = 0.0
## Fight budget per lane: fight_cap_frac x fishing_s (Free 40 %, Base 25 %).
var fight_budget_s: float = 0.0
var lanes: Array[FishingLaneState] = []

# --- Team (2.4 points, 2.8) ---------------------------------------------------------------
var team_points: int = 0
var team_fish: int = 0
## Fights on right now (the deck bar's hookup level, 0..4).
var hookup_level: int = 0
## The catch board, newest last, flat: [lane, species, grade, lane, species, grade, ...] (<= 5).
var catches: Array[int] = []
## Points if every started fish were Landed with no bonuses (scheduled trips: with each fish's
## Double Hookup multiplier); the grade is team_points / expected_points.
var expected_points: float = 0.0
var fish_started: int = 0
## finished("trip_over") was emitted.
var trip_over: bool = false

# --- Trip constants the rules read every tick (fish-rules, additive) ----------------------
## Threshold or e2e: one shared schedule, fixed Reels, self-hooking fish, no finished.
var scheduled: bool = false
## R_min = max(120 s, k_rmin x the previous fight's length incl. landing) (Free 1.5, Base 3).
var k_rmin: float = 1.5
## The area's spot types (FishingConst.SPOTS indexes, file order) and their affinities, flat:
## area_affinity[4 x spot position + species index].
var area_spots: Array[int] = []
var area_affinity: Array[float] = []
## Hint distances are drawn in [spot_d_lo, spot_d_hi] metres.
var spot_d_lo: float = FishingConst.SPOT_D_MIN
var spot_d_hi: float = FishingConst.SPOT_D_MAX


func lane_of_peer(peer: int) -> FishingLaneState:
	for l in lanes:
		if l.peer == peer:
			return l
	return null


func lane(slot: int) -> FishingLaneState:
	return lanes[slot] if slot >= 0 and slot < lanes.size() else null
