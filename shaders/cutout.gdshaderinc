// See-through cone from the camera to the kid, so the high follow camera never loses him behind a
// palm crown, bush, umbrella or roof (screen-door dither, Compatibility-safe).
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
	// Occluders from just in front of the lens to the boy's silhouette.
	// Was k>0.99 → 0, which left bush leaves on his shoulders solid (v34 web).
	if (k < 0.01 || k > 0.999) {
		return 0.0;
	}
	float dist = length(wpos - (cam + seg * k));
	// Fat soft capsule — leaf walls / bushes must open in the web follow cam.
	float r = cut_radius * mix(1.2, 2.2, smoothstep(0.01, 0.40, k))
		* mix(1.0, 0.92, smoothstep(0.88, 0.999, k));
	float hide = (1.0 - smoothstep(r * 0.03, r, dist));
	// Soften only the extreme near field (avoid grey rectangles in the lens).
	float along = length(wpos - cam);
	hide *= smoothstep(0.06, 0.32, along);
	// Vertical band covering crown→soles so a bush can't cover torso while ankles stay.
	float y0 = focus.y - 1.85;
	float y1 = focus.y + 1.25;
	hide *= smoothstep(y0 - 0.40, y0 + 0.06, wpos.y) * (1.0 - smoothstep(y1, y1 + 0.30, wpos.y));
	return clamp(hide, 0.0, 1.0);
}
