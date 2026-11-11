shader_type spatial;
render_mode cull_back;
// v21 eyeballs (MakeHuman low-poly eyes, UV laid out like their eye texture: one disc per eye with the
// iris in the middle): sclera, a brown iris with fibres and a dark limbal ring, the pupil, a wet cornea
// (low roughness) and a small catchlight fixed in view space so the eyes stay alive in any light.
// The upper lid's shadow comes from the eyeball's world normal (the top of the ball sits under the lid).
#include "res://shaders/underwater.gdshaderinc"
#include "res://shaders/refl_clip.gdshaderinc"

uniform vec3 sclera : source_color = vec3(0.90, 0.88, 0.84);
uniform vec3 iris_in : source_color = vec3(0.52, 0.33, 0.15);
uniform vec3 iris_out : source_color = vec3(0.24, 0.13, 0.06);
uniform vec3 limbal : source_color = vec3(0.07, 0.045, 0.035);
uniform vec2 centre_a = vec2(0.707, 0.297);
uniform vec2 centre_b = vec2(0.293, 0.707);
uniform float iris_r = 0.106;
uniform float pupil_r = 0.034;
uniform float catchlight = 0.85;

varying vec3 wp0;
varying vec3 wn;

void vertex() {
	wp0 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (!IN_SHADOW_PASS && refl_pass(CAMERA_POSITION_WORLD) && (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y < 0.0) {
		discard;
	}
	vec2 da = UV - centre_a;
	vec2 db = UV - centre_b;
	vec2 d = dot(da, da) < dot(db, db) ? da : db;
	float r = length(d);
	float aa = fwidth(r) + 0.002;
	float ang = atan(d.y, d.x);
	// sclera: a little warmer and darker toward the corners
	vec3 c = mix(sclera, sclera * vec3(0.86, 0.74, 0.70), smoothstep(0.16, 0.36, r));
	// iris: lighter amber collarette near the pupil, radial fibres, crypts, a dark limbal ring
	float k = clamp((r - pupil_r) / (iris_r - pupil_r), 0.0, 1.0);
	float fib = sin(ang * 41.0 + sin(ang * 7.0) * 1.7) * 0.5 + sin(ang * 97.0 + k * 9.0) * 0.3;
	vec3 ir = mix(iris_in, iris_out, smoothstep(0.1, 0.6, k));
	ir *= 1.0 + fib * 0.16 * (1.0 - smoothstep(0.3, 0.0, fwidth(ang * 41.0)));
	ir = mix(ir, iris_in * 1.1, (1.0 - smoothstep(0.0, 0.12, abs(k - 0.25))) * 0.15);
	ir = mix(ir, limbal, smoothstep(0.72, 1.0, k));
	float im = 1.0 - smoothstep(iris_r - aa, iris_r + aa, r);
	c = mix(c, ir, im);
	c = mix(c, vec3(0.015, 0.012, 0.012), 1.0 - smoothstep(pupil_r - aa, pupil_r + aa, r));
	// under the upper lid
	float lid = smoothstep(-0.15, 0.55, wn.y);
	c *= 1.0 - 0.5 * lid;
	if (wp0.y < 0.12) {
		c = uw_tint(c, wp0);
	}
	ALBEDO = c;
	ROUGHNESS = 0.07;
	SPECULAR = 0.55;
	AO = mix(0.85, 0.35, lid);
	AO_LIGHT_AFFECT = 0.35;
	vec3 h = normalize(vec3(-0.32, 0.42, 1.0));
	float cl = smoothstep(0.9955, 0.9985, dot(NORMAL, h)) * (1.0 - lid);
	EMISSION = vec3(1.0, 0.98, 0.95) * cl * catchlight * (1.0 - 0.4 * night_k);
}
