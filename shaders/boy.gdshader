shader_type spatial;
render_mode cull_disabled; // Concept A soft body: avoid spike silhouettes from flipped limb normals
// v6 boy: soft, low-contrast shading in the "Wired to Fish" spirit — flat albedo per material,
// wide wrapped diffuse with a warm terminator, cool shadow side (from the ambient), baked AO in
// COLOR.r, a faint rim. The face's painted detail (brows, lash line, lips, blush) is a map in UV2 (front
// projection of the head, metres from the head joint, in the rest pose) so it rides the expression
// morphs; COLOR.b on the skin = warmth (ears). Fine skin grain on UV (MakeHuman layout).
// kind: 0 skin, 1 cloth, 2 hair, 3 straw, 4 plastic/props, 5 inside of the mouth

uniform vec3 albedo : source_color = vec3(0.9);
uniform int kind = 1;
uniform float ao_strength = 0.55;
uniform float rim = 0.12;
uniform float blush = 1.0;
uniform sampler2D face_tex : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec4 face_rect = vec4(-0.075, -0.085, 0.15, 0.18);
uniform vec3 brow_col : source_color = vec3(0.30, 0.19, 0.12);
uniform vec3 lip_col : source_color = vec3(0.95, 0.45, 0.48);
#include "res://shaders/underwater.gdshaderinc"
#include "res://shaders/refl_clip.gdshaderinc"

varying vec2 fuv;
varying float ao;
varying float fmask;
varying float warm;
varying vec3 lpos;
varying vec3 wp0;

void vertex() {
	fuv = vec2(UV2.x, 1.0 - UV2.y);  // glTF stores V flipped
	ao = COLOR.r;
	fmask = COLOR.g;
	warm = COLOR.b;
	lpos = VERTEX;
	wp0 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (wp0.y < 0.12) {
		VERTEX += inverse(mat3(MODEL_MATRIX)) * uw_refract(wp0);
	}
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0)), f.x), f.y);
}

// brows, lash line, lid crease, lip line and nostrils darken; lips and the warm cheeks / nose tint
vec3 face(vec3 c, vec2 p, out float lip) {
	vec2 t = vec2((p.x - face_rect.x) / face_rect.z, 1.0 - (p.y - face_rect.y) / face_rect.w);
	vec4 m = texture(face_tex, t);
	c = mix(c, c * vec3(1.06, 0.88, 0.90), m.a * blush * 0.45);
	c = mix(c, lip_col, m.g * 0.75);
	c = mix(c, brow_col, m.r * 0.85);
	c = mix(c, vec3(0.12, 0.07, 0.06), m.b * 0.9);
	lip = m.g;
	return c;
}

// inside the mouth (the cap between the lips, seen when the "open" morph parts them): UV.x across the
// mouth, UV.y 0 at the upper lip .. 1 at the lower; upper teeth under the top lip, the tongue low
vec3 mouth_inside(vec2 uv) {
	float up = 1.0 - uv.y;
	float side = min(uv.x, 1.0 - uv.x);
	vec3 c = vec3(0.40, 0.13, 0.13);
	c = mix(c, vec3(0.78, 0.40, 0.40), smoothstep(0.42, 0.1, up) * smoothstep(0.08, 0.3, side));
	float gaps = smoothstep(0.0, 0.08, abs(fract(uv.x * 7.0 + 0.5) - 0.5));
	float teeth = smoothstep(0.66, 0.78, up) * smoothstep(0.06, 0.2, side);
	c = mix(c, vec3(0.86, 0.83, 0.76) * mix(0.75, 1.0, gaps), teeth);
	c = mix(c, vec3(0.70, 0.66, 0.60), smoothstep(0.16, 0.04, up) * smoothstep(0.12, 0.3, side) * 0.6);
	return c * mix(0.5, 1.0, smoothstep(0.0, 0.25, side));
}

