shader_type spatial;
// Vertex-coloured low-poly character: sRGB vertex colours, a little self-lift so the
// kid's face never goes muddy in shadow / backlight, plus a soft rim light.
uniform float lift = 0.14;
uniform float rim = 0.3;

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = c;
	ROUGHNESS = 0.78;
	SPECULAR = 0.3;
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = c * (lift + f * rim);
}
