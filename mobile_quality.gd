class_name MobileQuality
extends RefCounted
## Runtime quality ladder for phones (web + forced --mobile=1).
## Steps: render scale → reflection → shadow distance → particles → leaves near-fade.
## UI stays full-res via Viewport.scaling_3d_scale (3D only).

enum Tier { HIGH, MID, LOW, MIN }

var tier: int = Tier.HIGH
var mobile := false
var frozen := false  # probes/stills: don't auto-step on slow desktop GL
var scale_3d := 1.0
var shadow_dist := 50.0
var shadow_blur := 2.5
var particle_mul := 1.0
var water_cheap := 0.0
var leaf_near_fade := 0.9
var frame_ms_ema := 16.0
var slow_windows := 0
var fast_windows := 0
var window_t := 0.0
var window_n := 0
var window_ms_sum := 0.0

signal changed(tier: int)


func setup(is_web: bool, force_mobile: bool, vp: Viewport, sun: DirectionalLight3D) -> void:
	mobile = is_web or force_mobile
	if not mobile:
		tier = Tier.HIGH
		_apply(vp, sun)
		return
	# Prefer geometry/light/texture cuts; keep scale ≥0.75 until adaptive steps down.
	tier = Tier.MID
	_apply(vp, sun)


func _apply(vp: Viewport, sun: DirectionalLight3D) -> void:
	match tier:
		Tier.HIGH:
			scale_3d = 1.0
			shadow_dist = 55.0
			shadow_blur = 2.8
			particle_mul = 1.0
			water_cheap = 0.0
			leaf_near_fade = 0.85
		Tier.MID:
			scale_3d = 0.78
			shadow_dist = 22.0
			shadow_blur = 7.0
			particle_mul = 0.45
			water_cheap = 0.7
			leaf_near_fade = 1.7
		Tier.LOW:
			scale_3d = 0.70
			shadow_dist = 18.0
			shadow_blur = 7.2
			particle_mul = 0.3
			water_cheap = 0.9
			leaf_near_fade = 1.95
		Tier.MIN:
			scale_3d = 0.58
			shadow_dist = 14.0
			shadow_blur = 7.5
			particle_mul = 0.18
			water_cheap = 1.0
			leaf_near_fade = 2.2

	if mobile:
		vp.scaling_3d_scale = scale_3d
		# Compatibility has no FSR1 — stay on bilinear; sharpen via slightly higher scale.
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		# Keep positional atlas small — only campfire may cast omni shadows.
		vp.positional_shadow_atlas_size = 1024 if tier <= Tier.MID else 512
		# Prefer lower mesh LODs on phones when available.
		vp.mesh_lod_threshold = 2.5
	else:
		vp.scaling_3d_scale = 1.0
		vp.mesh_lod_threshold = 1.0
	if sun:
		sun.directional_shadow_max_distance = shadow_dist
		sun.shadow_blur = shadow_blur
		if mobile:
			# One orthogonal map (half the shadow primitives of 2-splits) + high blur ≈ soft PCF.
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.shadow_bias = 0.04
			sun.shadow_normal_bias = 1.5
			sun.directional_shadow_pancake_size = 3.0
			sun.light_angular_distance = maxf(sun.light_angular_distance, 2.8)
	changed.emit(tier)


func watch_frame(delta: float, vp: Viewport, sun: DirectionalLight3D, refl_level: int, set_refl: Callable) -> void:
	if not mobile or frozen:
		return
	var ms := delta * 1000.0
	# Ignore the first hitchy seconds (shader compile / warm).
	frame_ms_ema = lerpf(frame_ms_ema, ms, 0.08)
	window_t += delta
	window_n += 1
	window_ms_sum += ms
	if window_t < 1.25:
		return
	var avg := window_ms_sum / float(maxi(window_n, 1))
	window_t = 0.0
	window_n = 0
	window_ms_sum = 0.0
	# Target ≤20 ms (50 fps). Two slow windows → step down; sustained fast → step up once.
	if avg > 22.0:
		slow_windows += 1
		fast_windows = 0
	elif avg < 15.5:
		fast_windows += 1
		slow_windows = 0
	else:
		slow_windows = 0
		fast_windows = 0
	if slow_windows >= 2:
		slow_windows = 0
		if refl_level < 2:
			set_refl.call(refl_level + 1)
		elif tier < Tier.MIN:
			tier += 1
			_apply(vp, sun)
	elif fast_windows >= 6 and tier > Tier.MID:
		fast_windows = 0
		tier -= 1
		_apply(vp, sun)


func tier_name() -> String:
	return ["高", "中", "低", "最低"][clampi(tier, 0, 3)]
