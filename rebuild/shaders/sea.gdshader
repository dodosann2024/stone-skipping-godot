shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// v40 water colours and lace, without a discard. Mip-safe noise only.

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
	float b = abs(vnoise(q * 2.17 + vec2(5.2, 1.3)) - 0.5);
	float l = (1.0 - smoothstep(0.03, 0.12, a)) * 0.75 + (1.0 - smoothstep(0.02, 0.08, b)) * 0.45;
	return clamp(l, 0.0, 1.0);
}

const vec2 WK0 = vec2(0.82, 0.57);
const vec2 WK1 = vec2(-0.45, 0.89);
const vec2 WK2 = vec2(0.97, -0.24);

void vertex() {
	vec3 v = VERTEX;
	float t = game_time;
	v.y += sin(VERTEX.x * 0.35 + t * 0.8) * 0.045 + sin(VERTEX.z * 0.28 - t) * 0.03;
	wpos = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
	VERTEX = v;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = game_time;
	float d = length(p) - island_r(atan(p.y, p.x));
	float depth = clamp(d * 0.22, 0.0, 6.0);
	vec3 shallow = vec3(0.42, 0.80, 0.70);
	vec3 midc = vec3(0.24, 0.66, 0.60);
	vec3 deepc = vec3(0.13, 0.50, 0.52);
	vec3 abyss = vec3(0.09, 0.37, 0.45);
	vec3 col = mix(shallow, midc, smoothstep(0.05, 1.3, depth));
	col = mix(col, deepc, smoothstep(1.6, 3.6, depth));
	col = mix(col, abyss, smoothstep(3.8, 5.8, depth));
	col *= 1.0 + (vnoise(p * 0.35 + vec2(t * 0.02, 0.0)) - 0.5) * 0.06;

	vec2 g = WK0 * 0.05 * cos(dot(WK0, p) * 1.6 + t * 1.3);
	g += WK1 * 0.035 * cos(dot(WK1, p) * 2.3 + t * 1.7);
	g += WK2 * 0.02 * cos(dot(WK2, p) * 3.7 + t * 2.3);
	g *= mix(0.45, 1.0, smoothstep(0.0, 4.0, d));
	vec3 nw = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 sky = vec3(0.82, 0.89, 0.90);
	col = mix(col, sky, fres * 0.18);
	col = mix(col, vec3(0.06, 0.12, 0.22), night_k * 0.72);

	float cyc = fract(t * 0.11 + vnoise(p * 0.15) * 0.4);
	float roll = smoothstep(0.45, 1.0, cyc);
	float dl = mix(2.4, 0.05, roll);
	float form = smoothstep(0.5, 0.7, cyc) * (1.0 - smoothstep(0.88, 1.0, cyc));
	float band = exp(-pow((d - dl) / 0.28, 2.0)) * form;
	vec2 rn = p * 3.2 + normalize(p + vec2(0.01)) * roll * 4.0;
	band *= 0.45 + 0.55 * lace(rn);
	float drift = lace(p * 2.6 + vec2(t * 0.05, t * 0.02));
	drift *= (1.0 - smoothstep(0.05, 1.3, d)) * smoothstep(-0.4, 0.15, d);
	float foam = clamp(max(band, drift * 0.65), 0.0, 1.0);
	vec3 foam_col = mix(vec3(0.96, 0.98, 0.99), vec3(0.28, 0.34, 0.44), night_k);
	col = mix(col, foam_col, foam * mix(0.9, 0.4, night_k));

	vec3 light_dir = normalize(vec3(0.45, 0.82, 0.28));
	float glint = pow(max(dot(nw, light_dir), 0.0), 64.0);
	col += vec3(1.0, 0.96, 0.84) * glint * 0.55 * (1.0 - night_k) * (1.0 - foam);

	float alpha = mix(0.22, 0.62, smoothstep(0.0, 0.9, depth));
	alpha = mix(alpha, 0.9, smoothstep(1.2, 3.2, depth));
	alpha = mix(alpha, 0.97, smoothstep(3.8, 5.5, depth));
	alpha = clamp(alpha + fres * 0.12 + foam * 0.35, 0.0, 1.0);
	ALBEDO = col;
	ALPHA = alpha;
	ROUGHNESS = mix(0.08, 0.55, foam);
	SPECULAR = 0.55;
}
