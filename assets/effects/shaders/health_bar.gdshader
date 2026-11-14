shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled;

// Uniformes normais (não "instance") para funcionar também no renderizador Compatibility.
uniform float ratio = 1.0;
uniform vec4 fill_color : source_color = vec4(0.2, 0.9, 0.2, 1.0);

void vertex() {
	// Billboard (sempre virado para a câmera).
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = UV;
	float border = step(uv.x, 0.02) + step(0.98, uv.x) + step(uv.y, 0.12) + step(0.88, uv.y);
	vec3 col = uv.x < ratio ? fill_color.rgb * (0.75 + 0.35 * (1.0 - uv.y)) : vec3(0.08, 0.06, 0.05);
	// Marcações a cada 10% (estilo Warcraft/Dota).
	float tick = step(0.94, fract(uv.x * 10.0)) * step(uv.x, ratio) * 0.25;
	col -= tick;
	col = mix(col, vec3(0.0), clamp(border, 0.0, 1.0));
	ALBEDO = col;
}
