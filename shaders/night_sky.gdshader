shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Night sky overlay: a big sphere centred on the camera (night.gd) adds stars, a faint milky band and
// the moon with its halo on top of the darkened procedural sky. `k` fades it in with the night.
#include "res://shaders/common.gdshaderinc"

uniform float k = 0.0;
uniform vec3 moon_dir = vec3(0.0, 0.47, -0.88);
uniform float time = 0.0;
varying vec3 dir;

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

void vertex() {
	dir = VERTEX;
}

void fragment() {
	vec3 d = normalize(dir);
	if (d.y < -0.01 || k < 0.01) {
		discard;
	}
	float up = smoothstep(-0.01, 0.22, d.y);
	vec3 md = normalize(moon_dir);
	float ang = acos(clamp(dot(d, md), -1.0, 1.0));
	// moon: a big soft disc with a few darker maria, lit a touch from one side
	float rm = 0.042;
	float disc = 1.0 - smoothstep(rm * 0.9, rm, ang);
	vec3 col = vec3(0.0);
	if (ang < rm * 1.2) {
		vec3 t1 = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
		vec3 t2 = cross(t1, md);
		vec2 uv = vec2(dot(d, t1), dot(d, t2)) / rm;
		float mar = smoothstep(0.45, 0.75, vnoise(uv * 2.3 + 3.0)) * 0.22 + smoothstep(0.55, 0.8, vnoise(uv * 5.1)) * 0.1;
		float limb = 1.0 - 0.18 * dot(uv, uv);
		col += vec3(1.0, 0.97, 0.88) * 1.25 * disc * limb * (1.0 - mar);
	}
	col += vec3(0.55, 0.65, 0.9) * (exp(-ang / 0.06) * 0.28 + exp(-ang / 0.32) * 0.07) * (1.0 - disc);
	// stars: one candidate per cell of a 3D grid on the sphere, most of them faint, a few bright
	vec3 q = d * 70.0;
	vec3 c = floor(q);
	vec3 h = hash33(c);
	if (h.x < 0.32) {
		vec3 sp = normalize(c + 0.2 + 0.6 * hash33(c + 17.0)) * 70.0;
		float dist = length(q - sp);
		float b = pow(h.y, 6.0) * 1.6 + 0.12;
		float r = 0.07 + 0.08 * pow(h.y, 3.0);
		float tw = 0.7 + 0.3 * sin(time * (1.5 + h.z * 3.0) + h.z * 40.0);
		vec3 sc = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.92, 0.8), h.z);
		col += sc * b * tw * exp(-dist * dist / (r * r)) * up * (1.0 - disc) * (1.0 - smoothstep(0.0, 0.25, ang) * 0.0);
	}
	// a faint milky band across the sky
	float band = exp(-pow(dot(d, normalize(vec3(0.35, 0.25, 0.9))) / 0.2, 2.0));
	col += vec3(0.32, 0.38, 0.55) * band * (0.35 + 0.65 * vnoise(d.xz * 9.0 + d.y * 4.0)) * 0.06 * up;
	col *= k;
	if (max(col.r, max(col.g, col.b)) < 0.004) {
		discard;
	}
	ALBEDO = col;
}
