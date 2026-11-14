shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"

// Jade water after the "Wired to Fish" look: clear over the sand in the shallows (the terrain shader
// tints and caustics the bottom), greener and more opaque with depth. Each surf cycle a lacy breaker
// band rolls in, hands over to the swash foam on the sand (terrain.gdshader) and leaves drifting lace
// behind; sun (or moon) glints sparkle on the small waves.
uniform vec3 c_shallow : source_color = vec3(0.42, 0.80, 0.70);
uniform vec3 c_mid : source_color = vec3(0.24, 0.66, 0.60);
uniform vec3 c_deep : source_color = vec3(0.13, 0.50, 0.52);
uniform vec3 c_abyss : source_color = vec3(0.09, 0.37, 0.45);
uniform vec3 c_sky : source_color = vec3(0.82, 0.89, 0.90);
uniform sampler2D obj_foam : filter_linear, repeat_disable;
uniform float game_time = 0.0;
uniform vec4 ripples[8];
uniform vec3 glint_dir = vec3(0.45, 0.62, -0.64);   // towards the sun / moon (world)
uniform vec3 glint_col : source_color = vec3(1.0, 0.95, 0.85);
uniform float glint_gain = 1.0;
uniform float night = 0.0;
// planar reflection (reflection.gd): the scene mirrored about the water plane, flipped vertically
uniform sampler2D refl_tex : source_color, filter_linear, repeat_disable, hint_default_black;
uniform float refl_on = 0.0;
uniform float refl_gain = 1.0;
uniform float refl_guard = 0.1;
// night lights that streak across the waves: xyz, w = strength (0 off); rgb colour
uniform vec4 lamp_pos[12];
uniform vec4 lamp_col[12];
// the rowboat by the dock: centre x/z, cos / sin of its yaw; its waterline (starboard half, boat x/z,
// stern to bow; the hull is the same fore and aft) for the foam collar and the small rings it rocks off
uniform vec4 boat_c = vec4(0.0, 0.0, 1.0, 0.0);
uniform vec2 boat_wl[17];
uniform vec2 boat_box = vec2(1.4, 2.4);
uniform float boat_on = 0.0;

varying vec3 wpos;

const vec2 WK0 = vec2(0.82, 0.57);
const vec2 WK1 = vec2(-0.45, 0.89);
const vec2 WK2 = vec2(0.97, -0.24);
const vec2 WK3 = vec2(-0.71, -0.70);

vec2 wave_grad(vec2 p, float t) {
	vec2 g = vec2(0.0);
	g += WK0 * 1.6 * 0.030 * cos(dot(WK0, p) * 1.6 + t * 1.3);
	g += WK1 * 2.3 * 0.022 * cos(dot(WK1, p) * 2.3 + t * 1.7);
	g += WK2 * 3.7 * 0.013 * cos(dot(WK2, p) * 3.7 + t * 2.3);
	g += WK3 * 5.9 * 0.008 * cos(dot(WK3, p) * 5.9 + t * 2.9);
	return g;
}

// signed distance (m, outside > 0) from the boat's waterline, in boat x/z
float boat_sd(vec2 q) {
	vec2 a = abs(q);
	float d = 1e3;
	bool inside = false;
	for (int i = 8; i < 16; i++) {
		vec2 p0 = boat_wl[i];
		vec2 p1 = boat_wl[i + 1];
		vec2 e = p1 - p0;
		vec2 w = a - p0;
		float h = clamp(dot(w, e) / max(dot(e, e), 1e-6), 0.0, 1.0);
		d = min(d, length(w - e * h));
		if (a.y >= p0.y && a.y < p1.y) {
			inside = a.x < mix(p0.x, p1.x, (a.y - p0.y) / max(p1.y - p0.y, 1e-6));
		}
	}
	return inside ? -d : d;
}

