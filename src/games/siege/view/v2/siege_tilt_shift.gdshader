shader_type canvas_item;
// Castellum Rotae v2's screen pass (docs/games/siege.md 3, "View"), matching the art tool's
// finish() in src/games/siege/art/raster.mjs over the baked world and the sprites together:
// tilt-shift (rows above focus_top and below focus_bottom blur by up to blur_top / blur_bottom
// over ramp_top / ramp_bottom rows; the levels approximate finish()'s three box-blur radii as
// gaussians), the warm haze over the top rows and the vignette. `blur_enabled` false is the
// rider's tilt_shift option off: sharp, with the haze and vignette kept. Draw it last, on a
// ColorRect covering the art-resolution view.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform bool blur_enabled = true;
uniform bool grade_enabled = true;
uniform float focus_top = 95.0;
uniform float focus_bottom = 500.0;
uniform float ramp_top = 80.0;
uniform float ramp_bottom = 40.0;
uniform float blur_top = 3.0;
uniform float blur_bottom = 3.0;
uniform vec3 haze_color = vec3(0.784, 0.765, 0.729);

// finish()'s blur levels: box r1 x2, r2 x3, r4 x3 passes, as gaussian sigmas in art pixels.
float sigma_for(float amt) {
	if (amt <= 1.0) {
		return 1.15 * amt;
	}
	if (amt <= 2.0) {
		return mix(1.15, 2.45, amt - 1.0);
	}
	return mix(2.45, 4.47, min(amt - 2.0, 1.0));
}

void fragment() {
	vec2 size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 px = SCREEN_UV * size;
	float y = px.y;
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	if (blur_enabled) {
		float amt = 0.0;
		if (y < focus_top) {
			amt = clamp((focus_top - y) / ramp_top, 0.0, 1.0) * blur_top;
		} else if (y > focus_bottom) {
			amt = clamp((y - focus_bottom) / ramp_bottom, 0.0, 1.0) * blur_bottom;
		}
		if (amt > 0.02) {
			float s = max(sigma_for(amt), 0.3);
			float step_px = s * 0.75;
			vec3 acc = vec3(0.0);
			float wsum = 0.0;
			for (int j = -3; j <= 3; j++) {
				for (int i = -3; i <= 3; i++) {
					vec2 o = vec2(float(i), float(j)) * step_px;
					float w = exp(-dot(o, o) / (2.0 * s * s));
					acc += texture(screen_tex, SCREEN_UV + o * SCREEN_PIXEL_SIZE).rgb * w;
					wsum += w;
				}
			}
			vec3 b = acc / wsum;
			c = mix(c, b, min(amt, 1.0));
		}
	}
	if (grade_enabled) {
		float hz = clamp(1.0 - y / 70.0, 0.0, 1.0) * 0.18;
		c = mix(c, haze_color, hz);
		vec2 v = (px - size * 0.5) / (size * 0.5);
		c *= 1.0 - 0.12 * clamp(dot(v, v) - 0.35, 0.0, 1.0);
	}
	COLOR = vec4(c, 1.0);
}
