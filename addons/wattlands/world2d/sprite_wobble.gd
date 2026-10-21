class_name SpriteWobble
extends RefCounted
## Helpers for the SpriteWobble shader (BRIEF 3.9, 3.10): sine displacement for fish tails,
## the bait ball, water and light rays, snapped to whole art pixels.
##
## Parameters: amplitude (art px), wavelength (art px along the wave axis), frequency (Hz),
## phase (cycles), `vertical` (true: columns bob up and down, wave along x, for fish;
## false: rows sway sideways, wave along y, for water and rays), a falloff range in UV along
## the wave axis, and the time source (TIME by default; set_time() for deterministic frames,
## e.g. screenshots at a given sim time).
## [codeblock]
## SpriteWobble.fish_tail(fish_sprite, true)          # facing left, tail on the right
## SpriteWobble.water(light_rays)                     # rows sway
## var mat := SpriteWobble.apply(bait_ball, 1.0, 6.0, 2.0)
## SpriteWobble.set_time(mat, sim_t)                  # optional: drive from sim time
## [/codeblock]

const SHADER_PATH := "res://addons/wattlands/world2d/sprite_wobble.gdshader"


## The SpriteWobble shader (cached by the ResourceLoader).
static func shader() -> Shader:
	return load(SHADER_PATH) as Shader


## A new wobble material.
static func make_material(amplitude_px: float = 1.0, wavelength_px: float = 16.0, frequency_hz: float = 1.0, vertical: bool = true) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader()
	set_wave(mat, amplitude_px, wavelength_px, frequency_hz)
	mat.set_shader_parameter("vertical", vertical)
	mat.set_shader_parameter("margin_px", ceilf(absf(amplitude_px)))
	return mat


## Give `item` a new wobble material and return it.
static func apply(item: CanvasItem, amplitude_px: float = 1.0, wavelength_px: float = 16.0, frequency_hz: float = 1.0, vertical: bool = true) -> ShaderMaterial:
	var mat := make_material(amplitude_px, wavelength_px, frequency_hz, vertical)
	if item != null:
		item.material = mat
	return mat


## Change the wave of an existing material (wavelength must be > 0).
static func set_wave(mat: ShaderMaterial, amplitude_px: float, wavelength_px: float, frequency_hz: float, phase: float = 0.0) -> void:
	if wavelength_px <= 0.0:
		push_error("SpriteWobble: wavelength_px must be > 0 (got %s)" % wavelength_px)
		wavelength_px = 1.0
	mat.set_shader_parameter("amplitude_px", amplitude_px)
	mat.set_shader_parameter("wavelength_px", wavelength_px)
	mat.set_shader_parameter("frequency_hz", frequency_hz)
	mat.set_shader_parameter("phase", phase)


## Fade the wobble in from UV `from_uv` (no movement) to `to_uv` (full amplitude) along the
## wave axis. Equal values switch the falloff off.
static func set_falloff(mat: ShaderMaterial, from_uv: float, to_uv: float) -> void:
	mat.set_shader_parameter("falloff_from", from_uv)
	mat.set_shader_parameter("falloff_to", to_uv)


## Drive the wave from `t` seconds instead of the engine's TIME (deterministic frames).
static func set_time(mat: ShaderMaterial, t: float) -> void:
	mat.set_shader_parameter("use_engine_time", false)
	mat.set_shader_parameter("time_s", t)


## Go back to the engine's TIME.
static func use_engine_time(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("use_engine_time", true)


## Preset: a fish seen from the side; columns bob, the body (head half) stays still and the
## tail half swings. `facing_left`: the tail is on the right (Fishing's sprites face left).
static func fish_tail(item: CanvasItem, facing_left: bool = true, amplitude_px: float = 1.0, frequency_hz: float = 2.0) -> ShaderMaterial:
	var mat := apply(item, amplitude_px, 10.0, frequency_hz, true)
	if facing_left:
		set_falloff(mat, 0.45, 1.0)
	else:
		set_falloff(mat, 0.55, 0.0)
	return mat


## Preset: water bands and light rays; rows sway sideways slowly.
static func water(item: CanvasItem, amplitude_px: float = 1.0, frequency_hz: float = 0.6) -> ShaderMaterial:
	return apply(item, amplitude_px, 8.0, frequency_hz, false)


## CPU reference of the shader's displacement in art pixels for a texel at `along_px`
## (texel index along the wave axis) and time t, with falloff weight `weight` (0..1).
## Views use it to keep attached things (a fishing line's end at the tail) in step.
static func displacement(along_px: float, t: float, amplitude_px: float, wavelength_px: float, frequency_hz: float, phase: float = 0.0, weight: float = 1.0, snap: bool = true) -> float:
	var along := floorf(along_px) + 0.5 if snap else along_px
	var d := amplitude_px * clampf(weight, 0.0, 1.0) * sin(TAU * (along / maxf(wavelength_px, 0.001) - frequency_hz * t + phase))
	return roundf(d) if snap else d