// thin anti-aliased line of half-width w (metres) at distance x
float aline(float x, float w, float fw) {
	float ww = w + fw;
	return (1.0 - smoothstep(ww * 0.5, ww, abs(x))) * clamp(w / ww * 1.4, 0.0, 1.0);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sea_y(wp.xz, game_time);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = game_time;
	float d = shore_d(p);
	float depth = seabed_depth(max(d, 0.0));
	float fwd = fwidth(d);

	// --- layered small-wave normal
	vec2 g = wave_grad(p, t);
	float e = 0.2;
	vec2 q1 = p * 1.9 + vec2(t * 0.32, t * 0.21);
	float n0 = vnoise(q1);
	g += vec2(vnoise(q1 + vec2(e, 0.0)) - n0, vnoise(q1 + vec2(0.0, e)) - n0) / e * 0.06;
	vec2 q2 = p * 4.3 - vec2(t * 0.45, -t * 0.38);
	float m0 = vnoise(q2);
	g += vec2(vnoise(q2 + vec2(e, 0.0)) - m0, vnoise(q2 + vec2(0.0, e)) - m0) / e * 0.025;
	g *= mix(0.4, 1.0, smoothstep(0.0, 4.0, d)); // calmer in the shallows

	// --- stone ripples
	float rip = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 r = ripples[i];
		float age = t - r.z;
		// footsteps (w ~0.3) make small, short-lived rings; stones big ones
		float life = r.w < 0.5 ? 1.6 : 3.2;
		if (r.w > 0.0 && age > 0.0 && age < life) {
			vec2 dv = p - r.xy;
			float dist = length(dv);
			float fade = (1.0 - age / life) * r.w;
			for (int k = 0; k < 2; k++) {
				float rad = 0.25 + (age - float(k) * 0.28) * (r.w < 0.5 ? 0.7 : 1.45);
				float x = dist - rad;
				float ring = exp(-x * x * 30.0) * fade * (1.0 - float(k) * 0.45) * step(0.0, rad);
				rip += ring;
				g += (dv / max(dist, 0.001)) * ring * 0.35 * sign(x + 0.0001);
			}
		}
	}

	g *= 0.6;
	vec3 nw = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// --- depth colour: pale jade on the shelf, sage / teal past the reef edge
	vec3 col = mix(c_shallow, c_mid, smoothstep(0.05, 1.3, depth));
	col = mix(col, c_deep, smoothstep(1.6, 3.6, depth));
	col = mix(col, c_abyss, smoothstep(3.8, 5.8, depth));
	col *= 1.0 + (vnoise(p * 0.35 + vec2(t * 0.02, 0.0)) - 0.5) * 0.06;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	col *= mix(vec3(1.0), vec3(0.32, 0.42, 0.62), night);
	col = mix(col, mix(c_sky, vec3(0.10, 0.15, 0.28), night), fres * 0.14);

	// --- foam
	float foam = 0.0;
	float th = wpos.y - ground_near(p, d); // water thickness over the sand
	if (d < 7.0) {
		float c = wash_cycle(p, t);
		vec2 rn = normalize(p);
		// the breaker: a lacy band rolling in from ~2.5 m out, merging with the swash as it reaches the sand
		float roll = smoothstep(0.5, 1.0, c);
		float dl = mix(2.6, 0.0, roll) + (vnoise(p * 0.8 + vec2(t * 0.05, 0.0)) - 0.5) * 0.5;
		vec2 q = p * 3.6 + rn * (roll * 6.0) + vec2(t * 0.04, 0.0);
		// every term goes to zero at both ends of the cycle: the phase wraps (fract) along a moving seam
		float form = smoothstep(0.5, 0.68, c) * (1.0 - smoothstep(0.9, 1.0, c));
		float band = exp(-pow((d - dl) / 0.22, 2.0)) * (0.55 + 0.45 * lace(q * 0.7, 0.0));
		band *= smoothstep(0.15, 0.5, vnoise(p * 1.7 + vec2(t * 0.12, 0.0)) + 0.1);
		float wake = lace(q, 0.35) * smoothstep(dl, dl + 0.15, d) * (1.0 - smoothstep(dl + 0.3, dl + 1.6, d));
		foam = (band * 0.9 + wake * 0.45) * form;
		// after the wave has broken, lace spreads over the shallows and slowly pops
		float spent = smoothstep(0.0, 0.06, c) * (1.0 - smoothstep(0.06, 0.55, c));
		float drift = lace(p * 3.1 + vec2(t * 0.05, t * 0.03), mix(0.3, 0.9, 1.0 - spent));
		foam = max(foam, drift * (1.0 - smoothstep(0.1, 1.4, d)) * smoothstep(-0.3, 0.1, d) * (0.15 + 0.35 * spent));
	}

	// --- foam around posts / rocks (baked distance map, 0..3 m)
	vec2 fuv = (p + vec2(64.0)) / 128.0;
	float od = texture(obj_foam, fuv).r * 3.0;
	float nO = vnoise(p * 3.3 + vec2(t * 0.15, 0.0));
	float objf = (1.0 - smoothstep(0.02, 0.2 + nO * 0.25, od)) * (0.45 + 0.55 * lace(p * 4.0 + vec2(t * 0.06, 0.0), 0.1));
	objf += (1.0 - smoothstep(0.0, 1.4, od)) * smoothstep(0.62, 0.95, 0.5 + 0.5 * sin(od * 7.0 - t * 2.0)) * 0.45 * smoothstep(0.3, 0.6, nO);
	foam = max(foam, objf);
	// --- the rowboat: a lacy collar hugging the hull at the waterline, and faint rings it rocks off
	if (boat_on > 0.5) {
		vec2 dv = p - boat_c.xy;
		vec2 q = vec2(dv.x * boat_c.z - dv.y * boat_c.w, dv.x * boat_c.w + dv.y * boat_c.z);
		if (abs(q.x) < boat_box.x && abs(q.y) < boat_box.y) {
			float sd = boat_sd(q);
			float lc = lace(p * 6.0 + vec2(t * 0.25, -t * 0.18), 0.05);
			// (the flared topsides hide the contact line from above, so broken lace also drifts a hand's
			// width out past the gunwale)
			float collar = exp(-pow((sd - 0.03) / 0.05, 2.0)) * (0.6 + 0.4 * lc);
			collar += exp(-pow((sd - 0.17) / 0.09, 2.0)) * 0.6 * lc;
			float rings = 0.0;
			for (int k = 0; k < 2; k++) {
				float age = fract(t * 0.3 + float(k) * 0.5);
				float x = sd - (0.06 + age * 0.75);
				rings += exp(-x * x / (0.0006 + age * 0.0025)) * (1.0 - age) * (1.0 - age);
			}
			rings *= 0.42 * (0.5 + 0.5 * vnoise(p * 5.0 + vec2(t * 0.2, 0.0)));
			foam = max(foam, clamp(collar * 0.95 + rings, 0.0, 1.0) * step(-0.06, sd));
		}
	}
	foam = max(foam, clamp(rip, 0.0, 1.0) * 0.7);
	float foam_v = clamp(foam, 0.0, 1.0);
	// Night foam is subtle moonlit slate, not emissive cyan-white.
	vec3 foam_col = mix(vec3(0.97, 0.99, 1.0), vec3(0.28, 0.34, 0.44), night);
	col = mix(col, foam_col, foam_v * mix(1.0, 0.38, night));

	// --- glints: tiny twinkling highlights of the sun (or the moon's path at night) on the wave facets
	vec3 vw = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 rw = reflect(-vw, nw);
	float gd = max(dot(rw, normalize(glint_dir)), 0.0);
	vec2 gc = floor(p * 9.0);
	vec2 gf = fract(p * 9.0) - 0.5 - (vec2(hash12(gc + 3.1), hash12(gc + 7.7)) - 0.5) * 0.5;
	float tw = step(0.55, hash12(gc + floor(t * 5.0 + hash12(gc) * 5.0))) * (1.0 - smoothstep(0.06, 0.2, length(gf)));
	float glint = pow(gd, 300.0) * tw * 6.0 + pow(gd, 40.0) * 0.12 * mix(1.0, 0.85, night);
	glint *= (1.0 - foam_v) * glint_gain * mix(1.0, 0.70, night);

	vec3 emis = glint_col * glint;
	float fr = 0.02 + 0.98 * pow(1.0 - clamp(dot(nw, vw), 0.0, 1.0), 5.0);
	float rk = 0.0;
	if (refl_on > 0.5) {
		// the mirrored scene, shifted by how far the wave normal leans (in screen space). The mirror image is
		// overscanned by refl_guard each side and the shift kept inside that band, so it never runs off the
		// image at a screen edge; what still comes near its border blends into a plain sky
		vec3 n0 = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		vec2 off = (NORMAL.xy - n0.xy) * vec2(0.22, -0.22);
		float ol = length(off);
		off *= min(1.0, refl_guard * 0.8 / max(ol, 1e-5));
		vec2 ruv = 0.5 + (vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y) + off - 0.5) / (1.0 + 2.0 * refl_guard);
		vec3 R = texture(refl_tex, clamp(ruv, vec2(0.001), vec2(0.999))).rgb;
		vec2 eb = min(ruv, 1.0 - ruv);
		float ek = smoothstep(0.0, 0.012, min(eb.x, eb.y));
		vec3 fb = mix(c_sky, mix(vec3(0.09, 0.14, 0.25), vec3(0.025, 0.05, 0.13), smoothstep(0.0, 0.5, max(rw.y, 0.0))), night);
		R = mix(fb, R, ek);
		rk = clamp(fr * 1.6 + 0.07, 0.0, 1.0) * (1.0 - foam_v) * refl_gain;
		col *= 1.0 - rk;
		emis += R * rk;
	}
	// Night: moon glitter path (visible from dock/overview) + warm lamp/torch streaks.
	if (night > 0.001) {
		float ry = max(rw.y, 0.0);
		vec3 gd_n = normalize(glint_dir);
		float ma = acos(clamp(dot(rw, gd_n), -1.0, 1.0));
		// Specular moon blob + glitter.
		vec3 moon = vec3(0.82, 0.88, 1.0) * (exp(-ma / 0.12) * 0.45 + exp(-ma / 0.55) * 0.18);
		moon += vec3(0.95, 0.97, 1.0) * (1.0 - smoothstep(0.02, 0.07, ma)) * 0.95;
		float sc = step(0.92, hash12(gc + 11.0 + floor(t * 0.7 + hash12(gc + 5.0) * 3.0))) * (1.0 - smoothstep(0.03, 0.14, length(gf)));
		moon += vec3(0.86, 0.90, 1.0) * sc * 0.38 * smoothstep(0.02, 0.35, ry);
		// Explicit moon path on the water plane: streak from camera toward moon azimuth.
		vec2 mdir = normalize(gd_n.xz + vec2(1e-4));
		vec2 from_cam = wpos.xz - CAMERA_POSITION_WORLD.xz;
		float along = dot(from_cam, mdir);
		vec2 perp = from_cam - mdir * along;
		float path_w = 0.55 + 0.035 * max(along, 0.0);
		float path = exp(-dot(perp, perp) / (path_w * path_w))
			* smoothstep(-2.0, 6.0, along)
			* smoothstep(90.0, 18.0, along);
		float spark = step(0.88, hash12(gc + 19.0 + floor(t * 3.5 + hash12(gc + 2.0) * 4.0)))
			* (1.0 - smoothstep(0.02, 0.11, length(gf)));
		moon += vec3(0.82, 0.90, 1.0) * path * (0.75 + 1.05 * spark);
		if (refl_on < 0.5) {
			vec3 nsky = mix(vec3(0.11, 0.16, 0.28), vec3(0.04, 0.07, 0.16), smoothstep(0.0, 0.5, ry));
			col = mix(col, nsky, fr * night * (1.0 - foam_v));
		}
		emis += moon * (0.70 + 0.95 * fr) * night * (1.0 - foam_v) * glint_gain;
		vec3 streak = vec3(0.0);
		for (int i = 0; i < 12; i++) {
			vec4 lp = lamp_pos[i];
			if (lp.w > 0.0) {
				vec3 L = lp.xyz - wpos;
				float dl = length(L);
				vec3 h = normalize(L / dl + vw);
				float nh = max(dot(nw, h), 0.0);
				float s = pow(nh, 700.0) * tw * 5.0 + pow(nh, 140.0) * 0.45 + pow(nh, 24.0) * 0.05;
				streak += lamp_col[i].rgb * s * lp.w / (1.0 + dl * dl * 0.018);
			}
		}
		// Warm shore glints near dock/path torches.
		emis += streak * night * (1.0 - foam_v) * 1.85;
	}

	ALBEDO = col;
	EMISSION = emis;
	ROUGHNESS = mix(0.3, 0.7, foam_v);
	SPECULAR = 0.2 * (1.0 - night) * (1.0 - 0.75 * refl_on);
	METALLIC = 0.0;
	// clear over the sand, greener and more opaque with depth; a soft fade where it thins onto the beach
	float a = mix(0.16, 0.62, smoothstep(0.0, 0.9, depth));
	a = mix(a, 0.9, smoothstep(1.2, 3.2, depth));
	a = mix(a, 0.97, smoothstep(3.8, 5.5, depth));
	a *= smoothstep(0.0, 0.07, th);
	ALPHA = clamp(a + fres * 0.14 * smoothstep(0.0, 0.05, th) + foam_v + glint + rk * smoothstep(0.0, 0.05, th) * 0.8, 0.0, 1.0);
}
