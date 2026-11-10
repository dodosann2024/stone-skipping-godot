shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
#include "res://shaders/common.gdshaderinc"

uniform float game_time = 0.0;
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
	if (d > -9.0) {
		float sea = sea_y(p, t);
		float hab = wpos.y - sea;   // height above the sea surface right here
		float cyc = wash_cycle(p, t);
		float ru = runup(cyc);
		float nW = vnoise(p * 2.2 + vec2(t * 0.05, 0.0));
		// wet sand: dark where the wash reaches, drying out above the high-water mark
		float wet = 1.0 - smoothstep(0.0, 0.1 + nW * 0.03, hab - ru * 0.6);
		c *= mix(1.0, 0.62, wet);
		rough = mix(0.95, 0.45, wet);
		// the wash itself: a thin sheet of water running up the slope with a lacy foam front
		float film = 1.0 - smoothstep(ru - 0.003, ru + 0.001, hab);
		float dfw = fwidth(hab) + 0.0005;
		float front = (1.0 - smoothstep(0.0, 0.006 + dfw, abs(hab - ru + 0.003))) * smoothstep(0.004, 0.02, ru);
		front *= (0.6 + 0.4 * nW) * (1.0 - smoothstep(0.3, 0.85, cyc) * 0.75);
		float lace = smoothstep(0.78, 0.94, ridge(vnoise(p * 3.4 + vec2(-t * 0.08, t * 0.05))));
		vec3 sheet = c * vec3(0.78, 0.95, 0.93) + vec3(0.03, 0.07, 0.08);
		c = mix(c, sheet, film * smoothstep(-0.02, 0.0, hab));
		c = mix(c, vec3(0.92, 0.95, 0.95), max(front, lace * film * (1.0 - smoothstep(0.0, 0.6, cyc)) * 0.6));
		rough = mix(rough, 0.2, film);
		// under water: absorption tints the sand turquoise-green, sand ripples and caustics on the bottom
		float depth = -hab;
		if (depth > 0.0) {
			float rp = sin(d * 7.5 + vnoise(p * 0.45) * 7.0 + p.x * 0.6);
			c *= 1.0 + rp * 0.05 * smoothstep(0.05, 0.5, depth) * (1.0 - smoothstep(2.0, 4.0, depth));
			float k = exp(-depth * 0.5) * smoothstep(0.0, 0.18, depth);
			c += vec3(0.75, 0.95, 0.85) * caustic(p * 1.5, t) * 0.22 * k;
			vec3 tr = exp(-depth * vec3(0.95, 0.2, 0.28));
			c = c * tr + vec3(0.02, 0.32, 0.30) * (1.0 - tr);
		}
	}
	ALBEDO = c;
	ROUGHNESS = rough;
}
