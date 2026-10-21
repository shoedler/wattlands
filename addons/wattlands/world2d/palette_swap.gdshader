shader_type canvas_item;
// PaletteSwap (BRIEF 3.9): replaces each key color with the swap color at the same index,
// so one sprite drawn with a red key ramp shows every player's color. Exact palette sprites
// (pixelate output, lossless import) match within `tolerance` per channel. Source alpha and
// the CanvasItem's modulate are kept. Use the PaletteSwap helper to set the uniforms.
// Up to 8 keys, as separate uniforms (key_0..key_7, swap_0..swap_7) so each shows up in the
// inspector and in get_shader_parameter().

uniform vec4 key_0;
uniform vec4 key_1;
uniform vec4 key_2;
uniform vec4 key_3;
uniform vec4 key_4;
uniform vec4 key_5;
uniform vec4 key_6;
uniform vec4 key_7;
uniform vec4 swap_0;
uniform vec4 swap_1;
uniform vec4 swap_2;
uniform vec4 swap_3;
uniform vec4 swap_4;
uniform vec4 swap_5;
uniform vec4 swap_6;
uniform vec4 swap_7;
uniform int key_count = 0;
uniform float tolerance = 0.02;

// The vertex color times modulate. In fragment(), COLOR already includes the texture sample,
// so multiplying the swapped sample by it would apply the texture twice.
varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

bool near(vec3 a, vec3 b) {
	vec3 d = abs(a - b);
	return max(d.r, max(d.g, d.b)) <= tolerance;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 o = c.rgb;
	if (key_count > 0 && near(o, key_0.rgb)) {
		c.rgb = swap_0.rgb;
	} else if (key_count > 1 && near(o, key_1.rgb)) {
		c.rgb = swap_1.rgb;
	} else if (key_count > 2 && near(o, key_2.rgb)) {
		c.rgb = swap_2.rgb;
	} else if (key_count > 3 && near(o, key_3.rgb)) {
		c.rgb = swap_3.rgb;
	} else if (key_count > 4 && near(o, key_4.rgb)) {
		c.rgb = swap_4.rgb;
	} else if (key_count > 5 && near(o, key_5.rgb)) {
		c.rgb = swap_5.rgb;
	} else if (key_count > 6 && near(o, key_6.rgb)) {
		c.rgb = swap_6.rgb;
	} else if (key_count > 7 && near(o, key_7.rgb)) {
		c.rgb = swap_7.rgb;
	}
	COLOR = c * v_modulate;
}
