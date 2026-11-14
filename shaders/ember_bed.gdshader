shader_type spatial;
// Round glowing coal disc on a plane — discard outside the circle (no square corners).
// Soft radial glow; discard rim is a hard circle but the glow fades before it.
render_mode unshaded, cull_disabled, shadows_disabled;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 q = UV - 0.5;
	float r = length(q) * 2.0;
	if (r > 0.98) {
		discard;
	}
	float cells = vnoise(UV * 9.0) * 0.6 + vnoise(UV * 23.0) * 0.4;
	float breathe = vnoise(UV * 5.0 + vec2(TIME * 0.35, -TIME * 0.27));
	float glow = smoothstep(0.40, 0.78, cells * 0.7 + breathe * 0.5) * (1.0 - smoothstep(0.25, 0.88, r));
	vec3 ash = mix(vec3(0.08, 0.07, 0.06), vec3(0.28, 0.24, 0.20), smoothstep(0.40, 0.95, r) * 0.6);
	vec3 col = mix(ash, vec3(1.0, 0.40, 0.08) * 1.55, glow);
	// Soft visual edge: darken toward the discard rim.
	// Fade toward cool ground so the rim reads soft (no hard disc edge).
	vec3 ground = vec3(0.05, 0.07, 0.08);
	float soft = smoothstep(0.98, 0.55, r);
	ALBEDO = mix(ground, col, soft);
	EMISSION = vec3(1.0, 0.36, 0.06) * glow * 0.85 * soft;
}
