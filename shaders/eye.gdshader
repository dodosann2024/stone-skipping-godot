shader_type spatial;
render_mode cull_back;
// v22 eyeballs (MakeHuman low-poly eyes, UV laid out like their eye texture: one disc per eye with the
// iris in the middle): a bright sclera that shows round the iris, a light hazel iris with soft fibres and
// a soft limbal ring, a wet cornea (low roughness) and two big catchlights fixed in view space (one up,
// a smaller one below) so the eyes stay bright and alive in any light.
// The upper lid's shadow comes from the eyeball's world normal (the top of the ball sits under the lid).
#include "res://shaders/underwater.gdshaderinc"
#include "res://shaders/refl_clip.gdshaderinc"

uniform vec3 sclera : source_color = vec3(0.99, 0.96, 0.93);
uniform vec3 iris_in : source_color = vec3(0.92, 0.66, 0.30);
uniform vec3 iris_out : source_color = vec3(0.70, 0.45, 0.18);
uniform vec3 limbal : source_color = vec3(0.32, 0.20, 0.10);
uniform vec2 centre_a = vec2(0.707, 0.297);
uniform vec2 centre_b = vec2(0.293, 0.707);
uniform float iris_r = 0.095;
uniform float pupil_r = 0.036;
uniform float catchlight = 1.0;

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
	// scale UV so the iris sits smaller in the open lid aperture and the whites show
	float r = length(d) * 1.5;
	float aa = fwidth(r) + 0.002;
	float ang = atan(d.y, d.x);
	// sclera: a little warmer and darker toward the corners
	vec3 c = mix(sclera, sclera * vec3(0.96, 0.93, 0.9), smoothstep(0.28, 0.48, r));
	// iris: lighter amber collarette near the pupil, radial fibres, crypts, a dark limbal ring
	float k = clamp((r - pupil_r) / (iris_r - pupil_r), 0.0, 1.0);
	float fib = sin(ang * 41.0 + sin(ang * 7.0) * 1.7) * 0.5 + sin(ang * 97.0 + k * 9.0) * 0.3;
	vec3 ir = mix(iris_in, iris_out, smoothstep(0.1, 0.6, k));
	ir *= 1.0 + fib * 0.1 * (1.0 - smoothstep(0.3, 0.0, fwidth(ang * 41.0)));
	ir = mix(ir, iris_in * 1.1, (1.0 - smoothstep(0.0, 0.12, abs(k - 0.25))) * 0.15);
	ir = mix(ir, limbal, smoothstep(0.85, 1.0, k) * 0.28);
	float im = 1.0 - smoothstep(iris_r - aa, iris_r + aa, r);
	// at night the amber iris under torchlight would glow orange
	ir = mix(ir, vec3(dot(ir, vec3(0.3, 0.55, 0.15))) * 0.85, 0.45 * night_k);
	c = mix(c, ir, im);
	c = mix(c, vec3(0.015, 0.012, 0.012), 1.0 - smoothstep(pupil_r - aa, pupil_r + aa, r));
	// under the upper lid
	float lid = smoothstep(-0.15, 0.55, wn.y);
	c *= 1.0 - 0.06 * lid;
	if (wp0.y < 0.12) {
		c = uw_tint(c, wp0);
	}
	ALBEDO = c;
	ROUGHNESS = 0.22;
	SPECULAR = 0.18;
	AO = mix(1.0, 0.75, lid);
	AO_LIGHT_AFFECT = 0.35;
	vec3 h = normalize(vec3(-0.32, 0.42, 1.0));
	vec3 h2 = normalize(vec3(0.2, -0.22, 1.0));
	float cl = smoothstep(0.96, 0.975, dot(NORMAL, h)) * 1.1 + 0.75 * smoothstep(0.986, 0.993, dot(NORMAL, h2));
	cl *= 1.0 - 0.5 * lid;
	EMISSION = vec3(1.0, 0.98, 0.95) * cl * catchlight * 1.35 * (1.0 - 0.35 * night_k) + c * 0.28 * (1.0 - lid) * (1.0 - 0.55 * night_k);
}
