extends SceneTree
## Runs the rules-level balance harness (TankBalanceHarness) over a matrix and prints per segment
## times, overruns, breakdowns, score, grade, the dynamo's time above 80% FTP, the loader's shell
## build times, the Bulwark's Drive share, then T1-T5 (informational; --strict exits 1 on a miss).
##
##   tools/godot.sh --headless --path . -s tests/games/tank/sim/tank_balance_tool.gd -- \
##       [--crews=1,2,3] [--seeds=1,2,3] [--compliance=1.0,0.85,0.7] [--content=ashfall_road] \
##       [--enemy-mult=1] [--module] [--strict]
##
## Defaults: crews 1-3, seeds 1-3, compliance 1.0 / 0.85 / 0.7 on ashfall_road: 27 session-length
## runs. Nothing here can reach a trainer or a network (recording sinks only).


func _initialize() -> void:
	var args: Dictionary = CmdLine.parse(OS.get_cmdline_user_args())
	var crews := _numbers(args, "crews", [1, 2, 3])
	var seeds := _numbers(args, "seeds", [1, 2, 3])
	var comps := _numbers(args, "compliance", [1.0, 0.85, 0.7])
	var content := _last(args, "content", "ashfall_road")
	var mult := int(_last(args, "enemy-mult", "1"))
	var results: Array = []
	for crew in crews:
		for c in comps:
			for s in seeds:
				var cfg := {
					"crew": int(crew),
					"seed": int(s),
					"compliance": float(c),
					"content": content,
					"enemy_mult": mult,
					"via_module": args.has("module"),
				}
				var r := TankBalanceHarness.run(cfg)
				print(TankBalanceHarness.format(r))
				results.append(r)
	print("--- targets (informational) ---")
	var missed := 0
	for t: Dictionary in TankBalanceTargets.evaluate(results):
		print(t["text"])
		if not bool(t["ok"]):
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
