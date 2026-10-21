class_name SkyAmbient
extends Node3D
## Sky, ambient light, one shadowed sun and haze for the Compatibility renderer (BRIEF 3.9;
## Siege S3 "Light: one warm, shadowed sun from the front left, the world3d sky and
## ambient, and SSAO off").
##
## Adding the node creates a WorldEnvironment (ProceduralSkyMaterial background, flat ambient
## color, linear tonemap so palette colors stay as authored, SSAO, SSIL, SDFGI and glow off)
## and a DirectionalLight3D with orthogonal shadows sized for a miniature scene. Change any
## property and call apply(), or set it before adding the node. No depth of field anywhere.
##
## Haze (Siege S3: "Environment fog if Compatibility supports it in 4.7, otherwise vertex
## colors blended toward hazy blue beyond 120 m"): Godot 4.7.2's Compatibility renderer draws
## Environment depth fog (checked with a windowed render; ADR in docs/decisions/world-kits.md),
## so haze_mode() is "fog" and apply() sets depth fog from haze_begin_m to haze_end_m. Call
## haze_mesh(lp, camera_origin) on every LowPolyMesh before build(): it does nothing while
## fog is used and blends the vertex colors when haze_mode() is "vertex" (force it with
## `haze_vertex_fallback` or on a renderer without depth fog), so games need one code path.
## [codeblock]
## var sky := SkyAmbient.new()
## sky.sun_yaw_deg = -35.0         # from the front left of a camera at +Z
## add_child(sky)
## sky.haze_mesh(scenery_lp, rig.camera_position())
## [/codeblock]

const HAZE_FOG := "fog"
const HAZE_VERTEX := "vertex"
const HAZE_OFF := "off"

var sky_top_color: Color = Color("#6f9ccc")
var sky_horizon_color: Color = Color("#c9d8e2")
var ground_horizon_color: Color = Color("#b9ccda")
var ground_bottom_color: Color = Color("#8e8983")
## Sky brightness multiplier.
var sky_energy: float = 1.0

## Flat ambient light (Compatibility-safe; the sky's radiance is not used for ambient).
var ambient_color: Color = Color("#d4d9de")
var ambient_energy: float = 0.35

var sun_color: Color = Color("#ffeccc")
var sun_energy: float = 0.3
## Sun elevation above the horizon, degrees.
var sun_elevation_deg: float = 48.0
## Sun direction around Y, degrees; 0 shines from +Z (behind a default camera) toward -Z,
## negative values bring it round to the front left of a camera looking toward -Z.
var sun_yaw_deg: float = -35.0
var shadows: bool = true
## How far from the camera shadows reach (meters); a miniature scene is seen from far away.
var shadow_max_distance: float = 400.0

var haze_enabled: bool = true
var haze_color: Color = Color("#b9ccda")
## Haze starts at this distance from the camera...
var haze_begin_m: float = 120.0
## ... and reaches haze_max at this distance.
var haze_end_m: float = 380.0
## The strongest haze blend (0..1).
var haze_max: float = 0.55
## Use the vertex-color blend even where Environment depth fog works.
var haze_vertex_fallback: bool = false

var environment: Environment = null
var world_environment: WorldEnvironment = null
var sun: DirectionalLight3D = null
var sky_material: ProceduralSkyMaterial = null


func _init() -> void:
	sky_material = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment = Environment.new()
	environment.sky = sky
	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment, false, Node.INTERNAL_MODE_FRONT)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	add_child(sun, false, Node.INTERNAL_MODE_FRONT)
	apply()


## Push every property into the environment, the sky and the sun.
func apply() -> void:
	sky_material.sky_top_color = sky_top_color
	sky_material.sky_horizon_color = sky_horizon_color
	sky_material.ground_horizon_color = ground_horizon_color
	sky_material.ground_bottom_color = ground_bottom_color
	sky_material.sky_energy_multiplier = sky_energy
	sky_material.ground_energy_multiplier = sky_energy
	sky_material.sun_angle_max = 30.0
	sky_material.sky_curve = 0.12

	var env := environment
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient_color
	env.ambient_light_energy = ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.glow_enabled = false
	env.volumetric_fog_enabled = false
	var mode := haze_mode()
	env.fog_enabled = mode == HAZE_FOG
	if mode == HAZE_FOG:
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_light_color = haze_color
		env.fog_light_energy = 1.0
		env.fog_sun_scatter = 0.0
		env.fog_density = clampf(haze_max, 0.0, 1.0)
		env.fog_depth_begin = haze_begin_m
		env.fog_depth_end = maxf(haze_end_m, haze_begin_m + 0.01)
		env.fog_depth_curve = 1.0
		env.fog_sky_affect = 0.0
		env.fog_aerial_perspective = 0.0

	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.rotation = Vector3(-deg_to_rad(sun_elevation_deg), deg_to_rad(sun_yaw_deg), 0.0)
	sun.shadow_enabled = shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = shadow_max_distance
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 1.5
	sun.shadow_blur = 1.0
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY


## "fog" (Environment depth fog), "vertex" (blend LowPolyMesh colors with haze_mesh()) or
## "off".
func haze_mode() -> String:
	if not haze_enabled:
		return HAZE_OFF
	if haze_vertex_fallback or not environment_fog_supported():
		return HAZE_VERTEX
	return HAZE_FOG


## The haze helper: blend `lp`'s vertex colors toward haze_color by distance from
## `camera_origin` when haze_mode() is "vertex"; nothing otherwise (fog does the work).
## Returns true when it changed the mesh.
func haze_mesh(lp: LowPolyMesh, camera_origin: Vector3) -> bool:
	if lp == null or haze_mode() != HAZE_VERTEX:
		return false
	lp.apply_haze(camera_origin, haze_begin_m, haze_end_m, haze_color, haze_max, true)
	return true


## The sun's direction of travel (unit vector the light shines along).
func sun_direction() -> Vector3:
	return -sun.basis.z


## Whether Environment depth fog is available. Godot 4.7's Compatibility renderer draws it
## (verified on 4.7.2); Forward+ and Mobile always do. False only on an engine whose
## Environment lacks depth fog (before 4.3).
static func environment_fog_supported() -> bool:
	for p: Dictionary in ClassDB.class_get_property_list("Environment"):
		if str(p.get("name", "")) == "fog_depth_begin":
			return true
	return false
