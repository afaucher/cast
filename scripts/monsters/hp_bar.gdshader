shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;
// Billboarded HP bar quad: `fill` (0..1) is the red portion.
uniform float fill = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	bool edge = UV.x < 0.02 || UV.x > 0.98 || UV.y < 0.14 || UV.y > 0.86;
	vec3 col = UV.x <= fill ? vec3(0.9, 0.12, 0.1) : vec3(0.12, 0.05, 0.05);
	if (edge) {
		col = vec3(0.02);
	}
	ALBEDO = col;
	ALPHA = 0.97;
}
