shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
#include "res://shaders/common.gdshaderinc"

uniform float game_time = 0.0;
varying vec3 wpos;

float ridge(float n) { return 1.0 - abs(n * 2.0 - 1.0); }
float caustic(vec2 p, float t) {
	float a = ridge(vnoise(p * 1.15 + vec2(t * 0.33, t * 0.21)));
	float b = ridge(vnoise(p * 1.45 + vec2(-t * 0.26, t * 0.29) + 7.3));
	return pow(a, 16.0) + pow(b, 16.0) * 0.8;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float t = game_time;
	float d = shore_d(wpos.xz);
	// wet sand band that follows the wash
	float sw = swash(wpos.xz, t);
	float wet = smoothstep(-1.6 - sw * 1.2, -0.1, d);
	c *= mix(1.0, 0.68, wet);
	float depth = -wpos.y;
	if (depth > 0.0) {
		float k = exp(-depth * 0.32) * smoothstep(0.0, 0.25, depth);
		c += vec3(0.85, 1.0, 0.95) * caustic(wpos.xz * 1.25, t) * 0.3 * k;
		c *= mix(vec3(1.0), vec3(0.72, 0.93, 0.92), smoothstep(0.0, 3.0, depth));
	}
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.55, wet);
}
