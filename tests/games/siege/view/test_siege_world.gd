extends GutTest
## The static world: the terrain and its roads, the scatter, the fort builder (brief 3
## "Scene"), and the palette rules.

var _map: SiegeMap = null
var _terrain: SiegeTerrain = null


func before_all() -> void:
	_map = SiegeFixtures.content("short").map
	_terrain = SiegeTerrain.from_map(_map)


func test_the_plateau_under_the_fort_is_flat() -> void:
	for p: Vector2 in [Vector2(0, 0), Vector2(-30, -24), Vector2(30, 24), Vector2(0, 34)]:
		assert_almost_eq(_terrain.height_at(p.x, p.y), 0.0, 0.01, "plateau at %s" % p)


func test_the_hill_falls_away_from_the_plateau() -> void:
	assert_lt(_terrain.height_at(0, 120), -5.0)
	assert_lt(_terrain.height_at(-120, 0), -5.0)


func test_height_at_is_the_drawn_meshs_own_surface() -> void:
	# At a grid vertex it is the vertex; at a facet centre the mean of its three corners.
	var cs := _terrain.cell_size()
	var x := -_terrain.HALF_M + 40.0 * cs
	var z := -_terrain.HALF_M + 33.0 * cs
	assert_almost_eq(_terrain.height_at(x, z), _terrain.vertex_height(40, 33), 1e-4)
	var h00 := _terrain.vertex_height(40, 33)
	var h10 := _terrain.vertex_height(41, 33)
	var h01 := _terrain.vertex_height(40, 34)
	var h11 := _terrain.vertex_height(41, 34)
	var cx := x + cs * 0.5
	var cz := z + cs * 0.5
	# (40 + 33) is odd: the diagonal runs p10-p01, so the centre lies on it.
	assert_almost_eq(_terrain.height_at(cx, cz), (h10 + h01) * 0.5, 1e-3)
	assert_between(
		_terrain.height_at(x + cs * 0.2, z + cs * 0.2), minf(h00, h10) - 5.0, maxf(h00, h11) + 5.0
	)


func test_the_terrain_is_deterministic() -> void:
	var other := SiegeTerrain.from_map(_map)
	for p: Vector2 in [Vector2(10, 90), Vector2(-60, 20), Vector2(100, -40)]:
		assert_eq(other.height_at(p.x, p.y), _terrain.height_at(p.x, p.y))


func test_roads_ribbons_lie_on_the_ground() -> void:
	var lp := LowPolyMesh.new()
	_terrain.add_roads_to(lp, _map)
	assert_gt(lp.triangle_count(), 100)
	var verts := lp.vertices()
	for i in range(0, verts.size(), 17):
		var v := verts[i]
		var ground := _terrain.height_at(v.x, v.z)
		assert_almost_eq(v.y, ground + SiegeTerrain.ROAD_LIFT_M, 0.05, "road vertex at %s" % v)


func test_facets_are_ochre_with_rock_on_steep_ground() -> void:
	var flat := _terrain.facet_color(Vector3(5, 0, 5), Vector3.UP)
	var steep := _terrain.facet_color(Vector3(5, 0, 5), Vector3(0.8, 0.6, 0.0).normalized())
	assert_lt(steep.get_luminance(), flat.get_luminance(), "steep ground reads darker, greyer")
	assert_lt(absf(steep.r - steep.b), absf(flat.r - flat.b), "and less saturated")


func test_the_scatter_counts_and_exclusions() -> void:
	var mms := SiegeScatter.build(_map, _terrain)
	assert_eq(mms.size(), 3)
	var names: Array[String] = []
	for mm in mms:
		names.append(mm.name)
		assert_eq(mm.visible_count(), mm.capacity(), "%s: every instance placed" % mm.name)
	assert_eq(names, ["Cypress", "Olive", "Rocks"] as Array[String])
	assert_eq([mms[0].capacity(), mms[1].capacity(), mms[2].capacity()], [600, 400, 300])
	# Nothing grows inside the fort or on a road.
	var excl := SiegeScatter.exclusions(_map)
	for mm in mms:
		for i in mm.visible_count():
			var o := mm.instance_transform(i).origin
			var p := Vector2(o.x, o.z)
			assert_false(MultiMeshScatter.is_excluded(p, excl), "%s %d at %s" % [mm.name, i, p])
			assert_false(absf(p.x) < 30.0 and absf(p.y) < 24.0, "inside the fort at %s" % p)


