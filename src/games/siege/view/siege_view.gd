class_name SiegeView
extends Node3D
## The 3D miniature (brief 3 "Scene"). Owner: B3 "view" (src/games/siege/view/, with world/ and
## units/ below it). It only reads state: never mutates SiegeState, never sends intents, never
## calls ctx.directives. Builds headless (tests build it from a fixture state).
##
## Contract the module (B2) relies on:
##   var view := SiegeView.new(); view.bind(state, map); (the module's make_view() also sets
##   view.game = self so the view can read ctx.players for colors and patterns)
##   refresh(dt) runs every frame from _process (auto_process true) or from tests.
## The view keeps its own cosmetic RNG seeded from ctx.seed if it needs one.
##
## G0 status: a placeholder (camera rig, sky, ground, pad plinths). B3 replaces the body.

var game: SiegeGame = null
var state: SiegeState = null
var map: SiegeMap = null
var rig: MiniatureCameraRig = null
## Turn off to drive refresh() yourself (tests, screenshots).
var auto_process: bool = true
var _built: bool = false


## Points the view at the state it draws (call before adding it to the tree, or any time).
func bind(p_state: SiegeState, p_map: SiegeMap) -> void:
	state = p_state
	map = p_map
	if is_inside_tree() and not _built:
		_build()


func _ready() -> void:
	if not _built:
		_build()


func _process(delta: float) -> void:
	if auto_process:
		refresh(delta)


## Reads the state into the scene (B3: wheels, workers, chains, enemies, towers, gate, drum).
func refresh(_dt: float) -> void:
	pass


func _build() -> void:
	_built = true
	var sky := SkyAmbient.new()
	sky.name = "SkyAmbient"
	add_child(sky)
	rig = MiniatureCameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	var cam: Dictionary = map.data.get("camera", {}) if map != null else {}
	var tgt: Array = cam.get("target", [0, 0, 22])
	rig.target = Vector3(float(tgt[0]), float(tgt[1]), float(tgt[2]))
	rig.pitch_deg = float(cam.get("pitch_deg", 42.0))
	rig.fov_deg = float(cam.get("fov_deg", 32.0))
	var lp := LowPolyMesh.new()
	lp.add_plane(Vector2(260, 260), Color("#C7A15A"))
	if map != null:
		for n in range(1, SiegeIds.PAD_COUNT + 1):
			var p := map.pad_pos(n)
			lp.add_box(
				Vector3(4, 1, 4),
				Color("#E8E2D4"),
				Transform3D(Basis.IDENTITY, Vector3(p.x, 0.5, p.y))
			)
	add_child(lp.make_instance("Ground"))
