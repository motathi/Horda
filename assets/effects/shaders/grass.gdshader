shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
// Tufos de grama estilizados (vários "fios" desenhados num quad), com vento.

uniform vec3 base_color : source_color = vec3(0.2, 0.36, 0.1);
uniform vec3 tip_color : source_color = vec3(0.46, 0.66, 0.22);
uniform float wind_strength = 0.18;
uniform float wind_speed = 1.4;
uniform float blades = 9.0;

varying float tint;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	tint = fract(sin(dot(world.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float h = 1.0 - UV.y;
	float w = sin(TIME * wind_speed + world.x * 0.35 + world.z * 0.22) * wind_strength
		+ sin(TIME * wind_speed * 2.3 + world.z * 0.9) * wind_strength * 0.3;
	VERTEX.x += w * h * h;
	VERTEX.z += w * 0.5 * h * h;
	// Normal apontando para cima: iluminação igual ao terreno (sem "quads" visíveis).
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	float h = 1.0 - UV.y;
	float x = UV.x * blades;
	float id = floor(x);
	float rnd = fract(sin(id * 91.7 + tint * 13.0) * 4375.85);
	float local = fract(x) - 0.5;
	float height = mix(0.45, 1.0, rnd);
	float width = 0.3 * (1.0 - h / height);
	float lean = (rnd - 0.5) * 0.5 * h;
	if (abs(local - lean) > width || h > height) {
		discard;
	}
	vec3 col = mix(base_color, tip_color * mix(0.85, 1.15, tint), smoothstep(0.0, 1.0, h / height));
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
	BACKLIGHT = vec3(0.25, 0.35, 0.1);
}
