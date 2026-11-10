shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
#include "res://shaders/common.gdshaderinc"

uniform float game_time = 0.0;
uniform vec4 prints[48];          // footprints: x, z, heading angle, time stamped
uniform float print_wash[48];     // time the swash first ran over the print (-1: not yet)
uniform vec4 print_box = vec4(1.0, 1.0, -1.0, -1.0);   // xz bounds of the live prints

// flip-flop print: a soft dent along the foot (rounded sole, wider at the ball) with a faint pushed-up rim.
// Returns (dent, rim) faded by age and wiped out shortly after the wash has run over it.
vec2 footprint(vec2 p, vec4 fp, float washed, float t) {
	float age = t - fp.w;
	if (age < 0.0 || age > 75.0) {
		return vec2(0.0);
	}
	vec2 dv = p - fp.xy;
	if (dot(dv, dv) > 0.05) {
		return vec2(0.0);
	}
	vec2 f = vec2(cos(fp.z), sin(fp.z));
	float u = dot(dv, f);
	float v = dot(dv, vec2(-f.y, f.x));
	float k = clamp((u + 0.11) / 0.2, 0.0, 1.0);
	float r = mix(0.033, 0.043, smoothstep(0.2, 0.75, k));
	float dist = length(vec2(u - (k * 0.2 - 0.11), v)) - r;
	float life = 1.0 - smoothstep(30.0, 75.0, age);
	if (washed >= 0.0) {
		life *= 1.0 - smoothstep(0.0, 0.7, t - washed);
	}
	float dent = 1.0 - smoothstep(-0.008, 0.004, dist);
	float rim = smoothstep(-0.002, 0.006, dist) * (1.0 - smoothstep(0.008, 0.022, dist));
	return vec2(dent, rim) * life;
}
varying vec3 wpos;

float ridge(float n) { return 1.0 - abs(n * 2.0 - 1.0); }
float caustic(vec2 p, float t) {
	float a = ridge(vnoise(p * 1.15 + vec2(t * 0.33, t * 0.21)));
	float b = ridge(vnoise(p * 1.45 + vec2(-t * 0.26, t * 0.29) + 7.3));
	return pow(a, 14.0) + pow(b, 14.0) * 0.8 + pow(a * b, 6.0) * 0.6;
}

