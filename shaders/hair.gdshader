shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
// v17 hair (art/boy/hair.py): layered strand cards over a thin scalp cap, one surface of the boy mesh.
// Cards are cut out of the strand atlas (tools/hair_texture.py), with the coverage boosted in the small
// mips so distant hair stays full. The cut is anti-aliased: the solid part of each strand goes through
// the opaque depth pre-pass (depth written, so no sorting), and the last pixel of its edge, where the
// coverage crosses the cut, is blended with a width of one screen pixel (fwidth) - smooth edges close
// up without MSAA (gl_compatibility / WebGL). Shadows still use the plain alpha test.
// Their normals lean on the scalp normal (baked in Blender), so the mass lights as one soft volume.
// Highlights are Kajiya-Kay along the strand (UV v runs root -> tip, so BINORMAL is the strand): a
// faint white primary shifted to the root side and a broader, hair-tinted secondary towards the tip,
// both broken up per strand. Back light glows through the thin tips; roots and inner layers are darker.
// Under the hat brim, out of the sun, a soft sky fill from above and warm bounce from the ground below
// keep the strand layering readable, and the free ends (fringe, sideburns, nape) pick up a faint rim.
// Per vertex: COLOR.r baked AO, COLOR.b under the hat crown; UV2.x sway weight (cards) / distance to
// the hairline (cap); 1 - UV2.y card inner-layer occlusion, or 1 on the cap.

uniform sampler2D strands : filter_linear_mipmap, repeat_disable;
uniform vec3 root_col : source_color = vec3(0.25, 0.17, 0.12);
uniform vec3 mid_col : source_color = vec3(0.39, 0.28, 0.19);
uniform vec3 tip_col : source_color = vec3(0.60, 0.47, 0.33);
uniform float ao_strength = 0.5;
uniform float fill_sky = 0.13;
uniform float fill_bounce = 0.2;
uniform float fill_rim = 0.35;
uniform float hat_on = 1.0;
uniform vec3 sway = vec3(0.0);        // tip offset, mesh space (boy.gd: head motion + wind)
uniform float flutter = 0.0;          // per-strand jitter amplitude, mesh space
uniform float game_time = 0.0;
#include "res://shaders/refl_clip.gdshaderinc"
global uniform float night_k;
// at night the ambient and the moon are blue, which turns brown hair grey where the torches don't reach:
// the albedo is warmed against them, and the torches' (omni) light divided by the same tint, so torch-lit
// hair keeps its colour too
uniform vec3 night_warm = vec3(1.28, 1.06, 0.84);

varying float ao;
varying float occ;
varying float cap;
varying float edge;
varying vec3 strand;
varying float shift;
varying float tipv;
varying float crown;
varying float facing;

float hash1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	ao = COLOR.r;
	crown = COLOR.b * hat_on;
	float yb = 1.0 - UV2.y;            // glTF stores V flipped
	cap = step(0.9, yb);
	occ = yb * (1.0 - cap);
	edge = UV2.x;
	float w = UV2.x * (1.0 - cap) * (1.0 - COLOR.b * hat_on);
	if (w > 0.0) {
		float ph = dot(VERTEX, vec3(310.0, 170.0, 240.0));
		vec3 fl = vec3(sin(game_time * 6.3 + ph), sin(game_time * 4.7 + ph * 1.3), cos(game_time * 5.9 + ph * 0.7));
		VERTEX += (sway + fl * flutter) * w;
	}
}

float card_facing(vec3 p) {
	return abs(dot(normalize(cross(dFdx(p), dFdy(p))), normalize(-p)));
}

