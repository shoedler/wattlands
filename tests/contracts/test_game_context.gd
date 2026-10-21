extends GutTest
## GameContext (BRIEF 3.6): player lookups, authority, RFC 7386 merge patches and
## load_content_json with content_overrides.

var _dirs: Array[String] = []


func after_each() -> void:
	for d in _dirs:
		_remove_tree(d)
	_dirs.clear()


static func _remove_tree(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in da.get_directories():
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## JSON text after a parse, so ints and floats compare alike.
func _norm(v: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)))


func _ctx() -> GameContext:
	var ctx := GameContext.new()
	for peer: int in [1, 2, -1]:
		var s := PlayerSlot.new()
		s.peer_id = peer
		s.name = "P%d" % peer
		ctx.players.append(s)
	ctx.local_peer = 2
	return ctx


func test_player_lookups() -> void:
	var ctx := _ctx()
	assert_eq(ctx.player(1).name, "P1")
	assert_eq(ctx.player(-1).name, "P-1")
	assert_null(ctx.player(9))
	assert_eq(ctx.peers(), [1, 2, -1])
	assert_eq(ctx.local_player().name, "P2")


func test_is_authority() -> void:
	var ctx := GameContext.new()
	assert_eq(ctx.role, Wl.SOLO)
	assert_true(ctx.is_authority())
	ctx.role = Wl.HOST
	assert_true(ctx.is_authority())
	ctx.role = Wl.CLIENT
	assert_false(ctx.is_authority())


func test_defaults() -> void:
	var ctx := GameContext.new()
	assert_eq(ctx.scaling_mode, Wl.FAIR_FTP)
	assert_eq(ctx.content_overrides, {})


## RFC 7386 appendix A test cases (target, patch, result), with JSON null as Godot null.
func test_merge_patch_rfc_7386_examples() -> void:
	var cases := [
		[{"a": "b"}, {"a": "c"}, {"a": "c"}],
		[{"a": "b"}, {"b": "c"}, {"a": "b", "b": "c"}],
		[{"a": "b"}, {"a": null}, {}],
		[{"a": "b", "b": "c"}, {"a": null}, {"b": "c"}],
		[{"a": ["b"]}, {"a": "c"}, {"a": "c"}],
		[{"a": "c"}, {"a": ["b"]}, {"a": ["b"]}],
		[{"a": {"b": "c"}}, {"a": {"b": "d", "c": null}}, {"a": {"b": "d"}}],
		[{"a": [{"b": "c"}]}, {"a": [1]}, {"a": [1]}],
		[["a", "b"], ["c", "d"], ["c", "d"]],
		[{"a": "b"}, ["c"], ["c"]],
		[{"a": "foo"}, null, null],
		[{"a": "foo"}, "bar", "bar"],
		[{"e": null}, {"a": 1}, {"e": null, "a": 1}],
		[[1, 2], {"a": "b", "c": null}, {"a": "b"}],
		[{}, {"a": {"bb": {"ccc": null}}}, {"a": {"bb": {}}}],
	]
	for c: Array in cases:
		var got: Variant = GameContext.merge_patch(c[0], c[1])
		assert_eq(
			JSON.stringify(got),
			JSON.stringify(c[2]),
			"%s + %s" % [JSON.stringify(c[0]), JSON.stringify(c[1])]
		)


func test_merge_patch_does_not_mutate_the_target() -> void:
	var target := {"a": {"b": 1, "c": [1, 2]}, "d": "x"}
	var before := JSON.stringify(target)
	GameContext.merge_patch(target, {"a": {"b": null, "c": [3]}, "d": null, "e": 5})
	assert_eq(JSON.stringify(target), before)


func test_load_content_json_with_overrides() -> void:
	var dir := Paths.make_temp_dir("wattlands_content_test")
	_dirs.append(dir)
	DirAccess.make_dir_recursive_absolute(dir.path_join("waves"))
	_write(
		dir.path_join("waves/easy.json"),
		JSON.stringify({"count": 3, "hp": 10, "drop": "bronze", "boss": {"hp": 50, "armor": 2}})
	)
	_write(dir.path_join("fish.json"), JSON.stringify([{"id": "tuna"}]))
	var ctx := GameContext.new()
	ctx.content_dir = dir
	var plain: Variant = ctx.load_content_json("waves/easy.json")
	assert_eq(
		_norm(plain),
		_norm({"count": 3, "hp": 10, "drop": "bronze", "boss": {"hp": 50, "armor": 2}})
	)
	ctx.content_overrides = {"waves/easy.json": {"count": 5, "drop": null, "boss": {"armor": null}}}
	var patched: Variant = ctx.load_content_json("waves/easy.json")
	assert_eq(_norm(patched), _norm({"count": 5, "hp": 10, "boss": {"hp": 50}}))
	assert_eq(
		_norm(ctx.load_content_json("fish.json")),
		_norm([{"id": "tuna"}]),
		"files without an override load unchanged"
	)


func test_load_content_json_missing_file() -> void:
	var dir := Paths.make_temp_dir("wattlands_content_test")
	_dirs.append(dir)
	var ctx := GameContext.new()
	ctx.content_dir = dir
	assert_null(ctx.load_content_json("nope.json"))
	assert_push_error("missing content")
