shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Soft round contact shadow under the kid — alpha 0 at the rim (no hard square).
uniform float strength = 0.28;
void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	// Smoothstep rim so the quad edge never reads as a rectangle.
	float a = strength * pow(clamp(1.0 - r, 0.0, 1.0), 2.4);
	a *= smoothstep(1.0, 0.72, r);
	ALBEDO = vec3(0.10, 0.09, 0.08);
	ALPHA = a;
	if (a < 0.004) {
		discard;
	}
}
