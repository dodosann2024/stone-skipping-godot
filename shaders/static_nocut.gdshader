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
	// Softly emissive amber glass; dark metal/wood cage stays shaded (no flat yellow blob).
	if (COLOR.r > 0.35 && COLOR.r < 0.55 && COLOR.g > 0.20 && COLOR.g < 0.40 && COLOR.b < 0.22) {
		EMISSION = COLOR.rgb * mix(0.20, 0.65, nk);
		ALBEDO = COLOR.rgb * mix(1.0, 0.75, nk);
	} else if (COLOR.r < 0.36 && COLOR.g < 0.32 && COLOR.b < 0.30) {
		// Dark metal/wood — lit by the path Omni, slight warm rim only.
		EMISSION = vec3(0.04, 0.025, 0.012) * nk;
	}
	if (wpos.y < 0.1) {
		ALBEDO = uw_tint(ALBEDO, wpos);
	}
	ROUGHNESS = 0.88;
}
