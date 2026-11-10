shader_type spatial;
render_mode cull_back;
// Soft stylized character shading: sRGB vertex colours, wrapped diffuse with a warm terminator on skin,
// gentle sheen, a soft rim and a little self-lift so the face never goes muddy.
// Vertex colour alpha = material id: 1 cloth, 0.8 skin, 0.6 straw, 0.4 hair.
uniform float lift = 0.1;
uniform float rim = 0.22;

varying vec3 opos;
varying float mid;

void vertex() {
	opos = VERTEX;
	mid = COLOR.a;
}

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float straw = 1.0 - smoothstep(0.08, 0.12, abs(mid - 0.6));
	if (straw > 0.0) {
		float r = length(opos.xz);
		float a = atan(opos.z, opos.x);
		float w = sin(a * 110.0) * sin((r + opos.y) * 240.0);
		float fade = 1.0 - smoothstep(0.004, 0.02, fwidth(r + opos.y));
		c *= 1.0 + straw * w * 0.07 * fade;
	}
	ALBEDO = c;
	ROUGHNESS = 0.7;
	SPECULAR = 0.25;
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = c * (lift + f * rim);
}

void light() {
	float skin = 1.0 - smoothstep(0.08, 0.12, abs(mid - 0.8));
	float hair = 1.0 - smoothstep(0.08, 0.12, abs(mid - 0.4));
	float ndl = dot(NORMAL, LIGHT);
	float w = mix(0.35, 0.55, skin);
	float d = clamp((ndl + w) / (1.0 + w), 0.0, 1.0);
	d = d * d * (3.0 - 2.0 * d);
	float sh = mix(0.35, 1.0, ATTENUATION);
	vec3 warm = vec3(1.0, 0.45, 0.32) * skin * 0.35 * d * (1.0 - clamp(ndl * 2.0, 0.0, 1.0));
	DIFFUSE_LIGHT += LIGHT_COLOR * sh * (d + warm) / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float s = pow(clamp(dot(NORMAL, h), 0.0, 1.0), mix(18.0, 40.0, hair)) * mix(0.06, 0.14, hair);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * s;
}
