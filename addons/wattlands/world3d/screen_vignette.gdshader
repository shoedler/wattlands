shader_type canvas_item;
// ScreenVignette: darkens the screen corners by at most `strength` (Siege S3: "A vignette
// under the HUD darkens the corners by at most 12%"). Drawn on a full-screen ColorRect;
// `inner` is where darkening starts, as a fraction of the centre-to-corner distance.

uniform float strength = 0.12;
uniform float inner = 0.55;

void fragment() {
	vec2 d = (UV - vec2(0.5)) * 2.0;
	float r = length(d) / sqrt(2.0);
	float a = clamp(strength, 0.0, 1.0) * smoothstep(inner, 1.0, r);
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
