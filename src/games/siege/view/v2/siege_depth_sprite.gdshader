shader_type canvas_item;
// Castellum Rotae v2's depth-tested sprites (docs/games/siege.md 3, "View"). Every frame of the
// bake atlases has a depth twin (depth_atlas, same layout): the pixel's depth relative to the
// frame's anchor. The drawer passes the anchor's depth in the modulate colour (R, G: 16 bits in
// the world encoding), with the ramp row and the sun shade in B (row * 16 + shade 0..15) and the
// opacity in A. A pixel whose depth (anchor + frame) is behind the baked world's depth at its
// pixel is discarded, so sprites vanish behind walls. Key-ramp pixels (magenta, R = B = 255,
// G = key_g0 + key_step * index) take entry `index` of ramp row `row`: a slot's hue or an idle
// material. Compatibility renderer: plain textures and texelFetch only.

uniform sampler2D depth_atlas : filter_nearest, repeat_disable;
uniform sampler2D world_depth : filter_nearest, repeat_disable;
uniform sampler2D ramps : filter_nearest, repeat_disable;
// The canvas position of the world image's top-left pixel, and that image's size (SiegeBakeBank).
uniform vec2 art_origin = vec2(0.0);
uniform vec2 art_size = vec2(960.0, 540.0);
uniform bool depth_test = true;
uniform float depth_bias = 0.04;
uniform float world_offset = -400.0;
uniform float world_scale = 64.0;
uniform float sprite_zero = 32768.0;
uniform float sprite_scale = 256.0;
uniform float key_g0 = 4.0;
uniform float key_step = 8.0;

varying vec4 v_data;
varying vec2 v_art;

float to_byte(float v) {
	return floor(v * 255.0 + 0.5);
}

void vertex() {
	v_data = COLOR;
	v_art = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - art_origin;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.01) {
		discard;
	}
	vec4 dt = texture(depth_atlas, UV);
	float anchor_d = (to_byte(v_data.r) * 256.0 + to_byte(v_data.g)) / world_scale + world_offset;
	float d = anchor_d + (to_byte(dt.r) * 256.0 + to_byte(dt.g) - sprite_zero) / sprite_scale;
	if (depth_test) {
		ivec2 px = ivec2(floor(v_art));
		if (px.x >= 0 && px.y >= 0 && px.x < int(art_size.x) && px.y < int(art_size.y)) {
			vec4 w = texelFetch(world_depth, px, 0);
			float wv = to_byte(w.r) * 256.0 + to_byte(w.g);
			if (wv > 0.5 && d < wv / world_scale + world_offset - depth_bias) {
				discard;
			}
		}
	}
	float info = to_byte(v_data.b);
	float row = floor(info / 16.0);
	float shade = mod(info, 16.0) / 15.0;
	vec3 rgb = c.rgb;
	if (c.a > 0.99) {
		if (c.r > 0.985 && c.b > 0.985) {
			float idx = floor((to_byte(c.g) - key_g0) / key_step + 0.5);
			rgb = texelFetch(ramps, ivec2(int(idx), int(row)), 0).rgb;
		}
		rgb *= 0.62 + 0.38 * shade;
	}
	COLOR = vec4(rgb, c.a * v_data.a);
}
