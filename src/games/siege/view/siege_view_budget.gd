class_name SiegeViewBudget
extends RefCounted
## Counts what a built SiegeView costs the renderer (brief 3 "Budget at the enemy cap": <= 250
## draw calls, <= 400k triangles, <= 60 Label3Ds, one shadowed light, no per-enemy nodes for
## Raiders, Shield walls or Horsemen). The tree is walked, not the renderer asked, so it works
## headless: every visible mesh surface is a draw call, a MultiMesh draws each of its surfaces
## once for all its visible instances, a Label3D is one, a particle system is one; shadow
## casters count twice (the shadow pass).

const LIMIT_DRAW_CALLS := 250
const LIMIT_TRIANGLES := 400000
const LIMIT_LABELS := 60


## {"draw_calls", "draw_calls_with_shadows", "triangles", "labels", "shadow_lights", "nodes",
## "mesh_instances", "multimeshes"}.
static func measure(root: Node) -> Dictionary:
	var out := {
		"draw_calls": 0,
		"draw_calls_with_shadows": 0,
		"triangles": 0,
		"labels": 0,
		"shadow_lights": 0,
		"nodes": 0,
		"mesh_instances": 0,
		"multimeshes": 0,
	}
	_walk(root, out, true)
	return out


static func mesh_triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var n := 0
	for i in mesh.get_surface_count():
		var idx: int = mesh.surface_get_array_index_len(i)
		var verts: int = mesh.surface_get_array_len(i)
		n += floori(float(idx if idx > 0 else verts) / 3.0)
	return n


static func _walk(node: Node, out: Dictionary, parent_shown: bool) -> void:
	out["nodes"] = int(out["nodes"]) + 1
	var is_shown := parent_shown
	if node is Node3D:
		is_shown = parent_shown and (node as Node3D).visible
	if node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		out["multimeshes"] = int(out["multimeshes"]) + 1
		if is_shown and mmi.multimesh != null and mmi.multimesh.visible_instance_count != 0:
			var shown := mmi.multimesh.visible_instance_count
			if shown < 0:
				shown = mmi.multimesh.instance_count
			var surfaces := (
				mmi.multimesh.mesh.get_surface_count() if mmi.multimesh.mesh != null else 0
			)
			var casts := mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			out["draw_calls"] = int(out["draw_calls"]) + surfaces
			out["draw_calls_with_shadows"] = (
				int(out["draw_calls_with_shadows"]) + surfaces * (2 if casts else 1)
			)
			out["triangles"] = int(out["triangles"]) + shown * mesh_triangles(mmi.multimesh.mesh)
	elif node is MeshInstance3D:
		var mi := node as MeshInstance3D
		out["mesh_instances"] = int(out["mesh_instances"]) + 1
		if is_shown and mi.mesh != null:
			var surfaces := mi.mesh.get_surface_count()
			var casts := mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			out["draw_calls"] = int(out["draw_calls"]) + surfaces
			out["draw_calls_with_shadows"] = (
				int(out["draw_calls_with_shadows"]) + surfaces * (2 if casts else 1)
			)
			out["triangles"] = int(out["triangles"]) + mesh_triangles(mi.mesh)
	elif node is Label3D:
		if is_shown and (node as Label3D).text != "":
			out["labels"] = int(out["labels"]) + 1
			out["draw_calls"] = int(out["draw_calls"]) + 1
			out["draw_calls_with_shadows"] = int(out["draw_calls_with_shadows"]) + 1
	elif node is CPUParticles3D:
		var ps := node as CPUParticles3D
		if is_shown and ps.emitting:
			out["draw_calls"] = int(out["draw_calls"]) + 1
			out["draw_calls_with_shadows"] = int(out["draw_calls_with_shadows"]) + 1
			out["triangles"] = int(out["triangles"]) + ps.amount * 12
	elif node is DirectionalLight3D:
		if (node as DirectionalLight3D).shadow_enabled:
			out["shadow_lights"] = int(out["shadow_lights"]) + 1
	for c in node.get_children(true):
		_walk(c, out, is_shown)
