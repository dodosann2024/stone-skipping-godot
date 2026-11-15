shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// Shallow jade water and a lacy shore foam. No discard.

uniform float game_time = 0.0;
uniform float night_k = 0.0;
varying vec3 wpos;

float island_r(float th) {
	return 19.0 + 2.2 * sin(2.0 * th + 0.6) + 1.6 * sin(3.0 * th + 1.9) + 0.9 * sin(5.0 * th + 0.3);
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
float lace(vec2 q) {
	float a = abs(vnoise(q) - 0.5);
	return 1.0 - smoothstep(0.04, 0.12, a);
}

void vertex() {
	vec3 v = VERTEX;
	v.y += sin(VERTEX.x * 0.35 + game_time * 0.8) * 0.04 + sin(VERTEX.z * 0.28 - game_time) * 0.03;
	wpos = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
	VERTEX = v;
}

void fragment() {
	vec2 p = wpos.xz;
	float d = length(p) - island_r(atan(p.y, p.x));
	float deep = smoothstep(-1.0, 8.0, d);
	vec3 shallow = vec3(0.55, 0.86, 0.74);
	vec3 midc = vec3(0.20, 0.62, 0.62);
	vec3 deepc = vec3(0.08, 0.36, 0.48);
	vec3 c = mix(shallow, mix(midc, deepc, smoothstep(2.0, 10.0, d)), deep);
	c = mix(c, vec3(0.05, 0.12, 0.22), night_k * 0.8);
	float shore = smoothstep(1.6, -0.6, d);
	float foam = lace(p * 2.2 + vec2(game_time * 0.12, game_time * 0.04)) * shore;
	float foam2 = lace(p * 5.5 + vec2(-game_time * 0.2, 1.7)) * smoothstep(0.4, -0.2, d);
	foam = max(foam, foam2 * 0.65);
	foam *= 0.62 + 0.38 * sin(d * 5.0 - game_time * 1.3);
	c = mix(c, vec3(0.95, 0.98, 0.97), clamp(foam, 0.0, 1.0));
	vec3 nrm = normalize(vec3(sin(p.x * 0.85 + game_time), 5.5, cos(p.y * 0.7 - game_time * 0.8)));
	float glint = pow(max(dot(nrm, normalize(vec3(0.35, 0.86, 0.28))), 0.0), 48.0);
	c += vec3(1.0, 0.96, 0.82) * glint * 0.45 * (1.0 - night_k);
	float alpha = mix(0.42, 0.86, deep);
	alpha = mix(alpha, 0.92, clamp(foam, 0.0, 1.0) * 0.5);
	ALBEDO = c;
	ALPHA = alpha;
	ROUGHNESS = mix(0.18, 0.55, night_k);
	SPECULAR = 0.45;
}
