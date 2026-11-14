shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
// Foam collar + spreading ripple rings around the kid's legs while he wades. The plane follows him
// (world aligned, UV = world x/z); older rings are left behind along -vel, which reads as a little wake.
#include "res://shaders/common.gdshaderinc"

uniform float size = 2.6;
uniform float strength = 0.0;
uniform vec2 vel = vec2(0.0);       // world x/z, m/s
uniform vec2 right = vec2(1.0, 0.0); // the kid's right (world x/z)
uniform float time = 0.0;
uniform float night = 0.0;

void fragment() {
	vec2 q = (UV - 0.5) * size;
	float spd = length(vel);
	vec2 vd = spd > 0.01 ? vel / spd : vec2(0.0);
	// collar around both legs, pushed up in front when walking
	float collar = 0.0;
	for (int i = 0; i < 2; i++) {
		vec2 leg = right * (i == 0 ? 0.075 : -0.075);
		vec2 dq = q - leg;
		float r = length(dq);
		float front = spd > 0.01 ? dot(dq / max(r, 0.001), vd) : 0.0;
		float rr = 0.065 + 0.03 * max(front, 0.0) * min(spd * 2.0, 1.0);
		collar = max(collar, exp(-pow((r - rr) / (0.022 + 0.02 * min(spd, 1.0)), 2.0)));
	}
	collar *= 0.55 + 0.45 * lace(q * 9.0 + vec2(time * 0.6, -time * 0.4), 0.0);
	// rings: born at the legs, spreading and fading, centres drifting back along the path
	float rings = 0.0;
	for (int k = 0; k < 3; k++) {
		float age = fract(time * 0.75 + float(k) / 3.0) * 1.35;
		vec2 c = -vel * age * 0.9;
		float rad = 0.12 + age * (0.42 + spd * 0.2);
		float x = length(q - c) - rad;
		float ring = exp(-x * x / (0.0006 + age * 0.0012)) * (1.0 - age / 1.35);
		rings += ring * (0.55 + 0.45 * vnoise(q * 6.0 + float(k) * 3.1));
	}
	// a short V of foam trailing behind when walking
	vec2 qs = vec2(dot(q, vec2(vd.y, -vd.x)), dot(q, vd));
	float wake = exp(-pow((abs(qs.x) - (-qs.y) * 0.45) / 0.03, 2.0)) * smoothstep(0.0, -0.08, qs.y) * (1.0 - smoothstep(0.2, 0.9, -qs.y));
	wake *= min(spd * 1.6, 1.0) * lace(q * 7.0 + vec2(time * 0.3), 0.25);
	float a = clamp(collar * 0.85 + rings * 0.5 + wake * 0.7, 0.0, 1.0) * strength;
	a *= 1.0 - smoothstep(size * 0.36, size * 0.5, length(q));
	if (a < 0.01) {
		discard;
	}
	ALBEDO = mix(vec3(0.94, 0.98, 0.97), vec3(0.18, 0.26, 0.38), night);
	ALPHA = a * mix(1.0, 0.55, night);
}
