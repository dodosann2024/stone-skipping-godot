shader_type spatial;
render_mode cull_disabled, diffuse_lambert;
// Vertex colour RGB = albedo (sRGB), A = sway weight.
uniform float game_time = 0.0;
uniform float wind = 1.0;
// see-through cone from the camera to the kid, so the high follow camera never loses him under
// a palm crown (screen-door dither, works on the Compatibility renderer)
uniform vec3 focus = vec3(0.0, -100.0, 0.0);
uniform float cut_radius = 1.5;

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

float bayer4(vec2 fc) {
	ivec2 q = ivec2(mod(fc, 4.0));
	int i = q.x + q.y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

void fragment() {
	if (focus.y > -50.0) {
		vec3 cam = CAMERA_POSITION_WORLD;
		vec3 seg = focus - cam;
		float len = length(seg);
		float k = clamp(dot(wpos - cam, seg) / (len * len), 0.0, 1.0);
		float dist = length(wpos - (cam + seg * k));
		float r = cut_radius * mix(0.25, 1.0, smoothstep(0.0, 0.9, k));
		float hide = (1.0 - smoothstep(r * 0.6, r, dist)) * (1.0 - smoothstep(0.88, 0.97, k));
		// and anything right in front of the lens
		hide = max(hide, 1.0 - smoothstep(len * 0.35, len * 0.6, length(wpos - cam)));
		if (hide > bayer4(FRAGCOORD.xy)) {
			discard;
		}
	}
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = 0.8;
	BACKLIGHT = vec3(0.25, 0.35, 0.12) * COLOR.a;
}
