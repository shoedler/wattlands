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
	float t = use_engine_time ? TIME : time_s;
	float bump = abs(sin(PI * (t * steps_hz + INSTANCE_CUSTOM.r)));
	if (VERTEX.y > plant_below) {
		VERTEX.y += bump * bob_height;
	}
}

void fragment() {
	// COLOR arrives ready to use: on the Compatibility renderer (4.7.2) this matches
	// LowPolyMesh's vertex-color StandardMaterial3D exactly (checked by a windowed render).
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