void fragment() {
	if (!IN_SHADOW_PASS && refl_pass(CAMERA_POSITION_WORLD) && (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y < 0.0) {
		discard;
	}
	vec3 c = albedo;
	float lip = 0.0;
	float aos = ao_strength;
	if (kind == 0) {
		c = mix(c, c * vec3(1.04, 0.82, 0.78), warm * 0.55);
		c *= vec3(1.08, 0.94, 0.82);
		if (fmask > 0.01) {
			float fl;
			c = mix(c, face(c, fuv, fl), fmask);
			lip = fl * fmask;
			aos *= 1.0 - 0.85 * fmask;
		}
		// skin grain, faded out before it can shimmer
		vec2 g = UV * 1500.0;
		float n = vnoise(g) * 0.65 + vnoise(g * 2.3) * 0.35;
		c *= 1.0 + (n - 0.5) * 0.025 * (1.0 - smoothstep(0.25, 0.9, fwidth(g.x) + fwidth(g.y)));
	} else if (kind == 5) {
		c = mouth_inside(UV);
		aos = 0.0;
	} else if (kind == 3) {
		// straw weave: UV.x angle around the crown, UV.y radial distance
		float w = sin(UV.x * 6.2832 * 70.0) * sin(UV.y * 900.0);
		float fade = 1.0 - smoothstep(0.3, 1.0, fwidth(UV.y * 900.0));
		c *= 1.0 + w * 0.09 * fade;
		c *= 1.0 - 0.06 * smoothstep(0.6, 1.0, sin(UV.y * 160.0));
	}
	vec3 a = c * mix(1.0, ao, aos);
	float sub = 0.0;
	if (wp0.y < 0.12) {
		a = uw_tint(a, wp0);
		sub = smoothstep(-0.004, 0.02, uw_depth(wp0));
	}
	ALBEDO = a;
	ROUGHNESS = kind == 4 ? 0.35 : (kind == 0 ? mix(0.66, 0.42, lip) : 0.85);
	SPECULAR = kind == 4 ? 0.5 : (kind == 0 ? 0.3 : 0.15);
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = c * f * rim * (1.0 - sub) * (1.0 - 0.75 * night_k);
	if (kind == 0) {
		// light scattered under the skin keeps the shaded side warm instead of taking the sky's grey-blue
		EMISSION += c * vec3(0.22, 0.10, 0.04) * (1.0 - sub) * (1.0 - 0.5 * night_k);
		// soft fill from the camera, so the face never sinks into grey shade (eye sockets, under the brim)
		EMISSION += c * vec3(0.34, 0.18, 0.08) * clamp(dot(NORMAL, VIEW), 0.0, 1.0) * (1.0 - 0.45 * night_k);
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = kind == 0 ? 0.6 : 0.45;
	float d = clamp((ndl + w) / (1.0 + w), 0.0, 1.0);
	d = d * d * (3.0 - 2.0 * d);
	// sun / moon: lifted shadows. Torches / fire: ATTENUATION carries the distance falloff, so no floor,
	// and a soft knee keeps a face right next to the flame from burning out
	float sh = mix(kind == 0 ? 0.62 : 0.25, 1.0, ATTENUATION);
	if (!LIGHT_IS_DIRECTIONAL) {
		float e = ATTENUATION * max(LIGHT_COLOR.r, max(LIGHT_COLOR.g, LIGHT_COLOR.b));
		sh = ATTENUATION / (1.0 + e * 0.45);
	}
	// warm subsurface-ish band at the terminator on skin
	float term = (kind == 0 ? 0.22 : 0.12) * d * (1.0 - clamp(ndl * 1.6, 0.0, 1.0));
	vec3 lc = LIGHT_COLOR;
	if (kind == 0 && !LIGHT_IS_DIRECTIONAL) {
		// firelight on skin: keep the warmth but not its full saturation (skin x orange reads as salmon)
		lc = mix(vec3(dot(lc, vec3(0.3, 0.55, 0.15))), lc, 0.55) * 0.8;
	}
	DIFFUSE_LIGHT += lc * sh * (d + vec3(1.0, 0.55, 0.45) * term) / PI;
	if (kind == 2 || kind == 4) {
		vec3 h = normalize(LIGHT + VIEW);
		float s = pow(clamp(dot(NORMAL, h), 0.0, 1.0), kind == 2 ? 24.0 : 60.0) * (kind == 2 ? 0.08 : 0.3);
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * s;
	} else if (kind == 0) {
		// a soft sheen on the skin, a little wetter on the lips
		vec3 h = normalize(LIGHT + VIEW);
		float s = pow(clamp(dot(NORMAL, h), 0.0, 1.0), mix(70.0, 14.0, ROUGHNESS)) * (1.0 - ROUGHNESS) * 0.12;
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * s * clamp(ndl * 3.0, 0.0, 1.0);
	}
}
