shader_type spatial;
render_mode cull_disabled;
// Touceiras de capim modeladas no Blender (tools/blender_ground.py): a cor vem dos vértices
// (base escura, ponta palha); o vento entorta mais quanto mais alto o vértice.

uniform float wind_strength = 0.12;
uniform float wind_speed = 1.3;
uniform float brightness = 1.0;

varying float tint;

void vertex() {
	vec3 world = MODEL_MATRIX[3].xyz;
	tint = fract(sin(dot(world.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float h = max(VERTEX.y, 0.0);
	float w = sin(TIME * wind_speed + world.x * 0.35 + world.z * 0.22) * wind_strength
		+ sin(TIME * wind_speed * 2.3 + world.z * 0.9 + world.x * 0.4) * wind_strength * 0.35;
	VERTEX.x += w * h * h * 2.0;
	VERTEX.z += w * h * h * 0.8;
	// Normal para cima: o capim é iluminado como o chão (sem faces escuras de lado).
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	// Mesma normal (para cima) nos dois lados da folha: o verso não fica preto.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ALBEDO = COLOR.rgb * mix(0.85, 1.15, tint) * brightness;
	ROUGHNESS = 0.9;
	SPECULAR = 0.08;
	BACKLIGHT = vec3(0.12, 0.1, 0.05);
}
