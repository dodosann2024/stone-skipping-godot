shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// v40 water colours, depth steps, breaker and lace. No discard.

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
float lace(vec2 q, float thin) {
	float a = abs(vnoise(q) - 0.5);
	float b = abs(vnoise(q * 2.17 + vec2(5.2, 1.3)) - 0.5);
	float w = mix(0.11, 0.028, thin);
	float l = (1.0 - smoothstep(w * 0.3, w, a)) * 0.8 + (1.0 - smoothstep(w * 0.25, w * 0.8, b)) * 0.55;
	float holes = smoothstep(0.25 + thin * 0.45, 0.6 + thin * 0.3, vnoise(q * 0.43 + vec2(2.7, 8.1)));
	return clamp(l, 0.0, 1.0) * holes;
}

const vec2 WK0 = vec2(0.82, 0.57);
const vec2 WK1 = vec2(-0.45, 0.89);
const vec2 WK2 = vec2(0.97, -0.24);
const vec2 WK3 = vec2(-0.71, -0.70);
const vec3 C_SHALLOW = vec3(0.42, 0.80, 0.70);
const vec3 C_MID = vec3(0.24, 0.66, 0.60);
const vec3 C_DEEP = vec3(0.13, 0.50, 0.52);
const vec3 C_ABYSS = vec3(0.09, 0.37, 0.45);

void vertex() {
	vec3 v = VERTEX;
	float t = game_time;
	v.y += sin(dot(WK0, VERTEX.xz) * 0.55 + t * 0.9) * 0.07;
	v.y += sin(dot(WK1, VERTEX.xz) * 0.8 + t * 1.15) * 0.045;
	v.y += sin(dot(WK2, VERTEX.xz) * 0.32 - t * 0.7) * 0.035;
	wpos = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
	VERTEX = v;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = game_time;
	float d = length(p) - island_r(atan(p.y, p.x));
	float r0 = island_r(-1.5707963);
	float sea_end = -(r0 + 13.5);
	float shore = -(r0 - 3.2);
	// Past the pier the play camera looks out to sea. Push that water to abyss
	// so the 35 degree view has a gradient, not one cyan field.
	float past = clamp((sea_end - p.y) / 16.0, 0.0, 1.0);
	float depth = clamp(max(d, 0.0) * 0.22, 0.0, 6.0);
	depth = max(depth, past * 5.2);
	vec3 col = mix(C_SHALLOW, C_MID, smoothstep(0.05, 1.3, depth));
	col = mix(col, C_DEEP, smoothstep(1.6, 3.6, depth));
	col = mix(col, C_ABYSS, smoothstep(3.8, 5.6, depth));
	col *= 1.0 + (vnoise(p * 0.35 + vec2(t * 0.02, 0.0)) - 0.5) * 0.08;

	vec2 g = WK0 * 1.6 * 0.055 * cos(dot(WK0, p) * 1.6 + t * 1.3);
	g += WK1 * 2.3 * 0.04 * cos(dot(WK1, p) * 2.3 + t * 1.7);
	g += WK2 * 3.7 * 0.022 * cos(dot(WK2, p) * 3.7 + t * 2.3);
	g += WK3 * 5.9 * 0.012 * cos(dot(WK3, p) * 5.9 + t * 2.9);
	g *= mix(0.55, 1.0, smoothstep(0.0, 4.0, d));
	vec3 nw = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float ndl = clamp(dot(nw, normalize(vec3(0.45, 0.82, 0.28))) * 0.5 + 0.5, 0.0, 1.0);
	col *= mix(0.68, 1.12, ndl);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 sky = vec3(0.82, 0.89, 0.90);
	col = mix(col, sky, fres * 0.16);
	col = mix(col, vec3(0.06, 0.12, 0.22), night_k * 0.72);

	float cyc = fract(t * 0.105 + vnoise(p * 0.18) * 0.6 + atan(p.y, p.x));
	float roll = smoothstep(0.45, 1.0, cyc);
	float dl = mix(2.6, 0.05, roll);
	float form = smoothstep(0.5, 0.68, cyc) * (1.0 - smoothstep(0.9, 1.0, cyc));
	float band = exp(-pow((d - dl) / 0.22, 2.0)) * form;
	vec2 rn = p * 3.6 + normalize(p + vec2(0.01)) * (roll * 6.0);
	band *= 0.55 + 0.45 * lace(rn * 0.7, 0.0);
	float spent = smoothstep(0.0, 0.06, cyc) * (1.0 - smoothstep(0.06, 0.55, cyc));
	float drift = lace(p * 3.1 + vec2(t * 0.05, t * 0.03), mix(0.3, 0.9, 1.0 - spent));
	drift *= (1.0 - smoothstep(0.1, 1.4, d)) * smoothstep(-0.3, 0.15, d) * (0.15 + 0.35 * spent);
	float along = smoothstep(sea_end - 0.4, sea_end + 1.2, p.y) * (1.0 - smoothstep(shore - 0.5, shore + 1.5, p.y));
	float beside = smoothstep(1.2, 1.55, abs(p.x)) * (1.0 - smoothstep(2.4, 3.4, abs(p.x)));
	float pier = beside * along * (0.45 + 0.55 * lace(p * 4.0 + vec2(t * 0.06, 0.0), 0.15));
	float open_lace = lace(p * 1.8 + vec2(t * 0.04, -t * 0.03), 0.35) * (0.18 + 0.55 * past);
	float foam = clamp(max(max(max(band, drift), pier), open_lace), 0.0, 1.0);
	vec3 foam_col = mix(vec3(0.97, 0.99, 1.0), vec3(0.28, 0.34, 0.44), night_k);
	col = mix(col, foam_col, foam * mix(0.92, 0.4, night_k));

	float glint = pow(max(dot(nw, normalize(vec3(0.45, 0.62, -0.64))), 0.0), 18.0);
	col += vec3(1.0, 0.95, 0.85) * glint * 0.18 * (1.0 - night_k) * (1.0 - foam);

	float alpha = mix(0.62, 0.84, smoothstep(0.0, 1.2, depth));
	alpha = mix(alpha, 0.96, smoothstep(2.0, 4.8, depth));
	alpha = clamp(alpha + fres * 0.1 + foam * 0.4, 0.0, 1.0);
	ALBEDO = col;
	ALPHA = alpha;
	ROUGHNESS = mix(0.12, 0.62, foam);
	SPECULAR = 0.5;
}
