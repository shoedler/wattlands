class_name FishingAutopilot
extends RefCounted
## Autopilot's choices (brief 2.5): the strongest hint, the nearest on ties. It casts and recasts
## at once and strikes at 0.5 s (FishingRules applies those timings); it never sprints, shifts or
## changes targets. Pure; fish-rules owns this file.


## Index of the hint to cast to from flat hints [type, d, strength, ...]; -1 when there are none.
static func pick(hints: Array[float]) -> int:
	var best := -1
	for i in hints.size() / 3:
		if best < 0:
			best = i
			continue
		var s := hints[3 * i + 2]
		var bs := hints[3 * best + 2]
		if s > bs or (is_equal_approx(s, bs) and hints[3 * i + 1] < hints[3 * best + 1]):
			best = i
	return best
