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
## Everything is a LowPolyMesh or a MultiMesh: static scenery is merged per material, crowds
## and chains are MultiMeshes, so the draw count never grows with the number of enemies.
##
## Parts: SiegeTerrain (hill, roads), SiegeScatter (trees, rocks), SiegeFortBuilder (walls,
## frames, generator body), SiegeWheelView x4 (wheels, workers, pennants, shaft glow),
## SiegeChainView x4 (tower routes), SiegeGeneratorView (flywheel, the rolling drum),
## SiegeTowersView, SiegeEnemyView, SiegeEffectsView (bolts, caltrop zones), SiegeGateView, and
## the camera rig with its 4 s push-in and gate-hit shake.

## The fort fills this share of the screen width.
const FORT_WIDTH_SHARE := 0.575
const PUSH_IN_FROM := 1.45
const PUSH_IN_S := 4.0
## A single gate-HP drop of at least this much shakes the camera.
const SHAKE_MIN_HP := 8.0
const SHAKE_M := 0.15
const SHAKE_S := 0.5
const MARCH_COUNT := 20
const MARCH_RADIUS_M := 6.2
## The CanvasLayer of the 3D picture: above the session background (layer 0), below the HUD
## (HudLayer.LAYER 10); the vignette sits just above it.
const SCREEN_LAYER := 1

## The CanvasLayer that shows the 3D world, and the SubViewport that holds it.
var screen: CanvasLayer = null
var world: SubViewport = null
var game: SiegeGame = null
var state: SiegeState = null
var map: SiegeMap = null
var rig: MiniatureCameraRig = null
var sky: SkyAmbient = null
var terrain: SiegeTerrain = null
var fort: SiegeFortBuilder = null
var wheels: Array[SiegeWheelView] = []
var chains: Array[SiegeChainView] = []
var generator: SiegeGeneratorView = null
var towers: SiegeTowersView = null
var enemies: SiegeEnemyView = null
var effects: SiegeEffectsView = null
var gate: SiegeGateView = null
var march: MultiMeshScatter = null
var audio: SiegeAudio = null
## Turn off to drive refresh() yourself (tests, screenshots).
var auto_process: bool = true
var shakes: int = 0
var _built: bool = false
var _time: float = 0.0
var _last_gate_hp: float = -1.0
var _march_mat: ShaderMaterial = null


## Points the view at the state it draws (call before adding it to the tree, or any time).
func bind(p_state: SiegeState, p_map: SiegeMap) -> void:
	state = p_state
	map = p_map
	if is_inside_tree() and not _built:
		_build()


func _ready() -> void:
	if not _built and map != null:
		_build()


func _process(delta: float) -> void:
	if auto_process:
		refresh(delta)


## Reads the state into the scene: wheels, workers, chains, the drum, towers, enemies, shots,
## zones, the gate. `dt` is frame time in seconds.
func refresh(dt: float) -> void:
	if not _built or state == null:
		return
	_time += dt
	var victory := state.in_cooldown() or state.done
	for slot in wheels.size():
		var rider := state.rider_at(slot)
		wheels[slot].update(rider, dt, victory)
		chains[slot].update(rider, dt)
	generator.update(state.team_w, dt)
	enemies.interp.observe(state)
	enemies.interp.advance(dt)
	enemies.update(state, dt)
	towers.update(state, dt, enemies.drawn)
	effects.update(state, dt, enemies.drawn)
	gate.update(state, dt)
	_update_shake()
	_update_march(victory)
	audio.update(state, dt, local_peer())


## What the view draws for the enemy `e` (the one place the view reads enemy positions from;
## SiegeEnemyInterp smooths them between states).
func enemy_ground_pos(e: SiegeEnemyState) -> Vector2:
	return enemies.interp.pos_of(e, map)


func _update_shake() -> void:
	if _last_gate_hp >= 0.0 and _last_gate_hp - state.gate_hp >= SHAKE_MIN_HP:
		rig.shake(SHAKE_M, SHAKE_S)
		shakes += 1
	_last_gate_hp = state.gate_hp


func _update_march(victory: bool) -> void:
	march.visible = victory
	if not victory:
		return
	var xf: Array[Transform3D] = []
	var customs := PackedColorArray()
	var gp := map.generator_pos
	var spin := _time * 0.7
	for i in MARCH_COUNT:
		var a := spin + TAU * float(i) / float(MARCH_COUNT)
		var pos := Vector3(gp.x + cos(a) * MARCH_RADIUS_M, 0.1, gp.y + sin(a) * MARCH_RADIUS_M)
		# Marching counter-clockwise: face along the tangent.
		var tangent := Vector3(-sin(a), 0.0, cos(a))
		var facing := Basis.looking_at(tangent, Vector3.UP) * Basis().scaled(Vector3.ONE * 1.4)
		xf.append(Transform3D(facing, pos))
		customs.append(Color(fposmod(float(i) * 0.37, 1.0), 0.0, 0.0, 0.0))
	MultiMeshScatter.set_walk_time(_march_mat, _time * 2.4)
	march.set_instances(xf, PackedColorArray(), customs)


