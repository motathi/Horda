shader_type spatial;
// Efeitos das habilidades (formas de tools/blender_skill_fx.py): brilho aditivo com núcleo claro e borda colorida,
// rastro que corre ao longo de U (cabeça em `head`), ruído que dissolve as bordas e some no fim (`fade`).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.95, 0.75, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.45, 0.08, 1.0);
uniform float intensity = 2.0;
// 0 = faixa (brilha no meio de V), 1 = de baixo para cima (V = 0 brilha), 2 = sólido, 3 = borda (fresnel)
uniform int mode = 0;
// Rastro ao longo de U: só aparece de head - tail até head, mais forte perto da cabeça.
uniform float head = 1.0;
uniform float tail = 100.0;
uniform float fade = 1.0;      // 1 = visível, 0 = sumiu
uniform float dissolve = 0.0;  // 0..1: come as partes mais fracas do ruído
uniform vec2 noise_scale = vec2(2.0, 1.0);
uniform vec2 noise_scroll = vec2(-1.5, 0.0);
uniform float flicker = 0.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

void fragment() {
	vec2 uv = UV;
	float n = texture(noise_tex, uv * noise_scale + noise_scroll * TIME).r;
	float across = 1.0;
	if (mode == 0) {
		across = 1.0 - abs(uv.y * 2.0 - 1.0);
	} else if (mode == 1) {
		across = 1.0 - uv.y;
	} else if (mode == 3) {
		across = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	}
	float t = clamp((uv.x - (head - tail)) / max(tail, 0.001), 0.0, 1.0);
	float along = uv.x <= head + 0.001 ? t : 0.0;
	float a = across * along;
	a *= smoothstep(dissolve, dissolve + 0.3, n * 0.8 + 0.25 + across * 0.25);
	a *= fade * (1.0 + flicker * (n - 0.5));
	float hot = pow(clamp(across * (0.55 + 0.45 * along), 0.0, 1.0), 2.2);
	vec3 col = mix(edge_color.rgb, core_color.rgb, hot);
	ALBEDO = col * intensity;
	ALPHA = clamp(a, 0.0, 1.0);
}
