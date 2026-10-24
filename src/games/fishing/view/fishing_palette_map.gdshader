shader_type canvas_item;
// Turbo Reel's palette map (FishingPaletteMap sets the uniforms): swaps each src colour for
// the dst colour at the same index, so every pixel stays a palette colour (fish and hints
// shift along the ladder with depth, the farther boats one step lighter). flat_on paints every
// opaque pixel flat_col (a hint's silhouette); rows at or below under_y (view px) take
// under_col (a hull seen through the water).

uniform vec4 src_0;
uniform vec4 src_1;
uniform vec4 src_2;
uniform vec4 src_3;
uniform vec4 src_4;
uniform vec4 src_5;
uniform vec4 src_6;
uniform vec4 src_7;
uniform vec4 dst_0;
uniform vec4 dst_1;
uniform vec4 dst_2;
uniform vec4 dst_3;
uniform vec4 dst_4;
uniform vec4 dst_5;
uniform vec4 dst_6;
uniform vec4 dst_7;
uniform int count = 0;
uniform bool flat_on = false;
uniform vec4 flat_col;
uniform float under_y = 100000.0;
uniform vec4 under_col;

varying vec2 world_pos;
varying vec4 v_modulate;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	v_modulate = COLOR;
}

bool near(vec3 a, vec3 b) {
	vec3 d = abs(a - b);
	return max(d.r, max(d.g, d.b)) <= 0.02;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * v_modulate;
	vec3 o = c.rgb;
	if (count > 0 && near(o, src_0.rgb)) {
		c.rgb = dst_0.rgb;
	} else if (count > 1 && near(o, src_1.rgb)) {
		c.rgb = dst_1.rgb;
	} else if (count > 2 && near(o, src_2.rgb)) {
		c.rgb = dst_2.rgb;
	} else if (count > 3 && near(o, src_3.rgb)) {
		c.rgb = dst_3.rgb;
	} else if (count > 4 && near(o, src_4.rgb)) {
		c.rgb = dst_4.rgb;
	} else if (count > 5 && near(o, src_5.rgb)) {
		c.rgb = dst_5.rgb;
	} else if (count > 6 && near(o, src_6.rgb)) {
		c.rgb = dst_6.rgb;
	} else if (count > 7 && near(o, src_7.rgb)) {
		c.rgb = dst_7.rgb;
	}
	if (flat_on) {
		c.rgb = flat_col.rgb;
	}
	if (world_pos.y >= under_y) {
		c.rgb = under_col.rgb;
	}
	COLOR = c;
}
