shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"

uniform vec3 c_shallow : source_color = vec3(0.56, 0.95, 0.86);
uniform vec3 c_mid : source_color = vec3(0.16, 0.78, 0.82);
uniform vec3 c_deep : source_color = vec3(0.04, 0.47, 0.70);
uniform vec3 c_abyss : source_color = vec3(0.02, 0.26, 0.50);
uniform vec3 c_sky : source_color = vec3(0.72, 0.87, 0.97);
uniform sampler2D obj_foam : filter_linear, repeat_disable;
uniform float game_time = 0.0;
uniform vec4 ripples[8];

varying vec3 wpos;

const vec2 WK0 = vec2(0.82, 0.57);
const vec2 WK1 = vec2(-0.45, 0.89);
const vec2 WK2 = vec2(0.97, -0.24);
const vec2 WK3 = vec2(-0.71, -0.70);

vec2 wave_grad(vec2 p, float t) {
	vec2 g = vec2(0.0);
	g += WK0 * 1.6 * 0.030 * cos(dot(WK0, p) * 1.6 + t * 1.3);
	g += WK1 * 2.3 * 0.022 * cos(dot(WK1, p) * 2.3 + t * 1.7);
	g += WK2 * 3.7 * 0.013 * cos(dot(WK2, p) * 3.7 + t * 2.3);
	g += WK3 * 5.9 * 0.008 * cos(dot(WK3, p) * 5.9 + t * 2.9);
	return g;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = game_time;
	VERTEX.y += 0.03 * sin(dot(WK0, wpos.xz) * 0.5 + t * 0.9) + 0.02 * sin(dot(WK1, wpos.xz) * 0.8 + t * 1.2);
}

void fragment() {
	vec2 p = wpos.xz;
	float t = game_time;
	float d = shore_d(p);
	float depth = seabed_depth(max(d, 0.0));

	// --- layered small-wave normal
	vec2 g = wave_grad(p, t);
	float e = 0.2;
	vec2 q1 = p * 1.9 + vec2(t * 0.32, t * 0.21);
	float n0 = vnoise(q1);
	g += vec2(vnoise(q1 + vec2(e, 0.0)) - n0, vnoise(q1 + vec2(0.0, e)) - n0) / e * 0.06;
	vec2 q2 = p * 4.3 - vec2(t * 0.45, -t * 0.38);
	float m0 = vnoise(q2);
	g += vec2(vnoise(q2 + vec2(e, 0.0)) - m0, vnoise(q2 + vec2(0.0, e)) - m0) / e * 0.025;
	g *= mix(0.45, 1.0, smoothstep(0.0, 3.0, d)); // calmer in the shallows

	// --- stone ripples
	float rip = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 r = ripples[i];
		float age = t - r.z;
		if (r.w > 0.0 && age > 0.0 && age < 3.2) {
			vec2 dv = p - r.xy;
			float dist = length(dv);
			float fade = (1.0 - age / 3.2) * r.w;
			for (int k = 0; k < 2; k++) {
				float rad = 0.25 + (age - float(k) * 0.28) * 1.45;
				float x = dist - rad;
				float ring = exp(-x * x * 30.0) * fade * (1.0 - float(k) * 0.45) * step(0.0, rad);
				rip += ring;
				g += (dv / max(dist, 0.001)) * ring * 0.35 * sign(x + 0.0001);
			}
		}
	}

	vec3 nw = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// --- depth colour
	vec3 col = mix(c_shallow, c_mid, smoothstep(0.15, 1.5, depth));
	col = mix(col, c_deep, smoothstep(1.4, 3.6, depth));
	col = mix(col, c_abyss, smoothstep(3.6, 5.8, depth));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	col = mix(col, c_sky, fres * 0.5);

	// --- shoreline foam: creeping wash edge + incoming broken wave lines
	float nA = vnoise(p * 0.8 + vec2(t * 0.05, -t * 0.04));
	float nB = vnoise(p * 2.8 - vec2(t * 0.12, t * 0.08));
	float nC = vnoise(p * 6.5 + vec2(t * 0.2, 0.0));
	float sw = swash(p, t);
	float dd = d + sw - 0.25 + (nB - 0.5) * 0.35;
	float edge = 1.0 - smoothstep(0.0, 0.22 + nA * 0.25, dd);
	edge *= smoothstep(-0.6, -0.15, dd) * 0.35 + 0.65;
	float lam = 3.1;
	float ph = fract(d / lam + t * 0.15 + nA * 0.35);
	float band = smoothstep(0.0, 0.06, ph) * (1.0 - smoothstep(0.06, 0.3, ph));
	float brk = smoothstep(0.35, 0.7, vnoise(p * 1.2 + vec2(0.0, t * 0.15)) * 0.7 + nB * 0.45);
	float lines = band * brk * (1.0 - smoothstep(0.6, 6.0, d)) * smoothstep(0.1, 0.8, d);
	// lace left behind as the wash recedes
	float lace = smoothstep(0.55, 0.8, nC * 0.6 + nB * 0.6) * (1.0 - smoothstep(0.2, 2.0, d));

	// --- foam around posts / rocks (baked distance map, 0..3 m)
	vec2 fuv = (p + vec2(64.0)) / 128.0;
	float od = texture(obj_foam, fuv).r * 3.0;
	float objf = 1.0 - smoothstep(0.04, 0.28 + nB * 0.35, od);
	objf += (1.0 - smoothstep(0.0, 1.5, od)) * smoothstep(0.62, 0.95, 0.5 + 0.5 * sin(od * 7.0 - t * 2.0)) * 0.5 * smoothstep(0.3, 0.6, nB);

	float foam = max(edge, lines * 0.9);
	foam = max(foam, lace * 0.55);
	foam = max(foam, objf);
	foam = max(foam, clamp(rip, 0.0, 1.0) * 0.85);
	float foam_v = smoothstep(0.25, 0.75, foam * (0.65 + 0.55 * nC));
	col = mix(col, vec3(0.97, 0.99, 1.0), foam_v);

	ALBEDO = col;
	ROUGHNESS = mix(0.14, 0.6, foam_v);
	SPECULAR = 0.4;
	METALLIC = 0.0;
	float a = mix(0.22, 0.93, smoothstep(0.0, 3.4, depth));
	ALPHA = clamp(a + fres * 0.35 + foam_v, 0.0, 1.0);
}
