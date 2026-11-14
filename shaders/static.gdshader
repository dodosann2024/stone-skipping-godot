shader_type spatial;
render_mode cull_back;
// Static props (hut, dock, rocks, umbrella, boats...): vertex colour albedo + the camera cut-out.
#include "res://shaders/cutout.gdshaderinc"
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
	} else if (!IN_SHADOW_PASS) {
		float cut = cut_amount(wpos, CAMERA_POSITION_WORLD);
		// Strong occlusion still fully hides crates; mild occlusion only dithers.
		if (cut > 0.72 || (cut > 0.12 && cut > bayer4(FRAGCOORD.xy))) {
			discard;
		}
	}
	ALBEDO = COLOR.rgb;   // as the old StandardMaterial3D rendered them on the Compatibility renderer
	if (wpos.y < 0.1) {
		ALBEDO = uw_tint(ALBEDO, wpos);
	}
	ROUGHNESS = 0.88;
}
