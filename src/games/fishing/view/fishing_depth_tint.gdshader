shader_type canvas_item;
// Turbo Reel: tints a sprite toward the water colour at its depth, so fish, lures and hints
// read as under water (FishingDepthTint sets fog and amount; 0 leaves the sprite as drawn).

uniform vec4 fog : source_color = vec4(0.36, 0.56, 0.59, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(c.rgb, fog.rgb, amount), c.a);
}
