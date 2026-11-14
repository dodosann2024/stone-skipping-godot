shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled;
// Solid campfire ring stones — flat albedo (any shade gradient Bayer-stipples on Compatibility).
uniform vec3 albedo_color : source_color = vec3(0.52, 0.50, 0.46);
void fragment() {
	ALBEDO = albedo_color;
}
