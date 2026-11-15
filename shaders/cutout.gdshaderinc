// See-through volume from the camera to the boy, plus a capsule around the
// posed body, so palms, bushes and leaf cards cannot hide him.
// Compatibility-safe: screen-door dither, hard open in the core, vertex bend
// supplied as foliage_bend(). Shadow passes are left alone.
uniform vec3 focus = vec3(0.0, -100.0, 0.0);
uniform vec3 focus_lo = vec3(0.0, -100.0, 0.0);
uniform vec3 focus_hi = vec3(0.0, -100.0, 0.0);
uniform float cut_radius = 1.5;
uniform float body_radius = 0.92;

float bayer4(vec2 fc) {
	ivec2 q = ivec2(mod(fc, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

float dist_to_seg(vec3 p, vec3 a, vec3 b) {
	vec3 ab = b - a;
	float denom = max(dot(ab, ab), 0.0001);
	float t = clamp(dot(p - a, ab) / denom, 0.0, 1.0);
	return length(p - (a + ab * t));
}

vec3 seg_points(out vec3 lo, out vec3 hi) {
	lo = focus_lo.y < -50.0 ? focus - vec3(0.0, 0.95, 0.0) : focus_lo;
	hi = focus_hi.y < -50.0 ? focus + vec3(0.0, 0.72, 0.0) : focus_hi;
	return focus;
}

// 0 keep .. 1 gone
float cut_amount(vec3 wpos, vec3 cam) {
	if (focus.y < -50.0) {
		return 0.0;
	}
	vec3 lo;
	vec3 hi;
	seg_points(lo, hi);
	// View-ray capsule. Extend slightly past the boy so leaves ON him open.
	vec3 seg = focus - cam;
	float len2 = max(dot(seg, seg), 0.0001);
	float k = dot(wpos - cam, seg) / len2;
	float along_k = clamp(k, 0.0, 1.0);
	vec3 closest = cam + seg * along_k;
	float dist = length(wpos - closest);
	if (k > 1.0) {
		dist = length(wpos - focus);
	}
	float r = cut_radius * mix(1.05, 1.45, smoothstep(0.02, 0.35, along_k));
	float hide = 1.0 - smoothstep(r * 0.20, r, dist);
	// Body capsule: anything near the posed head–feet segment must open,
	// including a bush he is standing inside (k ≈ 1, which the old test skipped).
	float bd = dist_to_seg(wpos, lo, hi);
	float body = 1.0 - smoothstep(body_radius * 0.35, body_radius, bd);
	hide = max(hide, body);
	// Hard-open the core so a leaf card cannot sit on the shirt.
	if (bd < body_radius * 0.55) {
		hide = 1.0;
	}
	float along = length(wpos - cam);
	hide *= smoothstep(0.05, 0.28, along);
	return clamp(hide, 0.0, 1.0);
}

// Push foliage vertices off the posed body. World-space offset.
vec3 foliage_bend(vec3 wpos, vec3 cam) {
	if (focus.y < -50.0) {
		return vec3(0.0);
	}
	vec3 lo;
	vec3 hi;
	seg_points(lo, hi);
	vec3 ab = hi - lo;
	float denom = max(dot(ab, ab), 0.0001);
	float t = clamp(dot(wpos - lo, ab) / denom, 0.0, 1.0);
	vec3 c = lo + ab * t;
	vec3 away = wpos - c;
	// Also shove leaves that sit on the view ray, not only on the body.
	vec3 seg = focus - cam;
	float len2 = max(dot(seg, seg), 0.0001);
	float k = clamp(dot(wpos - cam, seg) / len2, 0.0, 1.0);
	vec3 ray_away = wpos - (cam + seg * k);
	if (length(ray_away) < length(away)) {
		away = ray_away;
		c = wpos - away;
	}
	float d = length(away);
	float reach = body_radius * 1.65;
	if (d > reach || d < 0.0001) {
		return vec3(0.0);
	}
	float s = 1.0 - d / reach;
	s = s * s;
	return (away / d) * s * 0.62;
}
