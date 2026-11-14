shader_type spatial;
render_mode cull_back;
// The tiki torches' pole, bamboo cup, lashing and wick: the static props' shader, plus the warm light of
// each torch's own flame. That flame sits on top of the cup, so a point light there only grazes the cup and
// pole; its glow wraps round them instead (no side is left black at night) and falls off down the pole.
// `flames[i].w` is 0 by day, so the daytime look is the static shader's.
#include "res://shaders/cutout.gdshaderinc"
#include "res://shaders/underwater.gdshaderinc"
#include "res://shaders/refl_clip.gdshaderinc"

uniform vec4 flames[2];                       // xyz: flame (world), w: strength (night x flicker)
uniform vec3 flame_col : source_color = vec3(1.0, 0.56, 0.26);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
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
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.88;
	vec3 e = vec3(0.0);
	for (int i = 0; i < 2; i++) {
		if (flames[i].w <= 0.0) {
			continue;
		}
		vec3 d = flames[i].xyz - wpos;
		float r = length(d);
		float facing = dot(normalize(wnorm), d / max(r, 1e-4));
		// half wrapped round, so the far side of the cup still glows; the side facing the flame more
		float wrap = 0.42 + 0.58 * clamp(facing, 0.0, 1.0);
		float fall = 1.0 / (1.0 + r * r * 22.0);
		e += flame_col * (flames[i].w * wrap * fall);
	}
	EMISSION = ALBEDO * e;
}
