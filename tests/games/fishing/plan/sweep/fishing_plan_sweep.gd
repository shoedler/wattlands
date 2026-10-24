extends SceneTree
## The opt-in full sweep on the pure plan code (not a GUT test; nothing under tests/ runs it
## automatically):
##   tools/godot.sh --headless --path . -s res://tests/games/fishing/plan/sweep/fishing_plan_sweep.gd \
##       -- --seeds=200 --directive-seeds=500
## Plan properties: the workouts x seeds x 4 riders x 5 reel_pct, and every Free Roam content grown
## bite by bite over seeds. Directives: every species x directive seeds, FTP cycling 100-500 W
## (--ftp=all runs all five per seed), a random rescue on every second seed, plus rescue and AFK at
## every ramp step of a tuna run and a marlin jump for the first --stagger-seeds seeds (default
## 20) at 100, 300 and 500 W. Prints a PASS/FAIL summary; exit code 0 or 1.

const H := preload("res://tests/games/fishing/plan/fishing_plan_harness.gd")


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var fails: Array[String] = []
	fails.append_array(_plans(int(args.get("seeds", "200"))))
	var all_ftp := str(args.get("ftp", "cycle")) == "all"
	fails.append_array(_directives(int(args.get("directive-seeds", "500")), all_ftp))
	fails.append_array(_staggers(int(args.get("stagger-seeds", "20"))))
	if fails.is_empty():
		print("fishing_plan_sweep: PASS")
		quit(0)
		return
	print("fishing_plan_sweep: FAIL (%d failures)" % fails.size())
	for line in fails.slice(0, 40):
		print("  ", line)
	quit(1)


func _plans(seeds: int) -> Array[String]:
	var fails: Array[String] = []
	var plans := 0
	for trip_id: String in H.TRIPS:
		var c := H.content(trip_id)
		if not c.ok:
			fails.append("%s: content: %s" % [trip_id, c.errors])
			continue
		var slots := 0
		for seed in range(1, seeds + 1):
			for rider in 4:
				fails.append_array(H.plan_failures(c, seed, rider))
				plans += H.REEL_PCTS.size()
				slots += FishingPreroll.roll(c.trip, c.species, seed, rider).size()
		print("  %-10s %d seeds x 4 riders: %d slots" % [trip_id, seeds, slots])
	for trip_id: String in H.ROAM_TRIPS:
		var c := H.content(trip_id)
		for seed in range(1, seeds + 1):
			fails.append_array(H.roam_failures(c, seed, FishingConst.SPECIES, 12))
			plans += 12
		print("  %-10s %d seeds x 12 bites" % [trip_id, seeds])
	print("plans: %d validated (%d failures so far)" % [plans, fails.size()])
	return fails


func _directives(seeds: int, all_ftp: bool) -> Array[String]:
	var fails: Array[String] = []
	var sets: Array = []
	for id: String in FishingConst.SPECIES:
		sets.append(["roam_30", id])
	(
		sets
		. append_array(
			[
				["base_60", "mackerel"],
				["base_60", "mahi"],
				["threshold", "tuna"],
			]
		)
	)
	for st: Array in sets:
		var c := H.content(str(st[0]))
		var fights := 0
		var sent := 0
		var runs := 0
		var pulls := 0
		var above := 0.0
		for seed in range(1, seeds + 1):
			var slot: FishingPlanSlot
			if c.trip.is_scheduled():
				slot = FishingPreroll.roll(c.trip, c.species, seed, 0)[seed % 4]
			else:
				slot = H.species_slot(c, str(st[1]), seed)
			var ftps: Array = H.FTPS if all_ftp else [H.FTPS[seed % H.FTPS.size()]]
			for ftp: float in ftps:
				var staggers: Array = []
				if seed % 2 == 0:
					var r := FishingRandom.derive(seed, 5, 5)
					staggers = [[r.range_f(5.0, slot.t_nom_s * 0.7), r.range_f(3.0, 45.0)]]
				var res := H.run_fight(slot, seed, ftp, staggers)
				fails.append_array(res["fails"])
				fights += 1
				sent += int(res["sent"])
				runs += int(res["runs"])
				pulls += int(res["pulls"])
				above = maxf(above, float(res["above105"]))
		print(
			(
				"  %-9s %-8s %d fights: %d directives, %d pulls, %d runs, max %.1f s above 105 %%"
				% [st[0], st[1], fights, sent, pulls, runs, above]
			)
		)
	print("directives: %d failures so far" % fails.size())
	return fails


func _staggers(seeds: int) -> Array[String]:
	var fails: Array[String] = []
	var cases := 0
	var variants := [["rescue", 6.0], ["rescue", 45.0], ["afk", 15.0], ["afk", 70.0]]
	for st: Array in [["roam_30", "tuna"], ["roam_30", "marlin"]]:
		var c := H.content(str(st[0]))
		for seed in range(1, seeds + 1):
			var slot := H.species_slot(c, str(st[1]), seed)
			for ftp: float in [100.0, 300.0, 500.0]:
				var n := H.run_step_count(slot, seed, ftp)
				for j in range(-1, n):
					for v: Array in variants:
						fails.append_array(H.stagger_failures(slot, seed, ftp, j, v[1], v[0]))
						cases += 1
	print("staggers: %d cases (%d failures)" % [cases, fails.size()])
	return fails
