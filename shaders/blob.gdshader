shader_type spatial;
// Soft contact disc under the kid. Discard (not alpha blend) so Compatibility
// never Bayer-dithers a hard square. Tiny screen-door softens the rim.
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform float strength = 0.85;

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	// Solid dark core; only the outer 25% of the radius dithers away.
	float core = pow(clamp(1.0 - r, 0.0, 1.0), 1.15);
	if (r > 0.98) {
		discard;
	}
	if (r > 0.72) {
		float rim = smoothstep(0.98, 0.72, r);
		vec2 grid = floor(mod(FRAGCOORD.xy, 2.0));
		float door = (grid.x + grid.y * 2.0) * 0.25;
		if (rim < 0.15 + door * 0.85) {
			discard;
		}
	}
	float k = clamp(core * strength, 0.35, 0.95);
	// Opaque dark stain sitting on the terrain.
	ALBEDO = mix(vec3(0.18, 0.14, 0.11), vec3(0.03, 0.025, 0.02), k);
}
