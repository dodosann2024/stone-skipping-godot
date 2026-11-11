shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// v17 hair (art/boy/hair.py): layered strand cards over a thin scalp cap, one surface of the boy mesh.
// Cards are alpha-tested (opaque pass, depth written: no sorting) against the strand atlas
// (tools/hair_texture.py), with the coverage boosted in the small mips so distant hair stays full.
// Their normals lean on the scalp normal (baked in Blender), so the mass lights as one soft volume.
// Highlights are Kajiya-Kay along the strand (UV v runs root -> tip, so BINORMAL is the strand): a
// faint white primary shifted to the root side and a broader, hair-tinted secondary towards the tip,
// both broken up per strand. Back light glows through the thin tips; roots and inner layers are darker.
// Per vertex: COLOR.r baked AO, COLOR.b under the hat crown; UV2.x sway weight (cards) / distance to
// the hairline (cap); 1 - UV2.y card inner-layer occlusion, or 1 on the cap.

uniform sampler2D strands : filter_linear_mipmap, repeat_disable;
uniform vec3 root_col : source_color = vec3(0.21, 0.14, 0.10);
uniform vec3 mid_col : source_color = vec3(0.33, 0.23, 0.155);
uniform vec3 tip_col : source_color = vec3(0.56, 0.43, 0.30);
uniform float ao_strength = 0.5;
uniform float hat_on = 1.0;
uniform vec3 sway = vec3(0.0);        // tip offset, mesh space (boy.gd: head motion + wind)
uniform float flutter = 0.0;          // per-strand jitter amplitude, mesh space
uniform float game_time = 0.0;
#include "res://shaders/refl_clip.gdshaderinc"

varying float ao;
varying float occ;
varying float cap;
varying float edge;
varying vec3 strand;
varying float shift;
varying float tipv;

float hash1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	ao = COLOR.r;
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

void fragment() {
	if (!IN_SHADOW_PASS && refl_pass(CAMERA_POSITION_WORLD) && (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y < 0.0) {
		discard;
	}
	vec3 tx;
	float v;
	if (cap > 0.5) {
		// procedural strands running away from the crown (UV.x = angle round it, UV.y = distance)
		float k = UV.x * 1400.0;
		float id = floor(k);
		float far = smoothstep(0.4, 1.2, fwidth(k));
		tx = mix(vec3(hash1(id), 0.55 + 0.35 * hash1(id + 7.1), hash1(id + 3.3)), vec3(0.5, 0.7, 0.5), far);
		// soft, broken hairline
		if (edge < 0.15 + 0.7 * hash1(id + 11.0) * (1.0 - far)) {
			discard;
		}
		v = 0.15;
	} else {
		vec4 t4 = texture(strands, UV);
		vec2 d = fwidth(UV * vec2(textureSize(strands, 0)));
		float mip = max(0.0, log2(max(d.x, d.y)));
		if (t4.a * (1.0 + mip * 0.35) < 0.5) {
			discard;
		}
		tx = t4.rgb;
		v = UV.y;
	}
	vec3 c = mix(root_col, mid_col, smoothstep(0.0, 0.45, v));
	c = mix(c, tip_col, smoothstep(0.5, 1.0, v) * 0.8);
	c *= mix(0.75, 1.2, tx.r);
	float root = mix(0.5, 1.0, smoothstep(0.0, 0.55, v)) * (1.0 - occ * 0.7) * mix(0.65, 1.0, tx.g);
	ALBEDO = c * root * mix(1.0, ao, ao_strength);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;        // both sides of a card take the bent (scalp-ward) normal
	}
	strand = normalize(BINORMAL);
	shift = tx.b - 0.5;
	tipv = v * (1.0 - cap);
	ROUGHNESS = 0.8;
}

float kk(vec3 t, vec3 h, float e) {
	float th = dot(t, h);
	return pow(sqrt(max(1.0 - th * th, 0.0)), e);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float d = clamp((ndl + 0.5) / 1.5, 0.0, 1.0);
	d = d * d * (3.0 - 2.0 * d);
	float sh = mix(0.3, 1.0, ATTENUATION);
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
	SPECULAR_LIGHT += LIGHT_COLOR * vis * (kk(t1, h, 140.0) * 0.035 + kk(t2, h, 22.0) * 0.06 * m2 * tint);
}
