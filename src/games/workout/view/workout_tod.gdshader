// Recolours an indexed world plane by time of day. Its texture stores a palette index in R
// (R = index * 2); the LUT's column is the index, its row the time of day (art/palette.mjs).
shader_type canvas_item;
uniform sampler2D lut : filter_nearest, repeat_disable;
uniform int row = 0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	int i = int(c.r * 255.0 * 0.5 + 0.5);
	vec4 p = texelFetch(lut, ivec2(i, row), 0);
	COLOR = vec4(p.rgb, p.a * c.a);
}
