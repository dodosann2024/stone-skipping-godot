shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Fireflies (MultiMesh, night.gd): each instance drifts in slow loops around its home spot and blinks.
uniform float k = 0.0;
uniform float time = 0.0;
varying float glow;

void vertex() {
	float id = float(INSTANCE_ID);
	vec3 home = MODEL_MATRIX[3].xyz;
	vec3 off = vec3(sin(time * (0.31 + fract(id * 0.37) * 0.3) + id * 1.7),
			0.45 * sin(time * (0.5 + fract(id * 0.71) * 0.4) + id * 2.9),
			cos(time * (0.27 + fract(id * 0.53) * 0.3) + id * 0.9)) * 0.7;
	vec3 pos = home + off;
	float sc = 0.07;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sc, INV_VIEW_MATRIX[1] * sc, INV_VIEW_MATRIX[2] * sc, vec4(pos, 1.0));
	float ph = time * (0.8 + fract(id * 0.29) * 0.9) + id * 7.3;
	glow = smoothstep(0.35, 1.0, sin(ph)) * k;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = (exp(-r * 6.0) + exp(-r * 2.2) * 0.25) * glow;
	if (a < 0.004) {
		discard;
	}
	ALBEDO = vec3(0.75, 1.0, 0.35) * a * 1.6;
}
