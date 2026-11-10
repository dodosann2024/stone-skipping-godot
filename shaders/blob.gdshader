shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// soft contact shadow under the kid
uniform float strength = 0.32;
void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = dot(d, d);
	ALBEDO = vec3(0.16, 0.12, 0.08);
	ALPHA = strength * pow(max(1.0 - r, 0.0), 1.8);
}
