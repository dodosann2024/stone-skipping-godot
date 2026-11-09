shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.36, 0.88, 0.80);
uniform vec3 mid_color : source_color = vec3(0.04, 0.60, 0.72);
uniform vec3 deep_color : source_color = vec3(0.02, 0.24, 0.50);
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);

varying vec3 wpos;

float shore_z(float x) {
	// Must match main.gd shore_z()
	float l = min(x, 0.0);
	float r = max(x, 0.0);
	return 1.0 - 0.05 * l * l + 0.006 * r * r + 0.6 * sin(x * 0.25);
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(wpos.x * 0.35 + TIME * 1.1) * 0.035 + cos(wpos.z * 0.42 + TIME * 0.9) * 0.035;
	VERTEX.y += w;
}

void fragment() {
	float d = shore_z(wpos.x) - wpos.z; // metres seaward from the shoreline
	float t1 = smoothstep(0.0, 7.0, d);
	float t2 = smoothstep(6.0, 32.0, d);
	vec3 col = mix(shallow_color, mid_color, t1);
	col = mix(col, deep_color, t2);
	// caustic-ish sparkle in the shallows
	float n = noise(wpos.xz * 1.3 + vec2(TIME * 0.35, TIME * 0.2));
	float n2 = noise(wpos.xz * 2.7 - vec2(TIME * 0.25, TIME * 0.4));
	col += (1.0 - t1) * 0.10 * smoothstep(0.55, 0.9, n * n2 * 1.8);
	// animated shoreline foam bands
	float wave = sin(d * 2.2 - TIME * 1.6 + noise(wpos.xz * 0.5) * 3.0);
	float foam = smoothstep(0.85, 1.0, wave) * (1.0 - smoothstep(0.0, 3.5, d));
	foam = max(foam, 1.0 - smoothstep(0.05, 0.55 + 0.25 * sin(TIME * 1.3 + wpos.x * 0.7), d));
	foam *= step(-0.2, d);
	col = mix(col, foam_color, clamp(foam, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = 0.32;
	METALLIC = 0.0;
	SPECULAR = 0.2;
	ALPHA = clamp(mix(0.55, 0.97, t1 * 0.6 + t2 * 0.4) + foam, 0.0, 1.0);
}
