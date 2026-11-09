shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;
// clouds / glow props: vertex colour, no lighting
uniform float boost = 1.0;
void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * boost;
}
