// See-through cone from the camera to the kid, so the high follow camera never loses him behind a
// palm crown, the umbrella or a roof (screen-door dither, works on the Compatibility renderer).
// main.gd sets `focus` every frame; shadow passes are left alone.
uniform vec3 focus = vec3(0.0, -100.0, 0.0);
uniform float cut_radius = 1.5;

float bayer4(vec2 fc) {
	ivec2 q = ivec2(mod(fc, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

// how much of this fragment to remove (0 keep .. 1 gone)
float cut_amount(vec3 wpos, vec3 cam) {
	if (focus.y < -50.0) {
		return 0.0;
	}
	vec3 seg = focus - cam;
	float len = length(seg);
	float k = clamp(dot(wpos - cam, seg) / (len * len), 0.0, 1.0);
	float dist = length(wpos - (cam + seg * k));
	float r = cut_radius * mix(0.45, 1.25, smoothstep(0.0, 0.9, k));
	float hide = (1.0 - smoothstep(r * 0.45, r, dist)) * (1.0 - smoothstep(0.88, 0.985, k));
	// Anything right in front of the lens (crates / posts / stairs that hide the boy).
	float near = 1.0 - smoothstep(len * 0.15, len * 0.50, length(wpos - cam));
	hide = max(hide, near * (1.0 - smoothstep(r * 1.0, r * 1.7, dist)));
	// Near occluders: cut down to ground. Far ones: still prefer above-waist (keep decks).
	float y0 = mix(focus.y - 1.55, focus.y - 0.20, smoothstep(0.12, 0.55, k));
	return hide * smoothstep(y0, focus.y + 0.40, wpos.y);
}
