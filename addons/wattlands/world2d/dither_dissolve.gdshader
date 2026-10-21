shader_type canvas_item;
// DitherDissolve: an ordered-dither (4 x 4 Bayer) fade for pixel-art effects (Fishing F3.3:
// "effects end in a dither dissolve"). `amount` 0 shows the sprite, 1 hides it; in between,
// texels drop out in a fixed Bayer pattern instead of turning translucent, so the sprite
// keeps hard pixel edges. `cell_px` groups texels into bigger dither cells. Use the
// DitherDissolve helper.

uniform float amount = 0.0;
uniform float cell_px = 1.0;

// Vertex color times modulate (fragment's COLOR already includes the texture sample).
varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

int bayer2(int x, int y) {
	return (x ^ y) * 2 + y;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	ivec2 cell = ivec2(floor(UV / TEXTURE_PIXEL_SIZE / max(cell_px, 1.0)));
	int x = cell.x & 3;
	int y = cell.y & 3;
	int b = 4 * bayer2(x & 1, y & 1) + bayer2((x >> 1) & 1, (y >> 1) & 1);
	float threshold = (float(b) + 0.5) / 16.0;
	if (threshold < amount) {
		c.a = 0.0;
	}
	COLOR = c * v_modulate;
}
