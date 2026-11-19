shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
// Tufos de grama estilizados (vários "fios" desenhados num quad), com vento.

// Capim seco pós-apocalíptico: base oliva escura, pontas cor de palha; cada tufo varia
// entre oliva doente e palha morta.
uniform vec3 base_color : source_color = vec3(0.17, 0.17, 0.08);
uniform vec3 tip_color : source_color = vec3(0.46, 0.42, 0.22);
uniform vec3 dead_tip : source_color = vec3(0.48, 0.36, 0.2);
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
	// Tufo sempre de frente para a câmera e inclinado na direção dela: vista de
	// cima, a grama aparece cheia (antes os planos cruzados viravam um "X").
	float sc = length(MODEL_MATRIX[0].xyz);
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 back = normalize(vec3(INV_VIEW_MATRIX[2].x, 0.0, INV_VIEW_MATRIX[2].z));
	// Topo inclinado para longe da câmera: a face do tufo fica voltada para ela.
	vec3 up = normalize(vec3(0.0, 1.0, 0.0) - back * 0.5);
	vec3 fwd = cross(right, up);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * sc, 0.0), vec4(up * sc, 0.0), vec4(fwd * sc, 0.0), MODEL_MATRIX[3]);
	// Normal apontando para cima: iluminação igual ao terreno.
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
	vec3 tip = mix(tip_color, dead_tip, smoothstep(0.55, 0.9, tint)) * mix(0.85, 1.15, fract(tint * 7.3));
	vec3 col = mix(base_color, tip, smoothstep(0.0, 1.0, h / height));
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
	BACKLIGHT = vec3(0.2, 0.18, 0.08);
}
