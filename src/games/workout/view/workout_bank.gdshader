// The earth bank's painted ground: its texture stores a ramp index in R (R = index * 17, 15 = nothing),
// and the time of day sets the ramp (WorkoutBankTile.ramp).
shader_type canvas_item;
uniform vec3 ramp[15];
void fragment() {
	int i = int(texture(TEXTURE, UV).r * 15.0 + 0.5);
	COLOR = i >= 15 ? vec4(0.0) : vec4(ramp[i], 1.0);
}
