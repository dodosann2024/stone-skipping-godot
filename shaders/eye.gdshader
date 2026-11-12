shader_type spatial;
render_mode cull_back;
// v22 cartoon eyeballs: albedo from baked vertex COLOR (sclera / hazel iris / pupil),
// catchlights view-facing. Extra warm fill so the face reads under the hat at game camera.
#include "res://shaders/underwater.gdshaderinc"
#include "res://shaders/refl_clip.gdshaderinc"

uniform float catchlight = 1.0;

varying vec3 wp0;

void vertex() {
	wp0 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (!IN_SHADOW_PASS && refl_pass(CAMERA_POSITION_WORLD) && (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y < 0.0) {
		discard;
	}
	vec3 c = COLOR.rgb;
	c = mix(c, vec3(dot(c, vec3(0.3, 0.55, 0.15))) * 0.9, 0.2 * night_k);
	if (wp0.y < 0.12) {
		c = uw_tint(c, wp0);
	}
	ALBEDO = c;
	ROUGHNESS = 0.38;
	SPECULAR = 0.08;
	AO = 1.0;
	vec3 h = normalize(vec3(-0.28, 0.42, 1.0));
	vec3 h2 = normalize(vec3(0.22, -0.16, 1.0));
	float cl = smoothstep(0.952, 0.972, dot(NORMAL, h)) + 0.7 * smoothstep(0.982, 0.992, dot(NORMAL, h2));
	float facing = smoothstep(0.0, 0.55, NORMAL.z);
	EMISSION = vec3(1.0, 0.99, 0.96) * cl * catchlight * 1.35 * (1.0 - 0.3 * night_k)
		+ c * 0.32 * facing * (1.0 - 0.35 * night_k)
		+ vec3(0.14, 0.10, 0.05) * (1.0 - 0.4 * night_k);
}
