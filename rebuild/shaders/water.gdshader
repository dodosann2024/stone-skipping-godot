shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

uniform vec4 deep_color : source_color = vec4(0.08, 0.42, 0.52, 0.62);
uniform vec4 shore_color : source_color = vec4(0.55, 0.82, 0.74, 0.38);
uniform float game_time = 0.0;

void fragment() {
	float wave = sin(UV.x * 40.0 + game_time) * 0.5 + sin(UV.y * 28.0 - game_time * 1.3) * 0.5;
	ALBEDO = mix(shore_color.rgb, deep_color.rgb, 0.55 + wave * 0.08);
	ALPHA = mix(shore_color.a, deep_color.a, 0.6);
}
