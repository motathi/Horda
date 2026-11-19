shader_type spatial;
// Terreno pintado à mão: mistura grama/terra/pedra/corrupção a partir de um
// mapa de regiões (splat) gerado pelo WorldBuilder.

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D corrupt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D splat : filter_linear;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float tile = 0.1;
uniform float map_size = 240.0;
// Grama pós-apocalíptica: capim seco e doente (0 = verde original, 1 = totalmente seco).
uniform float dry = 0.85;
uniform vec3 dry_tint : source_color = vec3(0.62, 0.55, 0.33);
uniform vec3 dead_color : source_color = vec3(0.36, 0.29, 0.18);
uniform vec3 ash_color : source_color = vec3(0.16, 0.15, 0.14);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * tile;
	vec2 suv = wpos.xz / map_size + 0.5;
	vec4 s = texture(splat, suv);
	float n = texture(noise_tex, wpos.xz * 0.015).r;
	float n2 = texture(noise_tex, wpos.xz * 0.06 + vec2(0.37)).r;
	vec3 g = texture(grass_tex, uv).rgb;
	g = mix(g, texture(grass_tex, uv * 0.31 + vec2(0.17, 0.53)).rgb, 0.4);
	g *= mix(0.82, 1.12, n);
	// Capim seco: tira a saturação e puxa para oliva/palha; manchas de grama morta,
	// terra aparecendo e áreas queimadas com cinza (ruído em escalas diferentes).
	float lum = dot(g, vec3(0.3, 0.55, 0.15));
	vec3 dried = mix(g, vec3(lum) * dry_tint * 2.0, dry);
	float n3 = texture(noise_tex, wpos.xz * 0.009 + vec2(0.71, 0.13)).r;
	float dead = smoothstep(0.48, 0.66, n3 + (n2 - 0.5) * 0.35);
	dried = mix(dried, dead_color * mix(0.8, 1.15, n2) , dead * 0.85);
	float bare = smoothstep(0.62, 0.74, n2 + (n - 0.5) * 0.4);
	dried = mix(dried, texture(dirt_tex, uv * 0.9).rgb * vec3(0.85, 0.8, 0.75), bare * 0.7);
	float n4 = texture(noise_tex, wpos.xz * 0.004 + vec2(0.29, 0.83)).r;
	float burnt = smoothstep(0.66, 0.74, n4 + (n2 - 0.5) * 0.25);
	dried = mix(dried, ash_color * mix(0.7, 1.3, n2), burnt);
	vec3 col = dried;
	float dirt_w = smoothstep(0.4, 0.6, s.r + (n2 - 0.5) * 0.5);
	col = mix(col, texture(dirt_tex, uv * 0.9).rgb, dirt_w);
	float stone_w = smoothstep(0.4, 0.6, s.g + (n2 - 0.5) * 0.35);
	col = mix(col, texture(stone_tex, uv * 1.4).rgb, stone_w);
	float cor_w = smoothstep(0.4, 0.6, s.b + (n - 0.5) * 0.4);
	vec3 cor = texture(corrupt_tex, uv).rgb;
	col = mix(col, cor, cor_w);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	// Rachaduras da área contaminada brilham levemente (mais visível à noite).
	float glow = smoothstep(0.35, 0.6, cor.g - cor.r) * cor_w;
	EMISSION = vec3(0.25, 1.0, 0.3) * glow * 0.6;
}
