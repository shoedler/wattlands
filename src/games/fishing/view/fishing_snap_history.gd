class_name FishingSnapHistory
extends SnapHistory
## The riders of the last few states keyed by the game time (tick x Wl.SIM_DT), so the view
## draws every boat and fish between two of them: on a client between snapshots with its render
## clock behind the newest by mean_spacing() (GAME_SDK 12), on the host and in SOLO between sim
## steps one step behind. push(t, state) records a state (the view pushes every frame; a push at
## the newest time replaces it); the view reads value_at().

## The values kept per rider: boat x (m), signed trim (deg, bow up positive), wake, braking
## (0..1), the fish's dx and depth (m), the wobbler's dx and depth (m), EMA cadence (rpm), heave
## (m, up positive).
const KEYS: Array[String] = [
	"x", "pitch", "wake", "brake", "fdx", "fz", "ldx", "lz", "cad", "heave"
]

## Rows, oldest first: {"t": host seconds, "r": {slot: {key: value}}}.


## The values KEYS names for rider `r`.
static func values_of(r: FishingRiderState) -> Dictionary:
	return {
		"x": r.x_m,
		"pitch": r.pitch_deg,
		"wake": r.wake,
		"brake": r.brake,
		"fdx": r.fish_dx(),
		"fz": r.fish.depth_m(),
		"ldx": r.lure_dx,
		"lz": r.lure_depth,
		"cad": r.cadence_ema,
		"heave": r.heave_m,
	}


## Records the riders of the snapshot just applied to `state`, at host time `t`.
func push(t: float, state: FishingState) -> void:
	var rows := {}
	for r in state.riders:
		rows[r.slot] = values_of(r)
	add(t, {"r": rows})


## Rider `slot`'s value `key` at host time `t`: linear between the two entries around `t`, the
## oldest entry's before it and the newest's after it (never extrapolated); `fallback` when no
## entry has the rider.
func value_at(slot: int, key: String, t: float, fallback: float) -> float:
	return sample_sub(t, "r", slot, key, fallback)
