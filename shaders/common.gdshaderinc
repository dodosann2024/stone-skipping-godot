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
float swash(vec2 p, float t) { // how far the wash creeps up the beach (0..~0.8 m)
	return 0.38 + 0.32 * sin(t * 0.75 + vnoise(p * 0.35) * 4.0 + atan(p.y, p.x) * 3.0);
}
