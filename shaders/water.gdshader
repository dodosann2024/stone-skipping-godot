shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"

// Milky jade water (v6, after the "Wired to Fish" look): an opaque-looking pastel gradient by depth,
// little specular, a translucent rim on the wet sand, one faint second foam line rolling in each
// surf cycle and scattered foam flecks. The crisp main foam line is the wash front on the sand
// (terrain.gdshader), so it slides up and down the beach.
uniform vec3 c_shallow : source_color = vec3(0.52, 0.78, 0.69);
uniform vec3 c_mid : source_color = vec3(0.38, 0.66, 0.61);
uniform vec3 c_deep : source_color = vec3(0.25, 0.52, 0.54);
uniform vec3 c_abyss : source_color = vec3(0.18, 0.40, 0.47);
uniform vec3 c_sky : source_color = vec3(0.82, 0.89, 0.90);
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

// thin anti-aliased line of half-width w (metres) at distance x
float aline(float x, float w, float fw) {
	float ww = w + fw;
	return (1.0 - smoothstep(ww * 0.5, ww, abs(x))) * clamp(w / ww * 1.4, 0.0, 1.0);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sea_y(wp.xz, game_time);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = game_time;
	float d = shore_d(p);
	float depth = seabed_depth(max(d, 0.0));
	float fwd = fwidth(d);

	// --- layered small-wave normal
	vec2 g = wave_grad(p, t);
	float e = 0.2;
	vec2 q1 = p * 1.9 + vec2(t * 0.32, t * 0.21);
	float n0 = vnoise(q1);
	g += vec2(vnoise(q1 + vec2(e, 0.0)) - n0, vnoise(q1 + vec2(0.0, e)) - n0) / e * 0.06;
	vec2 q2 = p * 4.3 - vec2(t * 0.45, -t * 0.38);
	float m0 = vnoise(q2);
	g += vec2(vnoise(q2 + vec2(e, 0.0)) - m0, vnoise(q2 + vec2(0.0, e)) - m0) / e * 0.025;
	g *= mix(0.4, 1.0, smoothstep(0.0, 4.0, d)); // calmer in the shallows

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

	g *= 0.6;
	vec3 nw = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// --- depth colour: pale jade on the shelf, sage / teal past the reef edge
	vec3 col = mix(c_shallow, c_mid, smoothstep(0.05, 1.3, depth));
	col = mix(col, c_deep, smoothstep(1.6, 3.6, depth));
	col = mix(col, c_abyss, smoothstep(3.8, 5.8, depth));
	col *= 1.0 + (vnoise(p * 0.35 + vec2(t * 0.02, 0.0)) - 0.5) * 0.06;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	col = mix(col, c_sky, fres * 0.25);

	// --- foam
	float foam = 0.0;
	float th = wpos.y - ground_near(p, d); // water thickness over the sand
	if (d < 6.0) {
		float nB = vnoise(p * 2.6 - vec2(t * 0.11, t * 0.07));
		float c = wash_cycle(p, t);
		// a faint second line rolling in, merging into the wash front as the surf reaches the sand
		float roll = smoothstep(0.55, 1.0, c);
		float dl = mix(2.4, 0.1, roll) + (vnoise(p * 0.8 + vec2(t * 0.05, 0.0)) - 0.5) * 0.5;
		float w2 = mix(0.02, 0.05, nB);
		foam = aline(d - dl, w2, fwd) * smoothstep(0.55, 0.7, c) * (0.25 + 0.25 * nB);
		// foam flecks drifting near the shore
		vec2 q = p * 2.4 + vec2(t * 0.05, t * 0.035);
		vec2 cell = floor(q);
		vec2 f = fract(q);
		float h = hash12(cell);
		vec2 cc = vec2(hash12(cell + 3.1), hash12(cell + 7.7)) * 0.6 + 0.2;
		float r = 0.035 + 0.05 * hash12(cell + 1.7);
		float fq = fwidth(q.x) + 0.002;
		float fleck = step(0.74, h) * (1.0 - smoothstep(r - fq, r + fq, length(f - cc)));
		foam = max(foam, fleck * (1.0 - smoothstep(0.6, 4.5, d)) * smoothstep(-0.2, 0.3, d) * 0.85);
	}

	// --- foam around posts / rocks (baked distance map, 0..3 m)
	vec2 fuv = (p + vec2(64.0)) / 128.0;
	float od = texture(obj_foam, fuv).r * 3.0;
	float nO = vnoise(p * 3.3 + vec2(t * 0.15, 0.0));
	float objf = 1.0 - smoothstep(0.04, 0.24 + nO * 0.3, od);
	objf += (1.0 - smoothstep(0.0, 1.4, od)) * smoothstep(0.62, 0.95, 0.5 + 0.5 * sin(od * 7.0 - t * 2.0)) * 0.45 * smoothstep(0.3, 0.6, nO);
	foam = max(foam, objf);
	foam = max(foam, clamp(rip, 0.0, 1.0) * 0.85);
	float foam_v = clamp(foam, 0.0, 1.0);
	col = mix(col, vec3(0.97, 0.99, 1.0), foam_v);

	ALBEDO = col;
	ROUGHNESS = mix(0.3, 0.7, foam_v);
	SPECULAR = 0.25;
	METALLIC = 0.0;
	// milky: mostly opaque, with a thin translucent edge where it runs onto the wet sand
	float a = mix(0.62, 0.86, smoothstep(0.0, 1.2, depth));
	a = mix(a, 0.97, smoothstep(1.8, 4.2, depth));
	a *= smoothstep(0.0, 0.05, th) * 0.75 + 0.25 * smoothstep(0.0, 0.012, th);
	ALPHA = clamp(a + fres * 0.2 + foam_v, 0.0, 1.0);
}
