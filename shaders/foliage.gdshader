shader_type spatial;
render_mode cull_disabled, diffuse_lambert;
// Vertex colour RGB = albedo (sRGB), A = sway weight.
uniform float game_time = 0.0;
uniform float wind = 1.0;

void vertex() {
	float s = COLOR.a * wind;
	vec3 w = VERTEX; // merged mesh at origin -> world space
	float ph = w.x * 0.17 + w.z * 0.13;
	float t = game_time;
	VERTEX.x += s * (sin(t * 1.2 + ph) * 0.11 + sin(t * 3.3 + ph * 4.0) * 0.025);
	VERTEX.z += s * (cos(t * 1.0 + ph * 1.3) * 0.07 + sin(t * 2.9 + ph * 3.0) * 0.02);
	VERTEX.y += s * sin(t * 2.1 + ph * 2.0) * 0.035;
}

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = 0.8;
	BACKLIGHT = vec3(0.25, 0.35, 0.12) * COLOR.a;
}
