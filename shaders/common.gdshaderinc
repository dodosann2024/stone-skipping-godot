// Shared island shape + noise helpers (keep island_R / seabed in sync with main.gd).
float island_R(float th) {
	return 19.0 + 2.2 * sin(2.0 * th + 0.6) + 1.6 * sin(3.0 * th + 1.9) + 0.9 * sin(5.0 * th + 0.3);
}
float shore_d(vec2 p) { // metres seaward of the shoreline (negative = on land)
	return length(p) - island_R(atan(p.y, p.x));
}
float seabed_depth(float d) {
	return clamp(d * 0.17, 0.0, 1.7) + smoothstep(13.0, 26.0, d) * 4.0;
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
// gentle swell height; the water plane's vertices and the beach wash use the same sea level
float sea_y(vec2 p, float t) {
	return 0.03 * sin(dot(vec2(0.82, 0.57), p) * 0.5 + t * 0.9) + 0.02 * sin(dot(vec2(-0.45, 0.89), p) * 0.8 + t * 1.2);
}
// island.gd ground_h() close to the waterline (the inland hills start further up)
float ground_near(vec2 p, float d) {
	float n = 0.07 * sin(p.x * 0.9 + p.y * 0.4) + 0.05 * cos(p.y * 1.3 - p.x * 0.5) + 0.04 * sin(p.x * 2.1 - p.y * 1.7);
	if (d > 0.0) {
		return -seabed_depth(d) + n * 0.6;
	}
	return 0.9 * smoothstep(0.0, 6.0, -d) + n * (0.6 + 0.4 * smoothstep(0.0, 3.0, -d));
}
// surf cycle along the beach: at 0 a foam line reaches the sand, the wash runs up, then drains back.
// 6 sets around the island (integer, so there is no seam where atan wraps) plus slow local jitter.
float wash_cycle(vec2 p, float t) {
	return fract(t * 0.105 + vnoise(p * 0.18) * 0.6 + atan(p.y, p.x) * (6.0 / 6.2831853));
}
// how high (m above the sea level) the wash has climbed at cycle phase c: quick run-up, slow drain
float runup(float c) {
	return 0.07 * smoothstep(0.0, 0.26, c) * (1.0 - smoothstep(0.26, 0.9, c));
}
// lacy foam: contour lines of two noise octaves make a meandering web; `thin` (0..1) eats it away into
// sparse strands and bubbles as the foam ages
float lace(vec2 q, float thin) {
	float a = abs(vnoise(q) - 0.5);
	float b = abs(vnoise(q * 2.17 + vec2(5.2, 1.3)) - 0.5);
	float w = mix(0.11, 0.025, thin);
	float l = (1.0 - smoothstep(w * 0.3, w, a)) * 0.8 + (1.0 - smoothstep(w * 0.25, w * 0.8, b)) * 0.55;
	float holes = smoothstep(0.25 + thin * 0.45, 0.6 + thin * 0.3, vnoise(q * 0.43 + vec2(2.7, 8.1)));
	return clamp(l, 0.0, 1.0) * holes;
}
