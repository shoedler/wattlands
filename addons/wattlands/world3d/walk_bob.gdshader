shader_type spatial;
render_mode cull_back, specular_disabled;
// Walk bob for MultiMesh crowds (Siege S3 "Each type is one MultiMesh with a vertex-shader
// walk bob"). Vertex colors (as LowPolyMesh writes them) times the instance color, fully
// rough; vertices above `plant_below` (local y) lift by a bump per step whose phase is
// INSTANCE_CUSTOM.r (0..1), so a column of figures doesn't move in lockstep. Created by
// MultiMeshScatter.walk_bob_material().

uniform float bob_height = 0.08;
uniform float steps_hz = 2.0;
uniform float plant_below = 0.0;
uniform bool use_engine_time = true;
uniform float time_s = 0.0;

void vertex() {
	// Vertex colors are sRGB palette values, as in LowPolyMesh's StandardMaterial3D
	// (vertex_color_is_srgb): decode them only where the renderer works in linear space.
	// Compatibility outputs sRGB (OUTPUT_IS_SRGB), so there COLOR is used as it is.
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	}
	float t = use_engine_time ? TIME : time_s;
	float bump = abs(sin(PI * (t * steps_hz + INSTANCE_CUSTOM.r)));
	if (VERTEX.y > plant_below) {
		VERTEX.y += bump * bob_height;
	}
}

void fragment() {
	// On the Compatibility renderer (4.7.2) this matches LowPolyMesh's vertex-color
	// StandardMaterial3D exactly (checked by a windowed render).
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
