shader_type spatial;
render_mode cull_disabled;
// Florzinhas coloridas (cor por instância via INSTANCE_CUSTOM / COLOR).

uniform float wind_strength = 0.1;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = VERTEX.y;
	VERTEX.x += sin(TIME * 1.6 + world.x * 0.4 + world.z * 0.3) * wind_strength * h;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.7;
	EMISSION = COLOR.rgb * 0.05;
}