void fragment() {
	if (!IN_SHADOW_PASS && refl_pass(CAMERA_POSITION_WORLD) && (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y < 0.0) {
		discard;
	}
	vec3 tx;
	float v;
	float alpha = 1.0;
	if (cap > 0.5) {
		// procedural strands running away from the crown (UV.x = angle round it, UV.y = distance)
		float k = UV.x * 1400.0;
		float id = floor(k);
		float far = smoothstep(0.4, 1.2, fwidth(k));
		tx = mix(vec3(hash1(id), 0.55 + 0.35 * hash1(id + 7.1), hash1(id + 3.3)), vec3(0.5, 0.7, 0.5), far);
		// soft, broken hairline
		float cut = edge - (0.15 + 0.7 * hash1(id + 11.0) * (1.0 - far));
		float cov = IN_SHADOW_PASS ? step(0.0, cut) : clamp(cut / max(fwidth(edge), 1e-4) + 0.5, 0.0, 1.0);
		if (cov < 0.02) {
			discard;
		}
		// thinner towards the hairline: the skin shows through before the last strands stop
		alpha = cov * mix(0.45, 1.0, smoothstep(0.0, 0.75, edge));
		v = 0.15;
	} else {
		vec4 t4 = texture(strands, UV);
		vec2 d = fwidth(UV * vec2(textureSize(strands, 0)));
		// (the atlas is 1024 px: its strands are 2 texels wide, so the thinning starts a mip later)
		float mip = max(0.0, log2(max(d.x, d.y)) - 1.0);
		float a = t4.a * (1.0 + mip * 0.35);
		if (IN_SHADOW_PASS) {
			if (a < 0.5) {
				discard;
			}
		} else {
			float cov = clamp((a - 0.5) / max(fwidth(a), 1e-3) + 0.5, 0.0, 1.0);
			// once a card is only a few pixels wide its strands are long gone into the mips and the cut
			// leaves a hard leaf-shaped blob: blend the filtered coverage instead, so its outline stays soft
			cov = mix(cov, clamp(a * 1.2, 0.0, 1.0), smoothstep(1.0, 3.0, mip));
			// cards seen edge-on are a sub-pixel tangle of strands that only sparkles: fade them out (the
			// cap and the cards behind fill in)
			cov *= smoothstep(0.06, 0.22, card_facing(VERTEX));
			if (cov < 0.02) {
				discard;
			}
			alpha = cov;
		}
		tx = t4.rgb;
		v = UV.y;
	}
	vec3 c = mix(root_col, mid_col, smoothstep(0.0, 0.45, v));
	// (light tips over dark roots in moderation: overlapping short cards band into rows of scales otherwise)
	c = mix(c, tip_col, smoothstep(0.5, 1.0, v) * 0.45);
	c *= mix(0.75, 1.2, tx.r);
	// the hat already shades the hair under it: keep the roots / inner layers / AO darkening softer there
	// so the shadow stays one soft tone instead of dark clumps
	float soft = 1.0 - 0.45 * hat_on * smoothstep(0.0, 0.6, 1.0 - ao);
	float root = mix(mix(0.72, 0.78, hat_on), 1.0, smoothstep(0.0, 0.55, v)) * (1.0 - occ * mix(0.7, 0.5, hat_on)) * mix(0.65, 1.0, tx.g);
	ALBEDO = c * root * mix(1.0, ao, ao_strength * soft) * mix(vec3(1.0), night_warm, night_k);
	ALPHA = alpha;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;        // both sides of a card take the bent (scalp-ward) normal
	}
	strand = normalize(BINORMAL);
	shift = tx.b - 0.5;
	tipv = v * (1.0 - cap);
	// how squarely the card itself (not its bent normal) faces the camera: cards seen edge-on are a
	// sub-pixel tangle of strands, and no rim on those, or it lights that up as speckle
	facing = card_facing(VERTEX);
	ROUGHNESS = 0.8;
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
	if (!LIGHT_IS_DIRECTIONAL) {
		// torches / fire: ATTENUATION carries the distance falloff (no shadow floor), soft knee up close
		sh = ATTENUATION / (1.0 + ATTENUATION * max(LIGHT_COLOR.r, max(LIGHT_COLOR.g, LIGHT_COLOR.b)) * 0.45);
	}
	DIFFUSE_LIGHT += LIGHT_COLOR * sh * d / PI;
	// thin tips glow when the light is behind them
	float back = pow(clamp(dot(-LIGHT, VIEW), 0.0, 1.0), 4.0) * (0.25 + 0.75 * tipv);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * back * 0.55 / PI;
	vec3 h = normalize(LIGHT + VIEW);
	vec3 t1 = normalize(strand + NORMAL * (0.1 + shift * 0.25));
	vec3 t2 = normalize(strand + NORMAL * (-0.12 + shift * 0.35));
	float vis = smoothstep(-0.15, 0.3, ndl) * ATTENUATION;
	vec3 tint = ALBEDO / max(max(ALBEDO.r, max(ALBEDO.g, ALBEDO.b)), 0.02);
	float m2 = 0.4 + 0.6 * fract(shift * 7.31 + 0.5);
	SPECULAR_LIGHT += LIGHT_COLOR * vis * (kk(t1, h, 140.0) * 0.025 + kk(t2, h, 22.0) * 0.06 * m2 * tint);
	if (LIGHT_IS_DIRECTIONAL) {
		// out of the sun (the brim's shadow): sky from above, warm bounce off the sand / deck from below,
		// both soft (wrapped), and a faint rim on the free ends where they stand against the light
		vec3 upv = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		float up = dot(NORMAL, upv);
		float shade = 1.0 - ATTENUATION * 0.7;
		vec3 fill = vec3(0.75, 0.85, 1.0) * fill_sky * (0.6 + 0.4 * up) + vec3(1.0, 0.82, 0.62) * fill_bounce * clamp(0.55 - 0.45 * up, 0.0, 1.0);
		DIFFUSE_LIGHT += LIGHT_COLOR * fill * shade / PI;
		// the sky also leaves a dim, broad sheen along the strands, so the layers separate in the shade
		vec3 hs = normalize(upv + VIEW);
		SPECULAR_LIGHT += LIGHT_COLOR * shade * fill_sky * kk(t2, hs, 16.0) * 0.22 * m2 * tint;
		float free = tipv * (1.0 - crown) * smoothstep(0.15, 0.45, facing);
		float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
		DIFFUSE_LIGHT += LIGHT_COLOR * free * (rim * fill_rim + pow(clamp(dot(-LIGHT, VIEW), 0.0, 1.0), 2.0) * fill_rim * 0.6) * shade / PI;
	}
	if (!LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT = d0 + (DIFFUSE_LIGHT - d0) / mix(vec3(1.0), night_warm, night_k);
	}
}
