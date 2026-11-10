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
	float r = cut_radius * mix(0.25, 1.0, smoothstep(0.0, 0.9, k));
	float hide = (1.0 - smoothstep(r * 0.6, r, dist)) * (1.0 - smoothstep(0.88, 0.97, k));
	// and anything right in front of the lens
	hide = max(hide, 1.0 - smoothstep(len * 0.35, len * 0.6, length(wpos - cam)));
	// only things above the kid's waist get in the way of a high camera; keep decks, rails, rocks
	return hide * smoothstep(focus.y - 0.3, focus.y + 0.4, wpos.y);
}
