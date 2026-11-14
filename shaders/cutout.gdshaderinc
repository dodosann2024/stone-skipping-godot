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
	float len = max(length(seg), 0.001);
	float k = clamp(dot(wpos - cam, seg) / (len * len), 0.0, 1.0);
	float dist = length(wpos - (cam + seg * k));
	// Keep the cone tight — a wide dithered cut read as a grey translucent rectangle
	// through the canopy on iPhone (day path). Prefer spring-arm pull-in over a big hole.
	float r = cut_radius * mix(0.40, 0.95, smoothstep(0.0, 0.85, k));
	float hide = (1.0 - smoothstep(r * 0.35, r, dist)) * (1.0 - smoothstep(0.86, 0.985, k));
	// Only cut true near occluders right on the camera→boy axis (posts / crates), not a
	// broad near-field disc that punches sky holes into side foliage.
	float along = length(wpos - cam);
	float near = (1.0 - smoothstep(len * 0.08, len * 0.28, along))
		* (1.0 - smoothstep(r * 0.55, r * 0.95, dist));
	hide = max(hide, near);
	float y0 = mix(focus.y - 1.35, focus.y - 0.15, smoothstep(0.12, 0.55, k));
	return hide * smoothstep(y0, focus.y + 0.35, wpos.y);
}
