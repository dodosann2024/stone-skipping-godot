shader_type spatial;
render_mode cull_back;
// v6 boy: soft, low-contrast shading in the "Wired to Fish" spirit — flat albedo per material,
// wide wrapped diffuse with a warm terminator, cool shadow side (from the ambient), baked AO in
// COLOR.r, a faint rim. The face is drawn here (UV2 = front projection of the head, metres from
// the head joint) so expressions are just uniforms.
// kind: 0 skin, 1 cloth, 2 hair, 3 straw, 4 plastic/props

uniform vec3 albedo : source_color = vec3(0.9);
uniform int kind = 1;
uniform float ao_strength = 0.55;
uniform float rim = 0.12;
uniform float eye_open = 1.0;     // 0 closed (blink / asleep) .. 1 open
uniform int mouth = 0;            // 0 smile, 1 laugh, 2 oops, 3 grit, 4 sleepy
uniform float blush = 0.35;

varying vec2 fuv;
varying float ao;
varying float fmask;
varying vec3 lpos;

void vertex() {
	fuv = vec2(UV2.x, 1.0 - UV2.y);  // glTF stores V flipped
	ao = COLOR.r;
	fmask = COLOR.g;
	lpos = VERTEX;
}

float ellipse(vec2 p, vec2 c, vec2 r, float aa) {
	float d = length((p - c) / r) - 1.0;
	return 1.0 - smoothstep(-aa, aa, d * min(r.x, r.y));
}

float arc(vec2 p, vec2 c, float half_w, float bend, float thick, float aa) {
	vec2 d = p - c;
	float y = bend * (d.x * d.x / (half_w * half_w) - 1.0) * -1.0;
	float m = 1.0 - smoothstep(thick - aa, thick + aa, abs(d.y - y));
	return m * (1.0 - smoothstep(half_w - aa, half_w + aa, abs(d.x)));
}

vec3 face(vec3 c, vec2 p) {
	float aa = clamp(fwidth(p.x) + fwidth(p.y), 0.0004, 0.004);
	vec3 ink = vec3(0.16, 0.10, 0.08);
	// cheeks
	for (int i = 0; i < 2; i++) {
		float s = i == 0 ? 1.0 : -1.0;
		float b = 1.0 - smoothstep(0.0, 1.0, length((p - vec2(0.042 * s, 0.018)) / vec2(0.013, 0.008)));
		c = mix(c, vec3(0.95, 0.55, 0.50), b * blush);
	}
	for (int i = 0; i < 2; i++) {
		float s = i == 0 ? 1.0 : -1.0;
		vec2 e = vec2(0.0315 * s, 0.040);
		float open = clamp(eye_open, 0.0, 1.0);
		if (open > 0.2) {
			float m = ellipse(p, e, vec2(0.0068, 0.0088 * open), aa);
			c = mix(c, ink, m);
			float hl = ellipse(p, e + vec2(-0.0022 * s + 0.001, 0.0032 * open), vec2(0.0022, 0.0024), aa);
			c = mix(c, vec3(1.0), hl * m * 0.9);
		} else {
			// closed: a soft downward arc (happy / asleep)
			c = mix(c, ink, arc(p, e + vec2(0.0, 0.001), 0.0072, -0.0028, 0.0011, aa));
		}
		// brows
		float br = arc(p, e + vec2(0.0005 * s, 0.0145), 0.0085, 0.0018, 0.0012, aa);
		c = mix(c, vec3(0.22, 0.14, 0.10), br * 0.85);
	}
	vec2 mo = vec2(0.0, -0.025);
	if (mouth == 0) {
		c = mix(c, vec3(0.55, 0.22, 0.2), arc(p, mo, 0.0085, -0.0035, 0.0011, aa));
	} else if (mouth == 1) {
		// open laugh: D shape, darker inside, tongue
		vec2 d = p - mo;
		float top = smoothstep(-aa, aa, 0.0015 - d.y);
		float shape = ellipse(p, mo + vec2(0.0, 0.0015), vec2(0.010, 0.0085), aa) * top;
		c = mix(c, vec3(0.42, 0.12, 0.12), shape);
		c = mix(c, vec3(0.86, 0.42, 0.42), shape * ellipse(p, mo + vec2(0.0, -0.005), vec2(0.0055, 0.003), aa));
	} else if (mouth == 2) {
		c = mix(c, vec3(0.42, 0.12, 0.12), ellipse(p, mo, vec2(0.0045, 0.0055), aa));
	} else if (mouth == 3) {
		float m = ellipse(p, mo, vec2(0.009, 0.0035), aa);
		c = mix(c, vec3(0.42, 0.12, 0.12), m);
		c = mix(c, vec3(0.97), m * (1.0 - smoothstep(-aa, aa, abs(p.y - mo.y) - 0.0016)));
	} else {
		c = mix(c, vec3(0.55, 0.22, 0.2), ellipse(p, mo + vec2(0.0, 0.001), vec2(0.004, 0.0028), aa) * 0.9);
	}
	return c;
}

void fragment() {
	vec3 c = albedo;
	if (kind == 0 && fmask > 0.5) {
		c = face(c, fuv);
	} else if (kind == 3) {
		// straw weave: UV.x angle around the crown, UV.y radial distance
		float w = sin(UV.x * 6.2832 * 70.0) * sin(UV.y * 900.0);
		float fade = 1.0 - smoothstep(0.3, 1.0, fwidth(UV.y * 900.0));
		c *= 1.0 + w * 0.09 * fade;
		c *= 1.0 - 0.06 * smoothstep(0.6, 1.0, sin(UV.y * 160.0));
	}
	ALBEDO = c * mix(1.0, ao, ao_strength);
	ROUGHNESS = kind == 4 ? 0.35 : 0.85;
	SPECULAR = kind == 4 ? 0.5 : 0.15;
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = c * f * rim;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = kind == 0 ? 0.6 : 0.45;
	float d = clamp((ndl + w) / (1.0 + w), 0.0, 1.0);
	d = d * d * (3.0 - 2.0 * d);
	float sh = mix(0.25, 1.0, ATTENUATION);
	// warm subsurface-ish band at the terminator on skin
	float term = (kind == 0 ? 0.3 : 0.12) * d * (1.0 - clamp(ndl * 1.6, 0.0, 1.0));
	DIFFUSE_LIGHT += LIGHT_COLOR * sh * (d + vec3(1.0, 0.5, 0.35) * term) / PI;
	if (kind == 2 || kind == 4) {
		vec3 h = normalize(LIGHT + VIEW);
		float s = pow(clamp(dot(NORMAL, h), 0.0, 1.0), kind == 2 ? 24.0 : 60.0) * (kind == 2 ? 0.08 : 0.3);
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * s;
	}
}
