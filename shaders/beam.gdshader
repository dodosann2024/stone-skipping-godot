shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Lighthouse beam: a long soft cone of light, brightest at the lamp, edges fading by the view angle.
uniform float k = 0.0;
uniform float half_len = 11.0;
uniform vec3 color : source_color = vec3(1.0, 0.92, 0.7);
varying float along;

void vertex() {
	along = clamp((half_len - VERTEX.y) / (2.0 * half_len), 0.0, 1.0);  // 0 at the lamp (top) .. 1 at the far end
}

void fragment() {
	float edge = pow(abs(dot(NORMAL, VIEW)), 1.6);
	float a = edge * pow(1.0 - along, 1.6) * 0.22 * k;
	if (a < 0.003) {
		discard;
	}
	ALBEDO = color * a;
}
