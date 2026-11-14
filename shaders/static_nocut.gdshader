shader_type spatial;
render_mode cull_back;
// Path lanterns / props that must stay solid (no camera cut-out cone).
#include "res://shaders/underwater.gdshaderinc"
#include "res://shaders/refl_clip.gdshaderinc"

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
	// Path-lantern amber glass: faint emission so panes glow without becoming a solid box.
	if (COLOR.r > 0.35 && COLOR.r < 0.55 && COLOR.g > 0.20 && COLOR.g < 0.40 && COLOR.b < 0.22) {
		EMISSION = COLOR.rgb * 0.28;
	}
	if (wpos.y < 0.1) {
		ALBEDO = uw_tint(ALBEDO, wpos);
	}
	ROUGHNESS = 0.88;
}
