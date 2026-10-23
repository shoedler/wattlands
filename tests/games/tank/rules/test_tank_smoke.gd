extends GutTest
## Whole sessions through the rules alone (TankRig): every crew plays ashfall_road and the drill to
## the cool-down with compliant riders and no input. The numbers are printed for the balance work.


func _describe(r: TankRig) -> String:
	var parts: Array[String] = []
	for i in r.segs().size():
		var s := r.content.segment(i)
		parts.append(
			(
				"%s%d=%.0f%s"
				% [
					str(s["type"]).substr(0, 3),
					int(s["stage"]),
					r.seg_len.get(i, -1.0),
					str(r.ended_by.get(i, "?")).substr(0, 1)
				]
			)
		)
	return " ".join(parts)


func _damage(r: TankRig) -> String:
	var per := {}
	var seg := -1
	for e in r.events:
		if e["type"] == "segment":
			seg = int(e["i"])
		if e["type"] == "hit" and int(e["on"]) == TankEvents.ON_TANK:
			per[seg] = float(per.get(seg, 0.0)) + float(e["dmg"])
	var out: Array[String] = []
	for k: int in per:
		out.append("%d:%.0f" % [k, per[k]])
	return " ".join(out)


func test_print_sessions() -> void:
	for crew in [1, 2, 3]:
		var rig := TankRig.new(crew)
		var t := rig.play()
		print(
			(
				"crew %d: %.0fs outcome=%s breakdowns=%d overruns=%d kills=%s hits=%d/%d hp=%s"
				% [
					crew,
					t,
					rig.state.outcome,
					rig.state.score.breakdowns,
					rig.state.score.overruns,
					rig.state.score.kills,
					rig.state.score.hits,
					rig.state.score.shots,
					rig.state.score.hp_by_segment
				]
			)
		)
		print("   ", _describe(rig))
		print("   dmg ", _damage(rig))
		assert_true(rig.in_cooldown(), "crew %d reached the cool-down" % crew)
