shader_type spatial;
render_mode cull_back;
// v17 clothes: woven / knitted fabric instead of flat painted colour.
//   UV        body UV (about 1.4 m per unit), tiles the fabric texture
//   UV2.x     hem sway weight (0 where the garment is held by the body), UV2.y like COLOR.a, a second seam
//   COLOR.r   baked AO, COLOR.g fold crest (> 0.5) / valley (< 0.5), COLOR.b metres to the garment edge / 30 mm, COLOR.a 0.5 + signed metres to a seam / 30 mm
// fabric.png: R jersey knit (tank), G linen plain weave (vest), B twill (shorts), A fibre noise.

uniform vec3 albedo : source_color = vec3(0.9);
uniform int fabric = 0;
uniform sampler2D fabric_tex : filter_linear_mipmap, repeat_enable;
uniform float weave = 35.0;            // texture tiles per UV unit (4 cm)
uniform float bump = 0.00018;          // weave relief, metres
uniform vec3 thread : source_color = vec3(0.9);
uniform vec3 binding : source_color = vec3(0.9);
uniform float binding_w = 0.0;         // metres of contrasting binding along the edge
uniform float hem_stitch = 0.006;      // metres from the edge
uniform float fade = 0.0;              // sun bleaching on up-facing cloth
uniform float wear = 0.3;              // lighter, fuzzier edges
uniform float sheen = 0.3;
uniform float translucency = 0.0;      // thin cotton shows skin and lets backlight through
uniform vec3 skin : source_color = vec3(0.90, 0.66, 0.52);
uniform float ao_strength = 0.55;
uniform vec3 sway = vec3(0.0);
uniform float flutter = 0.0;
uniform float game_time = 0.0;
#include "res://shaders/underwater.gdshaderinc"
#include "res://shaders/refl_clip.gdshaderinc"

varying float ao;
varying float fold;
varying float edge;
varying float seam;
varying float seam2;
varying vec3 lpos;
varying vec3 wp0;

void vertex() {
	ao = COLOR.r;
	fold = COLOR.g;
	edge = COLOR.b * 0.03;
	seam = (COLOR.a - 0.5) * 0.03;
	seam2 = (0.5 - UV2.y) * 0.03;      // glTF stores V flipped
	lpos = VERTEX;
	float w = UV2.x;
	if (w > 0.0) {
		float ph = game_time * 6.0 + dot(VERTEX, vec3(23.0, 9.0, 17.0));
		VERTEX += (sway + vec3(sin(ph), 0.3 * sin(ph * 1.3), cos(ph * 0.8)) * flutter) * w;
	}
	wp0 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (wp0.y < 0.12) {
		VERTEX += inverse(mat3(MODEL_MATRIX)) * uw_refract(wp0);
	}
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float line(float d, float at, float half_w) {
	float aa = max(fwidth(d), 1e-5);
	return 1.0 - smoothstep(half_w - aa, half_w + aa, abs(d - at));
}

void fragment() {
	if (!IN_SHADOW_PASS && refl_pass(CAMERA_POSITION_WORLD) && (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y < 0.0) {
		discard;
	}
	vec2 uv = UV * weave;
	vec4 t = texture(fabric_tex, uv);
	float h = fabric == 0 ? t.r : (fabric == 1 ? t.g : t.b);
	// texels per pixel (a thread is ~8 texels): once threads get under ~2 px the weave averages out
	// through the mipmaps and the bump fades so it never aliases into moire
	float px = length(fwidth(uv)) * 256.0;
	float near = 1.0 - smoothstep(2.5, 6.0, px);

	// seams: a soft groove with a row of stitches beside it; hems: a stitched line in from the edge
	float groove = max(line(seam, 0.0, 0.0006), line(seam2, 0.0, 0.0006));
	float sm = min(abs(seam), abs(seam2));
	float dash = smoothstep(0.35, 0.5, fract((UV.x * 0.8 + UV.y) * 700.0)) * (1.0 - smoothstep(0.75, 0.9, fract((UV.x * 0.8 + UV.y) * 700.0)));
	float stitch = max(line(sm, 0.003, 0.00035), line(edge, hem_stitch, 0.00035)) * mix(1.0, dash, near);
	stitch *= 1.0 - smoothstep(1.0, 3.0, length(fwidth(vec2(edge, sm))) * 1500.0);

	vec3 c = albedo;
	c *= 1.0 + (vnoise(lpos * 9.0) - 0.5) * 0.10 + (vnoise(lpos * 31.0) - 0.5) * 0.05;
	c *= mix(1.0, mix(0.90, 1.06, h) * mix(0.97, 1.03, t.a), 0.5 + 0.5 * near);
	float up = smoothstep(0.1, 0.9, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y);
	c = mix(c, c * 0.82 + vec3(0.15), fade * up);
	float rim_edge = 1.0 - smoothstep(0.0, 0.007, edge);
	if (binding_w > 0.0) {
		c = mix(c, binding * (1.0 + (vnoise(lpos * 40.0) - 0.5) * 0.08), 1.0 - smoothstep(binding_w - 0.0006, binding_w + 0.0006, edge));
	}
	c = mix(c, c * 0.92 + vec3(0.05), rim_edge * wear);
	// soft shadow in the folds' valleys, a little light on their crests
	c *= 1.0 + clamp(fold - 0.5, -0.5, 0.5) * 0.38;
	c *= 1.0 - 0.28 * groove;
	c = mix(c, thread, stitch * 0.75);
	float thin = translucency * smoothstep(0.004, 0.012, edge);
	c = mix(c, skin * 0.9, thin);

	vec3 a = c * mix(1.0, ao, ao_strength);
	if (wp0.y < 0.12) {
		a = uw_tint(a, wp0);
	}
	ALBEDO = a;
	ROUGHNESS = 0.95;
	SPECULAR = 0.08;

	// weave relief + seam groove + raised stitches, as a height bumped through screen derivatives
	float hb = (h - 0.5) * bump * near - groove * 0.0004 + stitch * 0.00015;
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec3 r1 = cross(dpy, NORMAL);
	vec3 r2 = cross(NORMAL, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dFdx(hb) * r1 + dFdy(hb) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float d = clamp((ndl + 0.45) / 1.45, 0.0, 1.0);
	d = d * d * (3.0 - 2.0 * d);
	float sh = mix(0.25, 1.0, ATTENUATION);
	float term = 0.12 * d * (1.0 - clamp(ndl * 1.6, 0.0, 1.0));
	DIFFUSE_LIGHT += LIGHT_COLOR * sh * (d + vec3(1.0, 0.5, 0.35) * term) / PI;
	// fuzz: fibres standing off the surface catch light at grazing view angles
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * sh * pow(1.0 - nv, 4.0) * smoothstep(-0.3, 0.5, ndl) * sheen / PI;
	// light through thin cotton from behind
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * translucency * pow(clamp(dot(-LIGHT, VIEW), 0.0, 1.0), 3.0) * 0.6 / PI;
	vec3 hv = normalize(LIGHT + VIEW);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * pow(clamp(dot(NORMAL, hv), 0.0, 1.0), 6.0) * 0.015;
}
