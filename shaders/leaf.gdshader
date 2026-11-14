shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;
// Leaf sprays of the bushes (island.gd _build_leaves, one MultiMesh): alpha-tested twig cards.
// Instance colour = tint (sRGB), its alpha = how much the spray sways (more towards the top of the bush);
// instance custom = the outward direction from the bush's heart (world) and the inner occlusion (w).
// The cards are shaded with that outward normal, so a bush lights as one soft volume rather than a
// pile of flat cards, wrap diffuse and a back-light let the sun glow through the thin leaves.
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float game_time = 0.0;
uniform float wind = 1.0;
global uniform float night_k;
#include "res://shaders/cutout.gdshaderinc"
#include "res://shaders/refl_clip.gdshaderinc"
varying vec3 wpos;
varying vec3 nrm;
varying float ao;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float s = COLOR.a * wind * (1.0 - UV.y);
	float ph = w.x * 0.9 + w.z * 0.7 + INSTANCE_CUSTOM.x * 3.0;
	float t = game_time;
	vec3 off = vec3(sin(t * 1.3 + ph) * 0.035 + sin(t * 3.9 + ph * 2.7) * 0.012,
		sin(t * 2.4 + ph * 1.7) * 0.01,
		cos(t * 1.1 + ph * 1.3) * 0.028 + sin(t * 3.3 + ph * 2.1) * 0.01) * s;
	mat3 m = mat3(MODEL_MATRIX);
	// the instance basis is a rotation times a uniform scale: its inverse is the transpose over scale²
	VERTEX += transpose(m) * off / dot(m[0], m[0]);
	wpos = w + off;
	nrm = INSTANCE_CUSTOM.xyz;
	ao = INSTANCE_CUSTOM.w;
}

void fragment() {
	vec4 tx = texture(leaf_tex, UV);
	if (tx.a < 0.5) {
		discard;
	}
	if (!IN_SHADOW_PASS && refl_pass(CAMERA_POSITION_WORLD)) {
		if (wpos.y < 0.0) {
			discard;
		}
	} else if (!IN_SHADOW_PASS) {
		float cut = cut_amount(wpos, CAMERA_POSITION_WORLD);
		if (cut > 0.55 || cut > bayer4(FRAGCOORD.xy)) {
			discard;
		}
	}
	vec3 c = pow(COLOR.rgb, vec3(2.2)) * tx.rgb;
	float lum = dot(c, vec3(0.30, 0.59, 0.11));
	c = mix(c, vec3(0.10, 0.14, 0.12) * (0.7 + lum), night_k * 0.88);
	ALBEDO = c * mix(0.75, 1.3, ao);
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	ROUGHNESS = 0.75;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	BACKLIGHT = c * (0.35 + 0.45 * ao) * (1.0 - night_k * 0.92);
}
