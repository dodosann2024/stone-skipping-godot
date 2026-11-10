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

vec3 uw_tint(vec3 c, vec3 wpos) {
	float dep = uw_depth(wpos);
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

// refraction for vertices under the surface: they appear shallower (~3/4 depth) and wobble a little
vec3 uw_refract(vec3 wpos) {
	float dep = uw_depth(wpos);
	if (dep <= 0.0) {
		return vec3(0.0);
	}
	float t = sea_time;
	float k = smoothstep(0.0, 0.05, dep);
	vec2 wob = vec2(sin(wpos.y * 18.0 + t * 3.1 + wpos.z * 4.0), sin(wpos.y * 15.0 - t * 2.7 + wpos.x * 4.0)) * 0.012 * k;
	return vec3(wob.x, dep * 0.22, wob.y);
}
