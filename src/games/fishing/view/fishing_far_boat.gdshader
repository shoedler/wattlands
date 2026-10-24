shader_type canvas_item;
// Turbo Reel: another rider's boat on the farther row. Swaps the two key reds for the slot
// colour (like PaletteSwap), mixes a touch of haze toward the sky, and hides everything below the
// boat's own waterline (clip_y, view px), which the nearer water covers.

uniform vec4 key0 : source_color;
uniform vec4 key1 : source_color;
uniform vec4 swap0 : source_color;
uniform vec4 swap1 : source_color;
uniform bool swap_keys = false;
uniform vec4 haze : source_color = vec4(0.82, 0.87, 0.85, 1.0);
uniform float haze_amount : hint_range(0.0, 1.0) = 0.2;
uniform float clip_y = 100000.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	if (world_pos.y >= clip_y) {
		discard;
	}
	vec4 c = texture(TEXTURE, UV) * COLOR;
	if (swap_keys) {
		if (distance(c.rgb, key0.rgb) < 0.02) {
			c.rgb = swap0.rgb;
		} else if (distance(c.rgb, key1.rgb) < 0.02) {
			c.rgb = swap1.rgb;
		}
	}
	COLOR = vec4(mix(c.rgb, haze.rgb, haze_amount), c.a);
}