global uniform float night_k;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float t = game_time;
	vec2 p = wpos.xz;
	float d = shore_d(p);
	float rough = 0.95;
	// sand grain: fine speckle + mid-scale mottling (faded out where it would alias), broad tonal drift
	float fq = fwidth(p.x * 40.0) + fwidth(p.y * 40.0);
	float grain = (hash12(floor(p * 40.0)) - 0.5) * (1.0 - smoothstep(0.5, 1.4, fq));
	c *= 1.0 + grain * 0.16 + (vnoise(p * 7.0) - 0.5) * 0.07 + (vnoise(p * 0.12) - 0.5) * 0.1;
	if (p.x > print_box.x && p.y > print_box.y && p.x < print_box.z && p.y < print_box.w) {
		vec2 fpr = vec2(0.0);
		for (int i = 0; i < 48; i++) {
			fpr = max(fpr, footprint(p, prints[i], print_wash[i], t));
		}
		c *= (1.0 - 0.36 * fpr.x) * (1.0 + 0.12 * fpr.y * (1.0 - fpr.x));
	}
	if (d > -9.0) {
		float sea = sea_y(p, t);
		// height above the sea surface; near the waterline use the smooth analytic beach profile
		// (the 1 m terrain grid would make the wash line angular)
		float gy = mix(ground_near(p, d), wpos.y, smoothstep(0.5, 2.5, abs(d + 0.3)));
		float hab = gy - sea;
		float cyc = wash_cycle(p, t);
		float nW = vnoise(p * 2.2 + vec2(t * 0.05, 0.0));
		// the wash: a wavy edge climbing the slope and draining back
		float rj = (vnoise(p * vec2(1.1, 1.3) + vec2(t * 0.08, 0.0)) - 0.5) * 0.02;
		float ru = runup(cyc) + rj;
		// beach slope along the radial direction turns heights into metres behind the wash front
		vec2 rn = normalize(p);
		float slope = max((ground_near(p - rn * 0.1, d - 0.1) - ground_near(p, d)) / 0.1, 0.03);
		float behind = (ru - hab) / slope;
		// wet sand: a soft damp band by the sea, plus sand the backwash uncovered a moment ago, drying out
		float damp = 1.0 - smoothstep(0.0, 0.12 + nW * 0.05, hab);
		float wetted = 0.0;
		float h2 = hab - rj;
		if (h2 < 0.07) {
			float s = clamp(1.0 - h2 / 0.07, 0.0, 1.0);
			float cd = 0.26 + (0.5 - sin(asin(1.0 - 2.0 * s) / 3.0)) * 0.64;   // drain phase that uncovered it
			float since = (cyc >= 0.26 ? cyc - cd : cyc + 1.0 - cd) / 0.105;
			wetted = since < 0.0 ? 1.0 : exp(-since / 3.5);
		}
		float wet = clamp(max(damp * 0.7, wetted), 0.0, 1.0);
		c *= mix(vec3(1.0), vec3(0.62, 0.635, 0.65), wet);
		rough = mix(0.95, 0.4, wet);
		// thin water sheet behind the front: slightly darker, cooler, glossy, with caustic shimmer
		float film = smoothstep(-0.01, 0.05, behind);
		float tw = clamp(ru - hab, 0.0, 0.08);
		vec3 sheet = c * mix(vec3(0.92, 0.97, 0.96), vec3(0.76, 0.90, 0.87), smoothstep(0.0, 0.04, tw));
		sheet += vec3(0.85, 1.0, 0.95) * caustic(p * 2.2, t * 1.4) * 0.07 * smoothstep(0.003, 0.02, tw);
		c = mix(c, sheet, film * smoothstep(-0.03, 0.0, hab));
		rough = mix(rough, 0.18, film);
		// foam: a broken, lacy leading rim riding the front, lace behind it that thins out and is left
		// stranded as the water drains back
		vec2 q = p * 4.2 + rn * (runup(cyc) * 9.0) + vec2(t * 0.03, 0.0);
		float age = smoothstep(0.05, 0.75, cyc);
		float rim = exp(-pow((behind - 0.16) / 0.13, 2.0)) * (1.0 - smoothstep(0.22, 0.5, cyc));
		rim *= smoothstep(0.15, 0.55, vnoise(p * 2.6 + vec2(t * 0.15, -t * 0.1)) + 0.15) * (0.3 + 0.7 * lace(q * 0.8, 0.05));
		float trail = lace(q, age) * smoothstep(0.02, 0.18, behind) * (1.0 - smoothstep(0.35, 1.3, behind));
		trail *= 1.0 - smoothstep(0.5, 0.95, cyc);
		// the cycle phase wraps (fract) along a moving seam; fading in from 0 keeps the foam continuous there
		float foam = clamp(max(rim, trail * 0.85), 0.0, 1.0) * smoothstep(-0.05, 0.0, hab) * smoothstep(0.0, 0.05, cyc);
		c = mix(c, vec3(0.95, 0.97, 0.96), foam * 0.92);
		rough = mix(rough, 0.8, foam);
		// under water the bottom fades into the sea colour with depth
		float depth = -hab;
		if (depth > 0.0) {
			float rp = sin(d * 7.5 + vnoise(p * 0.45) * 7.0 + p.x * 0.6);
			c *= 1.0 + rp * 0.04 * smoothstep(0.05, 0.5, depth) * (1.0 - smoothstep(2.0, 4.0, depth));
			float k = exp(-depth * 0.9) * smoothstep(0.0, 0.12, depth);
			c += vec3(0.7, 0.95, 0.85) * caustic(p * 1.5, t) * 0.075 * k;
			vec3 tr = exp(-depth * vec3(1.5, 0.75, 0.85));
			c = c * tr + vec3(0.30, 0.52, 0.47) * (1.0 - tr);
		}
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.5 * (1.0 - night_k);
}