func _build() -> void:
	_built = true
	_build_screen()
	terrain = SiegeTerrain.from_map(map)
	fort = SiegeFortBuilder.new(map)
	_build_environment()
	_build_ground()
	_build_fort()
	_build_machines()
	_build_units()
	var vignette := ScreenVignette.new()
	vignette.layer = SCREEN_LAYER + 1
	add_child(vignette)
	_build_march()
	audio = SiegeAudio.new()
	audio.name = "Audio"
	add_child(audio)


## The 3D world lives in its own SubViewport shown on a CanvasLayer (above the session screen's
## background, below the HUD): the app's session screen paints an opaque background in the main
## viewport's 2D canvas, which would hide any 3D drawn straight into it. Everything below is a
## child of `world`; this node itself stays an empty Node3D.
func _build_screen() -> void:
	screen = CanvasLayer.new()
	screen.name = "Screen"
	screen.layer = SCREEN_LAYER
	add_child(screen)
	var container := SubViewportContainer.new()
	container.name = "Container"
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(container)
	world = SubViewport.new()
	world.name = "World"
	world.own_world_3d = true
	world.handle_input_locally = false
	world.msaa_3d = Viewport.MSAA_2X
	world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world.size = Vector2i(1920, 1080)
	container.add_child(world)


func _build_environment() -> void:
	sky = SkyAmbient.new()
	sky.name = "SkyAmbient"
	world.add_child(sky)
	rig = MiniatureCameraRig.new()
	rig.name = "CameraRig"
	world.add_child(rig)
	var cam: Dictionary = map.data.get("camera", {})
	var tgt: Array = cam.get("target", [0, 0, 22])
	rig.target = Vector3(float(tgt[0]), float(tgt[1]), float(tgt[2]))
	rig.pitch_deg = float(cam.get("pitch_deg", 42.0))
	rig.fov_deg = float(cam.get("fov_deg", 32.0))
	rig.yaw_deg = float(cam.get("yaw_deg", 0.0))
	rig.fit_width(map.fort_size.x / FORT_WIDTH_SHARE)
	rig.push_in(PUSH_IN_FROM, float(cam.get("push_in_s", PUSH_IN_S)))


func _build_ground() -> void:
	var ground := LowPolyMesh.new()
	terrain.add_to(ground)
	terrain.add_roads_to(ground, map)
	sky.haze_mesh(ground, rig.camera_position())
	world.add_child(ground.make_instance("Ground"))
	for mm in SiegeScatter.build(map, terrain):
		world.add_child(mm)


func _build_fort() -> void:
	var lp := fort.build_static()
	sky.haze_mesh(lp, rig.camera_position())
	world.add_child(lp.make_instance("Fort"))


func _build_machines() -> void:
	for slot in 4:
		var look := slot_look_of(slot)
		var rider := state.rider_at(slot) if state != null else null
		var wheel := SiegeWheelView.new()
		wheel.setup(slot, fort, look, rider != null and rider.is_bot)
		world.add_child(wheel)
		wheels.append(wheel)
		var chain := SiegeChainView.new()
		chain.setup(slot, fort, look)
		world.add_child(chain)
		chains.append(chain)
	generator = SiegeGeneratorView.new()
	generator.setup(fort)
	world.add_child(generator)


func _build_units() -> void:
	towers = SiegeTowersView.new()
	towers.setup(fort)
	world.add_child(towers)
	enemies = SiegeEnemyView.new()
	enemies.setup(map, terrain)
	world.add_child(enemies)
	effects = SiegeEffectsView.new()
	effects.setup(terrain, towers)
	world.add_child(effects)
	gate = SiegeGateView.new()
	gate.setup(fort)
	world.add_child(gate)


func _build_march() -> void:
	march = MultiMeshScatter.new()
	march.name = "VictoryMarch"
	march.setup(SiegeUnitMeshes.worker().build(), MARCH_COUNT, true, true)
	_march_mat = MultiMeshScatter.walk_bob_material(0.14, 1.0, 0.3)
	MultiMeshScatter.set_walk_time(_march_mat, 0.0)
	march.material_override = _march_mat
	march.visible = false
	world.add_child(march)


## The local rider's peer (the module's, else the first rider's): whose denarii the coins follow.
func local_peer() -> int:
	if game != null and game.ctx != null:
		return game.ctx.local_peer
	return state.riders[0].peer if state != null and not state.riders.is_empty() else 0


## The look (color, pattern) of `slot`: the player slot's when the module is attached, else
## the platform's Wl.slot_look.
func slot_look_of(slot: int) -> Dictionary:
	if game != null and game.ctx != null:
		for p in game.ctx.players:
			if p.slot_index == slot:
				return {
					"color": p.color, "pattern": p.pattern, "shape": p.shape, "hollow": p.hollow
				}
	return Wl.slot_look(slot)


## Draws `frames` frames of `dt` seconds without waiting for _process (tests, screenshots).
func settle(frames: int = 1, dt: float = 1.0 / 60.0) -> void:
	for i in frames:
		refresh(dt)
		if rig != null:
			rig.tick(dt)