func test_the_scatter_is_the_same_every_time() -> void:
	var a := SiegeScatter.build(_map, _terrain)
	var b := SiegeScatter.build(_map, _terrain)
	for k in 3:
		assert_eq(a[k].visible_count(), b[k].visible_count())
		assert_eq(a[k].instance_transform(7).origin, b[k].instance_transform(7).origin)
	for mm in a:
		mm.free()
	for mm in b:
		mm.free()


func test_fort_geometry_follows_the_map() -> void:
	var fort := SiegeFortBuilder.new(_map)
	assert_eq(fort.fort_half, Vector2(32, 26))
	assert_eq(fort.wall_h, 6.0)
	for pad in [2, 5, 7, 8]:
		assert_true(fort.is_corner_pad(pad))
		assert_almost_eq(
			fort.pad_top_y(pad),
			6.0 + SiegeFortBuilder.CORNER_EXTRA_H + SiegeFortBuilder.PLINTH_H,
			1e-5
		)
	for pad in [1, 3, 4, 6]:
		assert_false(fort.is_corner_pad(pad))
		assert_almost_eq(fort.pad_top_y(pad), 6.0 + SiegeFortBuilder.PLINTH_H, 1e-5)
	# A wheel faces the generator along its local +Z.
	for slot in 4:
		var t := fort.wheel_transform(slot)
		var toward := t.basis * Vector3.BACK
		var d := _map.generator_pos - _map.wheel_pos(slot)
		assert_almost_eq(Vector2(toward.x, toward.z).dot(d.normalized()), 1.0, 1e-4)


func test_the_static_fort_is_one_mesh_with_no_crenellations() -> void:
	var fort := SiegeFortBuilder.new(_map)
	var lp := fort.build_static()
	assert_eq(lp.surface_keys().size(), 1, "one material, one draw call")
	assert_lt(lp.triangle_count(), 6000)
	var box := lp.aabb()
	assert_lte(
		box.end.y, SiegeFortBuilder.PLAQUE_CENTER.y + 3.0, "nothing towers above the counter"
	)


func test_chain_paths_end_on_the_pad_at_wall_height() -> void:
	var fort := SiegeFortBuilder.new(_map)
	var chain := SiegeChainView.new()
	chain.setup(0, fort, Wl.slot_look(0))
	for pad in range(1, 9):
		var path := chain.build_path(pad)
		assert_gte(path.size(), 3, "pad %d" % pad)
		var end := path[path.size() - 1]
		var pp := _map.pad_pos(pad)
		assert_lt(Vector2(end.x, end.z).distance_to(pp), 1.0, "ends at pad %d" % pad)
		assert_almost_eq(end.y, fort.chain_y_at(pp), 1e-4)
	chain.free()


func test_the_palette_has_no_saturated_enemy_or_scenery_colors() -> void:
	# Player colors are the only saturated hues (brief 3 "Palette").
	var slot_hues: Array[float] = []
	for c in Wl.SLOT_COLORS:
		slot_hues.append(c.h)
	for mesh: LowPolyMesh in [
		SiegeUnitMeshes.raider(),
		SiegeUnitMeshes.shield_wall(),
		SiegeUnitMeshes.horseman(),
		SiegeUnitMeshes.ram(),
	]:
		for col in mesh.colors():
			assert_lt(col.s, 0.6, "enemy color %s is muted" % col)
			var near := false
			for h in slot_hues:
				if absf(col.h - h) < 0.03 and col.s > 0.7 and col.v > 0.5:
					near = true
			assert_false(near, "enemy color %s is no player color" % col)
