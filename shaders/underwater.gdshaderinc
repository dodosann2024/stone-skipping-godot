// Things standing in the sea (the wading kid, dock posts, rocks): below the surface they take on the
// water colour and darken with depth, with a slight caustic shimmer and a wet band at the waterline.
// The clock is the global `sea_time` (main.gd), so this matches the water plane's swell exactly.
global uniform float sea_time;
global uniform float night_k;

float uw_sea_y(vec2 p) {
	float t = sea_time;
	return 0.03 * sin(dot(vec2(0.82, 0.57), p) * 0.5 + t * 0.9) + 0.02 * sin(dot(vec2(-0.45, 0.89), p) * 0.8 + t * 1.2);
}

// metres below the swell at this point (negative above the water)
float uw_depth(vec3 wpos) {
	return uw_sea_y(wpos.xz) - wpos.y;
}

vec3 uw_tint_d(vec3 c, vec3 wpos, float dep) {
	if (dep < -0.03) {
		return c;
	}
	float d = max(dep, 0.0);
	vec3 water = mix(vec3(0.12, 0.38, 0.38), vec3(0.03, 0.08, 0.12), night_k);
	vec3 under = c * exp(-d * vec3(2.4, 0.95, 1.0)) * vec3(0.7, 0.92, 0.9);
	under = mix(under, water, (1.0 - exp(-d * 2.2)) * 0.85);
	float t = sea_time;
	float cs = sin(wpos.x * 9.0 + wpos.z * 5.0 + t * 2.3) * sin(wpos.z * 8.0 - wpos.y * 6.0 - t * 1.9);
	under += vec3(0.6, 0.85, 0.8) * smoothstep(0.6, 1.0, cs) * 0.06 * exp(-d * 3.0) * (1.0 - night_k);
	vec3 r = mix(c, under, smoothstep(-0.004, 0.02, dep));
	// wet, slightly darker skin / wood just above the surface
	r *= 1.0 - 0.12 * (1.0 - smoothstep(0.0, 0.06, -dep)) * step(dep, 0.0);
	return r;
}

vec3 uw_tint(vec3 c, vec3 wpos) {
	return uw_tint_d(c, wpos, uw_depth(wpos));
}

// refraction for vertices under the surface: a small wobble and only a slight lift. The seabed is not
// refracted, so the full ~1/4 apparent-depth lift would squash the legs and float the feet off the sand
vec3 uw_refract_d(vec3 wpos, float dep) {
	if (dep <= 0.0) {
		return vec3(0.0);
	}
	float t = sea_time;
	float k = smoothstep(0.0, 0.05, dep);
	vec2 wob = vec2(sin(wpos.y * 18.0 + t * 3.1 + wpos.z * 4.0), sin(wpos.y * 15.0 - t * 2.7 + wpos.x * 4.0)) * 0.012 * k;
	return vec3(wob.x, min(dep * 0.06, 0.025), wob.y);
}

vec3 uw_refract(vec3 wpos) {
	return uw_refract_d(wpos, uw_depth(wpos));
}

// the water plane as drawn: a 1200 m PlaneMesh with 161 cells a side, so the swell is linear between its
// vertices (every 7.45 m) and can sit a few cm off uw_sea_y. Things floating on it (the rowboat) use this
float uw_shown_y(vec2 p) {
	float cell = 1200.0 / 161.0;
	vec2 g = (p + vec2(600.0)) / cell;
	vec2 i = floor(g);
	vec2 f = g - i;
	vec2 p0 = i * cell - vec2(600.0);
	float h10 = uw_sea_y(p0 + vec2(cell, 0.0));
	float h01 = uw_sea_y(p0 + vec2(0.0, cell));
	if (f.x + f.y <= 1.0) {
		float h00 = uw_sea_y(p0);
		return h00 + f.x * (h10 - h00) + f.y * (h01 - h00);
	}
	float h11 = uw_sea_y(p0 + vec2(cell));
	return h11 + (1.0 - f.x) * (h01 - h11) + (1.0 - f.y) * (h10 - h11);
}
