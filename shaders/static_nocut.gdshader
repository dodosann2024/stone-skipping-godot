shader_type spatial;
render_mode cull_back;
// Path lanterns / props that must stay solid (no camera cut-out cone).
#include "res://shaders/underwater.gdshaderinc"
#include "res://shaders/refl_clip.gdshaderinc"
// night_k comes from underwater.gdshaderinc (global uniform).

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (!IN_SHADOW_PASS && refl_pass(CAMERA_POSITION_WORLD)) {
		if (wpos.y < 0.0) {
			discard;
		}
	}
	ALBEDO = COLOR.rgb;
	float nk = night_k;
	// Path-lantern amber glass + wood cage: readable hanging lantern at night (not a bare post).
	if (COLOR.r > 0.35 && COLOR.r < 0.55 && COLOR.g > 0.20 && COLOR.g < 0.40 && COLOR.b < 0.22) {
		EMISSION = COLOR.rgb * mix(0.28, 0.85, nk);
	} else if (COLOR.r < 0.50 && COLOR.g < 0.35 && COLOR.b < 0.25) {
		// Dark wood/metal cage — slight warm rim so the hanging body reads against the post.
		EMISSION = vec3(0.08, 0.05, 0.02) * nk;
		ALBEDO = mix(ALBEDO, ALBEDO * vec3(1.15, 1.05, 0.9), nk * 0.35);
	}
	if (wpos.y < 0.1) {
		ALBEDO = uw_tint(ALBEDO, wpos);
	}
	ROUGHNESS = 0.88;
}
