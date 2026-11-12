shader_type spatial;
render_mode cull_disabled; // avoid striped/dithered vest from flipped solidify normals
// v17 clothes: woven / knitted fabric instead of flat painted colour.
//   UV        body UV (about 1.4 m per unit), tiles the fabric texture
//   UV2.x     hem sway weight (0 where the garment is held by the body), UV2.y like COLOR.a, a second seam
//             with wrinkle > 0 (vest): UV2.x < 0 is minus the underarm wrinkle strength, UV2.y their phase
//   COLOR.r   baked AO, COLOR.g fold crest (> 0.5) / valley (< 0.5), COLOR.b metres to the garment edge / 30 mm, COLOR.a 0.5 + signed metres to a seam / 80 mm
// fabric.png: R jersey knit (tank), G linen plain weave (vest), B twill (shorts), A fibre noise.

uniform vec3 albedo : source_color = vec3(0.9);
uniform int fabric = 0;
uniform sampler2D fabric_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D pattern_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float pattern_mix = 0.0; // 1 = multiply albedo by pattern_tex (flower shorts)
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
uniform vec3 sway2 = vec3(0.0);        // a slower spring: the hem lags unevenly along its length
uniform vec3 sway_l = vec3(0.0);       // per shorts leg (legs = 1), trailing each thigh's swing
uniform vec3 sway_r = vec3(0.0);
uniform float legs = 0.0;
uniform float flutter = 0.0;
uniform float game_time = 0.0;
// shading-only relief (no geometry, so the swinging arms keep their clearance): drag lines fanning from
// the armpit and the armhole binding there, metres of virtual height
uniform float wrinkle = 0.0;
// raising an arm (boy.gd, 0..1 per side: x left, y right) also folds the cloth there for real, a few
// broad ridges along the same fan so the side's silhouette crumples; arms down it stays flat
uniform vec2 pit = vec2(0.0);
uniform float pit_depth = 0.0;         // ridge height in model units
#include "res://shaders/underwater.gdshaderinc"
#include "res://shaders/refl_clip.gdshaderinc"

varying float ao;
varying float fold;
varying float edge;
varying float seam;
varying float seam2;
varying vec3 lpos;
varying vec3 wp0;
varying float wmask;
varying float wph;
varying float pk;

void vertex() {
	ao = COLOR.r;
	fold = COLOR.g;
	edge = COLOR.b * 0.03;
	seam = (COLOR.a - 0.5) * 0.08;
	seam2 = wrinkle > 0.0 ? 0.03 : (0.5 - UV2.y) * 0.03;      // glTF stores V flipped
	wmask = wrinkle > 0.0 ? max(-UV2.x, 0.0) : 0.0;
	wph = 1.0 - UV2.y;
	lpos = VERTEX;
	pk = 0.0;
	if (wmask > 0.001) {
		pk = VERTEX.x > 0.0 ? pit.x : pit.y;
		// the side gathers a little as a whole, in narrow crests over broad valleys
		float g = 0.5 + 0.5 * cos(wph * PI);
		VERTEX += NORMAL * (0.3 + 0.7 * g * g) * pk * pit_depth * wmask * smoothstep(0.006, 0.022, edge);
	}
	float w = UV2.x;
	if (w > 0.0) {
		float ph = game_time * 6.0 + dot(VERTEX, vec3(23.0, 9.0, 17.0));
		// which spring a vertex follows varies along the hem (body UV, fixed on the cloth), ~20 cm apart
		float lag = 0.5 + 0.5 * sin(UV.x * 41.0 + UV.y * 27.0);
		vec3 s = mix(sway, sway2, lag) + legs * (VERTEX.x > 0.0 ? sway_l : sway_r);
		VERTEX += (s + vec3(sin(ph), 0.3 * sin(ph * 1.3), cos(ph * 0.8)) * flutter) * w;
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

	// underarm drag lines: soft crests, wider valleys, each line its own depth, fading towards the armhole
	// (where they meet) and into a flat average once they get finer than a few pixels
	float wr = 0.0;
	float bind = 0.0;
	if (wmask > 0.001) {
		float amp = 0.5 + 0.5 * hash(vec3(floor(wph + 0.25), 3.1, 7.7));
		float f = 0.5 + 0.5 * sin(wph * 6.2831853);
		float blur = smoothstep(0.12, 0.35, fwidth(wph));
		wr = mix(f * f, 0.375, blur) * amp * wmask * smoothstep(0.006, 0.022, edge) * (1.0 + 0.6 * pk);
		bind = wmask * (1.0 - smoothstep(0.0035, 0.0085, edge));
	}
	vec3 c = albedo;
	if (pattern_mix > 0.001) {
		vec3 pat = texture(pattern_tex, UV * 2.2).rgb;
		c = mix(c, c * pat, pattern_mix);
	}
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
	c *= 1.0 + (wr - 0.3 * wmask) * 0.4;
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
	float hb = (h - 0.5) * bump * near - groove * 0.0004 + stitch * 0.00015 + (wr + bind * 0.45) * wrinkle;
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
	if (!LIGHT_IS_DIRECTIONAL) {
		// torches / fire: ATTENUATION carries the distance falloff (no shadow floor), soft knee up close
		sh = ATTENUATION / (1.0 + ATTENUATION * max(LIGHT_COLOR.r, max(LIGHT_COLOR.g, LIGHT_COLOR.b)) * 0.45);
	}
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
