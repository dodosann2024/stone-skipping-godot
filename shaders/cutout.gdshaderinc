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
	// Only occluders BETWEEN camera and boy (not behind him).
	if (k < 0.02 || k > 0.98) {
		return 0.0;
	}
	float dist = length(wpos - (cam + seg * k));
	// Wider soft capsule while exploring so leaf walls can't swallow the kid.
	// Tapers near the camera (avoid sky holes) and near the boy (keep bush silhouette at his feet).
	float r = cut_radius * mix(0.55, 1.15, smoothstep(0.05, 0.55, k))
		* mix(1.0, 0.72, smoothstep(0.70, 0.95, k));
	float hide = (1.0 - smoothstep(r * 0.25, r, dist));
	// Soften the very near field so we don't punch grey rectangles into close foliage.
	float along = length(wpos - cam);
	hide *= smoothstep(0.35, 1.1, along);
	// Vertical band covering head→feet so a bush can't cover his hat while leaving ankles.
	float y0 = focus.y - 1.15;
	float y1 = focus.y + 0.55;
	hide *= smoothstep(y0 - 0.15, y0 + 0.25, wpos.y) * (1.0 - smoothstep(y1, y1 + 0.45, wpos.y));
	return clamp(hide, 0.0, 1.0);
}
