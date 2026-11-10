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
		float ru = runup(cyc) + (vnoise(p * vec2(1.1, 1.3) + vec2(t * 0.08, 0.0)) - 0.5) * 0.02;
		// wet band: darker, cooler and smoother up to just above the highest wash
		float wet = 1.0 - smoothstep(0.06, 0.11 + nW * 0.03, hab);
		float fresh = 1.0 - smoothstep(0.0, 0.03, hab - ru);
		c *= mix(vec3(1.0), vec3(0.70, 0.72, 0.74), max(wet, fresh));
		rough = mix(0.95, 0.5, wet);
		// the water film behind the front, and the front itself: one crisp, bright, wavy foam line
		float film = 1.0 - smoothstep(ru - 0.003, ru + 0.001, hab);
		float dfw = fwidth(hab) + 0.0004;
		float half_w = 0.0035 + 0.003 * nW;
		float front = 1.0 - smoothstep(half_w, half_w + dfw, abs(hab - ru + half_w));
		front *= 0.95 - smoothstep(0.35, 0.9, cyc) * 0.35;
		vec3 sheet = c * vec3(0.82, 0.95, 0.92) + vec3(0.04, 0.07, 0.07);
		c = mix(c, sheet, film * smoothstep(-0.02, 0.0, hab));
		c = mix(c, vec3(0.97, 0.98, 0.97), front * smoothstep(-0.03, 0.0, hab));
		rough = mix(rough, 0.25, film);
		// under water the milky water hides the bottom quickly
		float depth = -hab;
		if (depth > 0.0) {
			float rp = sin(d * 7.5 + vnoise(p * 0.45) * 7.0 + p.x * 0.6);
			c *= 1.0 + rp * 0.04 * smoothstep(0.05, 0.5, depth) * (1.0 - smoothstep(2.0, 4.0, depth));
			float k = exp(-depth * 0.8) * smoothstep(0.0, 0.18, depth);
			c += vec3(0.75, 0.95, 0.85) * caustic(p * 1.5, t) * 0.05 * k;
			vec3 tr = exp(-depth * vec3(1.5, 0.75, 0.85));
			c = c * tr + vec3(0.30, 0.52, 0.47) * (1.0 - tr);
		}
	}
	ALBEDO = c;
	ROUGHNESS = rough;
}
