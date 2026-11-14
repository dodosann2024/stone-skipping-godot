shader_type spatial;
render_mode cull_disabled, diffuse_lambert;
// Vertex colour RGB = albedo (sRGB), A = sway weight.
uniform float game_time = 0.0;
uniform float wind = 1.0;
global uniform float night_k;
#include "res://shaders/cutout.gdshaderinc"
#include "res://shaders/refl_clip.gdshaderinc"
varying vec3 wpos;

void vertex() {
	float s = COLOR.a * wind;
	vec3 w = VERTEX; // merged mesh at origin -> world space
	float ph = w.x * 0.17 + w.z * 0.13;
	float t = game_time;
	VERTEX.x += s * (sin(t * 1.2 + ph) * 0.11 + sin(t * 3.3 + ph * 4.0) * 0.025);
	VERTEX.z += s * (cos(t * 1.0 + ph * 1.3) * 0.07 + sin(t * 2.9 + ph * 3.0) * 0.02);
	VERTEX.y += s * sin(t * 2.1 + ph * 2.0) * 0.035;
	wpos = VERTEX;
}

void fragment() {
	if (!IN_SHADOW_PASS && refl_pass(CAMERA_POSITION_WORLD)) {
		if (wpos.y < 0.0) {
			discard;
		}
	} else if (!IN_SHADOW_PASS) {
		float cut = cut_amount(wpos, CAMERA_POSITION_WORLD);
		// Prefer dither over a solid sky-hole; open earlier so he stays readable in bushes.
		if (cut > 0.55 || (cut > 0.02 && cut > bayer4(FRAGCOORD.xy))) {
			discard;
		}
	}
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	// Night: desaturate daytime leaf green toward cool blue-green (no neon canopy).
	float lum = dot(c, vec3(0.30, 0.59, 0.11));
	c = mix(c, vec3(0.10, 0.14, 0.12) * (0.7 + lum), night_k * 0.88);
	ALBEDO = c;
	ROUGHNESS = 0.8;
	// Kill the green subsurface glow at night — it read as a lantern bloom blob.
	BACKLIGHT = vec3(0.25, 0.35, 0.12) * COLOR.a * (1.0 - night_k * 0.92);
}
