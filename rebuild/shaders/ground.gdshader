shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
// Sand, grass, wet shore and wood planks. No discard. Vertex color marks wood.

uniform float game_time = 0.0;
uniform float night_k = 0.0;
varying vec3 wpos;

float island_r(float th) {
	return 19.0 + 2.2 * sin(2.0 * th + 0.6) + 1.6 * sin(3.0 * th + 1.9) + 0.9 * sin(5.0 * th + 0.3);
}
float shore_d(vec2 p) {
	return length(p) - island_r(atan(p.y, p.x));
}
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}
float sea_y(vec2 p, float t) {
	return 0.03 * sin(dot(vec2(0.82, 0.57), p) * 0.5 + t * 0.9) + 0.02 * sin(dot(vec2(-0.45, 0.89), p) * 0.8 + t * 1.2);
}
float lace(vec2 q, float thin) {
	float a = abs(vnoise(q) - 0.5);
	float b = abs(vnoise(q * 2.17 + vec2(5.2, 1.3)) - 0.5);
	float w = mix(0.11, 0.025, thin);
	float l = (1.0 - smoothstep(w * 0.3, w, a)) * 0.8 + (1.0 - smoothstep(w * 0.25, w * 0.8, b)) * 0.55;
	return clamp(l, 0.0, 1.0);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = game_time;
	bool wood = COLOR.r > 0.48 && COLOR.b < 0.32 && COLOR.r > COLOR.g;
	vec3 c;
	float rough = 0.92;
	if (wood) {
		float along = p.y * 3.2;
		float across = p.x * 6.5;
		float board = floor(along);
		float grain = hash12(vec2(board, floor(across)));
		float seam = smoothstep(0.0, 0.08, fract(along)) * smoothstep(1.0, 0.92, fract(along));
		c = mix(vec3(0.45, 0.30, 0.16), vec3(0.62, 0.44, 0.24), grain);
		c *= 0.72 + 0.28 * seam;
		c *= 1.0 + (hash12(floor(p * 18.0)) - 0.5) * 0.08;
		rough = 0.78;
	} else {
		float d = shore_d(p);
		float sand = smoothstep(0.35, 1.15, wpos.y) * smoothstep(-1.5, -7.0, d);
		vec3 sand_c = vec3(0.86, 0.78, 0.58);
		vec3 grass_c = vec3(0.42, 0.62, 0.32);
		grass_c = mix(grass_c, vec3(0.55, 0.68, 0.34), vnoise(p * 0.35));
		c = mix(sand_c, grass_c, sand);
		float fq = fwidth(p.x * 36.0);
		float grain = (hash12(floor(p * 36.0)) - 0.5) * (1.0 - smoothstep(0.4, 1.2, fq));
		c *= 1.0 + grain * 0.18 + (vnoise(p * 6.0) - 0.5) * 0.08;
		float sea = sea_y(p, t);
		float hab = wpos.y - sea;
		float wet = (1.0 - smoothstep(0.0, 0.18, hab)) * smoothstep(-2.0, 0.4, d + 1.0);
		c *= mix(vec3(1.0), vec3(0.62, 0.66, 0.64), clamp(wet, 0.0, 1.0));
		float cyc = fract(t * 0.105 + vnoise(p * 0.18) * 0.6);
		float rim = exp(-pow(hab / 0.08, 2.0)) * (1.0 - smoothstep(0.2, 0.55, cyc));
		rim *= lace(p * 3.5 + vec2(t * 0.05, 0.0), 0.15);
		c = mix(c, vec3(0.95, 0.97, 0.96), clamp(rim, 0.0, 1.0) * smoothstep(-0.5, 0.2, d));
		rough = mix(0.94, 0.35, clamp(wet, 0.0, 1.0));
	}
	c = mix(c, vec3(0.09, 0.14, 0.16), night_k);
	ALBEDO = c;
	ROUGHNESS = rough;
	EMISSION = vec3(0.08, 0.12, 0.14) * night_k;
}
