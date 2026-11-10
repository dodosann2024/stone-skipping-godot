shader_type spatial;
// One flame tongue: an upright billboard (turns about the vertical only) whose shape is eaten away by
// upward-scrolling noise, so the tip splits into flickering tongues. Plain alpha blend of
// an unlit colour: additive/premultiplied washes out over bright sand and the env grade lifts its black.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

uniform float seed = 0.0;
uniform float speed = 1.7;
uniform float strength = 1.0;
uniform vec3 tint : source_color = vec3(1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - origin;
	to_cam.y = 0.0;
	vec3 f = normalize(to_cam + vec3(1e-4, 0.0, 0.0));
	vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), f));
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 wp = origin + r * VERTEX.x * sx + vec3(0.0, VERTEX.y * sy, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(f, 0.0)).xyz);
}

void fragment() {
	float y = 1.0 - UV.y;
	float x = UV.x - 0.5;
	float t = TIME * speed + seed * 13.0;
	float n = fbm(vec2(UV.x * 2.6 + seed * 3.1, y * 2.0 - t));
	float n2 = fbm(vec2(UV.x * 5.5 - seed * 1.7, y * 3.6 - t * 1.55));
	// the flame leans and licks more towards its tip
	x += (n - 0.5) * 0.6 * y + sin(t * 0.8 + seed * 5.0) * 0.05 * y;
	float w = 0.44 * pow(max(1.0 - y, 0.0), 0.6) * (0.7 + 0.3 * n2);
	float body = 1.0 - smoothstep(w * 0.45, w, abs(x));
	body *= smoothstep(0.0, 0.1, y);
	float cut = smoothstep(0.1, 0.95, y + (n2 - 0.5) * 0.55);
	float a = clamp(body * (1.0 - cut * 1.1), 0.0, 1.0);
	float core = clamp(a * 1.7 - 0.6 - y * 0.6, 0.0, 1.0);
	vec3 col = mix(vec3(0.8, 0.14, 0.02), vec3(1.0, 0.5, 0.08), smoothstep(0.05, 0.55, a));
	col = mix(col, vec3(1.0, 0.9, 0.55), core);
	float k = a * strength;
	if (k < 0.01) {
		discard;
	}
	ALBEDO = col * tint;
	ALPHA = clamp(k * 1.7 + core * 0.5, 0.0, 1.0);
}
