shader_type spatial;
// Glowing coals and ash under the fire: charcoal with slowly breathing orange cracks.
// Opaque disc (no discard) — Compatibility Bayer-stipples any alpha/discard rim into dotted grey.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;

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
	// Soft edge via albedo darkening, not discard/alpha (avoids stipple).
	float edge = smoothstep(1.05, 0.72, r);
	float cells = vnoise(UV * 9.0) * 0.6 + vnoise(UV * 23.0) * 0.4;
	float breathe = vnoise(UV * 5.0 + vec2(TIME * 0.35, -TIME * 0.27));
	float glow = smoothstep(0.42, 0.75, cells * 0.7 + breathe * 0.5) * (1.0 - smoothstep(0.35, 0.90, r));
	vec3 ash = mix(vec3(0.06, 0.05, 0.045), vec3(0.22, 0.20, 0.18), smoothstep(0.55, 1.0, r) * 0.5);
	vec3 col = mix(ash, vec3(1.0, 0.36, 0.06) * 1.35, glow);
	ALBEDO = col * edge;
	if (edge < 0.02) {
		ALBEDO = vec3(0.04, 0.035, 0.03);
	}
}
