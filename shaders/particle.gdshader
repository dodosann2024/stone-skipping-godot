shader_type spatial;
// Soft round camera-facing particle (CPUParticles3D sparks / smoke): instance position + scale, colour ramp in COLOR.
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;

// size over life (start, end); INSTANCE_CUSTOM.y is the particle's age fraction
uniform vec2 grow = vec2(1.0, 1.0);

void vertex() {
	vec3 pos = MODEL_MATRIX[3].xyz;
	float sc = length(MODEL_MATRIX[0].xyz) * mix(grow.x, grow.y, INSTANCE_CUSTOM.y);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sc, INV_VIEW_MATRIX[1] * sc, INV_VIEW_MATRIX[2] * sc, vec4(pos, 1.0));
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = 1.0 - smoothstep(0.0, 1.0, r);
	if (COLOR.a * a * a < 0.01) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * a * a;
}
