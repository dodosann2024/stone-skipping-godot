shader_type spatial;
render_mode cull_back;
// The rowboat floating by the dock: the static props' look, but measured against the water as drawn, so
// the hull below the waterline takes the water's colour and wobbles a little, right at the visible line.
#include "res://shaders/cutout.gdshaderinc"
#include "res://shaders/underwater.gdshaderinc"
#include "res://shaders/refl_clip.gdshaderinc"

uniform vec3 hull_col : source_color = vec3(0.3, 0.6, 0.8);

varying vec3 wpos;
// depth below the drawn water, per vertex: the surface is linear across a 7.45 m cell and the hull's faces
// are small, so interpolating it is as good as working it out per pixel
varying float dep;

// the boat's rest transform in its current model space: the mooring line follows it towards the dock end,
// whose knot stays put while the boat bobs (rope vertices: alpha 0.69 - 0.99)
uniform mat4 pin = mat4(1.0);

void vertex() {
	if (COLOR.a > 0.6 && COLOR.a < 0.995) {
		VERTEX = mix(VERTEX, (pin * vec4(VERTEX, 1.0)).xyz, clamp((0.99 - COLOR.a) / 0.3, 0.0, 1.0));
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	dep = uw_shown_y(wpos.xz) - wpos.y;
	VERTEX += transpose(mat3(MODEL_MATRIX)) * uw_refract_d(wpos, dep);
}

void fragment() {
	float d = dep;
	vec3 base = COLOR.rgb;
	if (!IN_SHADOW_PASS && refl_pass(CAMERA_POSITION_WORLD)) {
		if (d > 0.0) {
			discard;
		}
		if (COLOR.a < 0.5) {
			base = hull_col;
		}
	} else if (!IN_SHADOW_PASS && cut_amount(wpos, CAMERA_POSITION_WORLD) > bayer4(FRAGCOORD.xy)) {
		discard;
	}
	// a painted hull reads through more water than a leg does: tint it as if a little deeper
	ALBEDO = uw_tint_d(base, wpos, d > 0.0 ? d * 1.8 + 0.04 * smoothstep(0.0, 0.03, d) : d);
	ROUGHNESS = 0.88;
}
