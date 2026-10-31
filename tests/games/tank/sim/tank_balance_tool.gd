extends SceneTree
## Runs the rules-level balance harness (TankBalanceHarness) over a matrix and prints one line per
## run (crew, seed, difficulty: losses, breakdowns, near threats killed/escaped, the hull per fight,
## grade, segment times), then T1-T5 and the difficulty table D1 (informational; --strict exits 1 on
## a miss).
##
##   tools/godot.sh --headless --path . -s tests/games/tank/sim/tank_balance_tool.gd -- \
##       [--crews=1,2,3] [--seeds=1,2,3] [--compliance=1.0,0.85,0.7] \
##       [--difficulties=easy,normal,hard] [--content=ashfall_road,ambush_15] \
##       [--enemy-mult=1] [--module] [--verbose] [--strict]
##
## Defaults: crews 1-4, seeds 1-3, compliance 1.0 / 0.85 / 0.7, Normal, on ashfall_road. --verbose
## adds each run's full block. Nothing here can reach a trainer or a network (recording sinks only).


func _initialize() -> void:
	var args: Dictionary = CmdLine.parse(OS.get_cmdline_user_args())
	var crews := _numbers(args, "crews", [1, 2, 3, 4])
	var seeds := _numbers(args, "seeds", [1, 2, 3])
	var comps := _numbers(args, "compliance", [1.0, 0.85, 0.7])
	var contents := _last(args, "content", "ashfall_road").split(",", false)
	var diffs := _last(args, "difficulties", TankIds.DIFF_NORMAL).split(",", false)
	var mult := int(_last(args, "enemy-mult", "1"))
	var results: Array = []
	var failed := 0
	for content in contents:
		for diff in diffs:
			for crew in crews:
				for c in comps:
					for s in seeds:
						var cfg := {
							"crew": int(crew),
							"seed": int(s),
							"compliance": float(c),
							"content": content,
							"difficulty": diff,
							"enemy_mult": mult,
							"via_module": args.has("module"),
						}
						var r := TankBalanceHarness.run(cfg)
						print(TankBalanceHarness.line(r))
						if r.has("error"):
							failed += 1
							continue
						if args.has("verbose"):
							print(TankBalanceHarness.format(r))
						results.append(r)
	print("--- targets (informational) ---")
	var missed := failed
	for t: Dictionary in TankBalanceTargets.evaluate(results):
		print(t["text"])
		if not bool(t["ok"]):
			missed += 1
	var table := TankBalanceTargets.d1(results)
	for row: String in table["rows"]:
		print(row)
	print(table["text"])
	if not bool(table["ok"]):
		missed += 1
	quit(1 if (args.has("strict") and missed > 0) else 0)


func _last(args: Dictionary, key: String, fallback: String) -> String:
	var v: Variant = args.get(key, [])
	if v is Array and not (v as Array).is_empty():
		return str((v as Array).back())
	return fallback


func _numbers(args: Dictionary, key: String, fallback: Array) -> Array:
	var out: Array = []
	for part in _last(args, key, "").split(",", false):
		out.append(float(part))
	return out if not out.is_empty() else fallback
