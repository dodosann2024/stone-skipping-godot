shader_type spatial;
render_mode cull_back;
// Static props (hut, dock, rocks, umbrella, boats...): vertex colour albedo + the camera cut-out.
#include "res://shaders/cutout.gdshaderinc"
#include "res://shaders/underwater.gdshaderinc"

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (!IN_SHADOW_PASS && cut_amount(wpos, CAMERA_POSITION_WORLD) > bayer4(FRAGCOORD.xy)) {
		discard;
	}
	ALBEDO = COLOR.rgb;   // as the old StandardMaterial3D rendered them on the Compatibility renderer
	if (wpos.y < 0.1) {
		ALBEDO = uw_tint(ALBEDO, wpos);
	}
	ROUGHNESS = 0.88;
}
