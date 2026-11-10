shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Soft camera-facing glow around a lamp at night (night.gd); `k` fades it in.
uniform vec3 color : source_color = vec3(1.0, 0.75, 0.4);
uniform float k = 0.0;

void vertex() {
	vec3 pos = MODEL_MATRIX[3].xyz;
	float sc = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sc, INV_VIEW_MATRIX[1] * sc, INV_VIEW_MATRIX[2] * sc, vec4(pos, 1.0));
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = (exp(-r * 4.5) * 0.9 + (1.0 - smoothstep(0.0, 1.0, r)) * 0.12) * k;
	if (a < 0.004) {
		discard;
	}
	ALBEDO = color * a;
}
