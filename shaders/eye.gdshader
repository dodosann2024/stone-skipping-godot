shader_type spatial;
render_mode cull_back;
// v22 cartoon eyeballs: albedo from baked vertex COLOR (white sclera / hazel iris / round pupil
// + baked catchlights). Mild view-facing fill so the face reads under the hat at game camera.
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
	if (wp0.y < 0.12) {
		c = uw_tint(c, wp0);
	}
	ALBEDO = c;
	// Night: matte sclera, tiny natural highlight only — no emission halo.
	ROUGHNESS = mix(0.42, 0.62, night_k);
	SPECULAR = mix(0.06, 0.02, night_k);
	AO = 1.0;
	float facing = smoothstep(0.0, 0.55, NORMAL.z);
	float lit = smoothstep(0.55, 0.92, max(c.r, max(c.g, c.b))); // bright = sclera / catchlight
	float day_e = (1.0 - night_k);
	EMISSION = (c * 0.18 * facing
		+ vec3(0.10, 0.08, 0.05)
		+ vec3(1.0, 0.99, 0.96) * lit * 0.15 * catchlight * facing) * day_e;
}
