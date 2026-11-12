shader_type spatial;
render_mode cull_back;
// v22 hair (art/boy/hair.py): solid, tapered locks over a smooth hair mass - an opaque, stylised little-boy
// cut, no cards and no alpha. Each lock is warm brown, a little darker at the root and lighter at the
// tip, with a few soft strand grooves along it that fade out before they can shimmer. Its normals lean on
// the head's volume (baked in Blender), so the hair lights as one soft shape and the locks read on it.
// Highlights are Kajiya-Kay along the lock (UV v runs root -> tip, so BINORMAL is the strand): a broad,
// hair-tinted sheen. Back light glows a little through the tips. Under the hat brim, out of the sun, a
// soft sky fill from above and warm bounce from below keep the locks readable.
// Per vertex: COLOR.r baked AO, COLOR.b under the hat crown; UV2.x sway weight (0 root .. 1 tip, 0 on the
// mass), 1 - UV2.y = 1 on the mass.

uniform vec3 root_col : source_color = vec3(0.42, 0.28, 0.15);
uniform vec3 mid_col : source_color = vec3(0.60, 0.40, 0.22);
uniform vec3 tip_col : source_color = vec3(0.72, 0.52, 0.32);
uniform float ao_strength = 0.6;
uniform float fill_sky = 0.13;
uniform float fill_bounce = 0.2;
uniform float fill_rim = 0.3;
uniform float hat_on = 1.0;
uniform vec3 sway = vec3(0.0);        // tip offset, mesh space (boy.gd: head motion + wind)
uniform float flutter = 0.0;          // per-lock jitter amplitude, mesh space
uniform float game_time = 0.0;
#include "res://shaders/refl_clip.gdshaderinc"
global uniform float night_k;
// at night the ambient and the moon are blue, which turns brown hair grey where the torches don't reach:
// the albedo is warmed against them, and the torches' (omni) light divided by the same tint, so torch-lit
// hair keeps its colour too
uniform vec3 night_warm = vec3(1.12, 1.02, 0.9);

varying float ao;
varying float mass;
varying float tipv;
varying float crown;
varying vec3 strand;

float hash1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	ao = COLOR.r;
	crown = COLOR.b * hat_on;
	mass = step(0.5, 1.0 - UV2.y);      // glTF stores V flipped
	float w = UV2.x * (1.0 - mass) * (1.0 - COLOR.b * hat_on);
	if (w > 0.0) {
		float ph = dot(VERTEX, vec3(310.0, 170.0, 240.0));
		vec3 fl = vec3(sin(game_time * 6.3 + ph), sin(game_time * 4.7 + ph * 1.3), cos(game_time * 5.9 + ph * 0.7));
		VERTEX += (sway + fl * flutter) * w;
	}
}

void fragment() {
	if (!IN_SHADOW_PASS && refl_pass(CAMERA_POSITION_WORLD) && (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y < 0.0) {
		discard;
	}
	float v = mix(UV.y, 0.1, mass);
	vec3 c = mix(root_col, mid_col, smoothstep(0.0, 0.3, v) * 0.6 + 0.4);
	c = mix(c, tip_col, smoothstep(0.5, 1.0, v) * 0.2);
	// soft strand grooves along the lock (round it: UV.x), gone before they are a pixel wide
	float g = UV.x * 6.2832 * 4.0 + sin(UV.y * 5.0 + UV.x * 20.0) * 0.6;
	float fade = 1.0 - smoothstep(0.25, 0.9, fwidth(g));
	c *= 1.0 + (sin(g) * 0.5 + 0.5 - 0.5) * 0.14 * fade * (1.0 - mass);
	// the mass between the locks is the shade between them
	c *= mix(1.0, 0.97, mass);
	float soft = 1.0 - 0.4 * hat_on * smoothstep(0.0, 0.6, 1.0 - ao);
	ALBEDO = c * mix(1.0, ao, ao_strength * soft) * mix(vec3(1.0), night_warm, night_k);
	strand = normalize(BINORMAL);
	tipv = v * (1.0 - mass);
	ROUGHNESS = 0.62;
	SPECULAR = 0.2;
}

float kk(vec3 t, vec3 h, float e) {
	float th = dot(t, h);
	return pow(sqrt(max(1.0 - th * th, 0.0)), e);
}

void light() {
	vec3 d0 = DIFFUSE_LIGHT;
	float ndl = dot(NORMAL, LIGHT);
	float d = clamp((ndl + 0.5) / 1.5, 0.0, 1.0);
	d = d * d * (3.0 - 2.0 * d);
	float sh = mix(0.3, 1.0, ATTENUATION);
	vec3 lc = LIGHT_COLOR;
	if (!LIGHT_IS_DIRECTIONAL) {
		// firelight: keep its warmth, not its full orange (brown hair would turn carrot)
		lc = mix(vec3(dot(lc, vec3(0.3, 0.55, 0.15))), lc, 0.45);
		// torches / fire: ATTENUATION carries the distance falloff (no shadow floor), soft knee up close
		sh = ATTENUATION / (1.0 + ATTENUATION * max(LIGHT_COLOR.r, max(LIGHT_COLOR.g, LIGHT_COLOR.b)) * 0.45);
	}
	DIFFUSE_LIGHT += lc * sh * d / PI;
	// tips glow a little when the light is behind them
	float back = pow(clamp(dot(-LIGHT, VIEW), 0.0, 1.0), 4.0) * (0.2 + 0.6 * tipv);
	DIFFUSE_LIGHT += lc * sh * back * 0.4 / PI;
	vec3 h = normalize(LIGHT + VIEW);
	vec3 t2 = normalize(strand + NORMAL * -0.1);
	float vis = smoothstep(-0.15, 0.3, ndl) * (LIGHT_IS_DIRECTIONAL ? ATTENUATION : sh);
	vec3 tint = ALBEDO / max(max(ALBEDO.r, max(ALBEDO.g, ALBEDO.b)), 0.02);
	SPECULAR_LIGHT += lc * vis * (kk(strand, h, 90.0) * 0.05 + kk(t2, h, 18.0) * 0.11 * tint);
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 upv = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		float up = dot(NORMAL, upv);
		float shade = 1.0 - ATTENUATION * 0.7;
		vec3 fill = vec3(0.75, 0.85, 1.0) * fill_sky * (0.6 + 0.4 * up) + vec3(1.0, 0.82, 0.62) * fill_bounce * clamp(0.55 - 0.45 * up, 0.0, 1.0);
		DIFFUSE_LIGHT += LIGHT_COLOR * fill * shade / PI;
		vec3 hs = normalize(upv + VIEW);
		SPECULAR_LIGHT += LIGHT_COLOR * shade * fill_sky * kk(t2, hs, 14.0) * 0.2 * tint;
		float free = tipv * (1.0 - crown);
		float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
		DIFFUSE_LIGHT += LIGHT_COLOR * free * rim * fill_rim * shade / PI;
	}
	if (!LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT = d0 + (DIFFUSE_LIGHT - d0) / mix(vec3(1.0), night_warm, night_k);
	}
}
