shader_type canvas_item;
// SpriteWobble (BRIEF 3.9, 3.10): a pixel-snapped sine displacement for fish tails, bait
// balls, water bands and light rays. `vertical` true: each texel column moves up and down
// with a wave that travels along x (a swimming fish). false: each row moves left and right
// with a wave along y (water, heat shimmer, light rays). The wobble fades in from
// `falloff_from` to `falloff_to` (UV along the wave axis; equal values = full everywhere),
// so a fish body can stay still while its tail swings. Use the SpriteWobble helper.
// Works on whole-texture sprites (Sprite2D without region, TextureRect); `margin_px` grows
// the quad along the displacement axis so displaced pixels are not clipped.

uniform float amplitude_px = 1.0;
uniform float wavelength_px = 16.0;
uniform float frequency_hz = 1.0;
uniform float phase = 0.0; // in cycles
uniform bool vertical = true;
uniform float falloff_from = 0.0;
uniform float falloff_to = 0.0;
uniform bool pixel_snap = true;
uniform bool use_engine_time = true;
uniform float time_s = 0.0;
uniform float margin_px = 0.0;

// The vertex color times modulate (fragment's COLOR already includes the texture sample).
varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
	if (margin_px > 0.0) {
		vec2 dir = vertical ? vec2(0.0, 1.0) : vec2(1.0, 0.0);
		vec2 grow = (UV * 2.0 - 1.0) * dir * margin_px;
		VERTEX += grow;
		UV += grow * TEXTURE_PIXEL_SIZE;
	}
}

void fragment() {
	vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;
	float t = use_engine_time ? TIME : time_s;
	float along = vertical ? UV.x * tex_size.x : UV.y * tex_size.y;
	float u = vertical ? UV.x : UV.y;
	if (pixel_snap) {
		along = floor(along) + 0.5;
		u = along / (vertical ? tex_size.x : tex_size.y);
	}
	float w = 1.0;
	if (abs(falloff_to - falloff_from) > 0.0001) {
		w = clamp((u - falloff_from) / (falloff_to - falloff_from), 0.0, 1.0);
	}
	float d = amplitude_px * w * sin(TAU * (along / max(wavelength_px, 0.001) - frequency_hz * t + phase));
	if (pixel_snap) {
		d = round(d);
	}
	vec2 offset = vertical ? vec2(0.0, d) : vec2(d, 0.0);
	vec2 uv = UV - offset * TEXTURE_PIXEL_SIZE;
	vec4 c = texture(TEXTURE, uv);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		c = vec4(0.0);
	}
	COLOR = c * v_modulate;
}
