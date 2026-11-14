class_name MobileQuality
extends RefCounted
## Runtime quality ladder for phones (web + forced --mobile=1).
## Steps: render scale → reflection → shadow distance → particles → leaves near-fade.
## UI stays full-res via Viewport.scaling_3d_scale (3D only).

enum Tier { HIGH, MID, LOW, MIN }

var tier: int = Tier.HIGH
var mobile := false
var frozen := false  # probes/stills / URL ?q= override: don't auto-step
var scale_3d := 1.0
var shadow_dist := 50.0
var shadow_blur := 2.5
var particle_mul := 1.0
var water_cheap := 0.0
var leaf_near_fade := 0.9
var foliage_mul := 1.0
var omni_mul := 1.0
var shadows_on := true
var frame_ms_ema := 16.0
var slow_windows := 0
var fast_windows := 0
var window_t := 0.0
var window_n := 0
var window_ms_sum := 0.0
var window_ms: Array[float] = []

signal changed(tier: int)


func setup(is_web: bool, force_mobile: bool, vp: Viewport, sun: DirectionalLight3D, ios_default_low := false) -> void:
	mobile = is_web or force_mobile
	if not mobile:
		tier = Tier.HIGH
		_apply(vp, sun)
		return
	# iOS / WebKit starts LOW (scale 0.7, short single-cascade shadow); adaptive may step up.
	tier = Tier.LOW if ios_default_low else Tier.MID
	_apply(vp, sun)


func force_tier(name: String, vp: Viewport, sun: DirectionalLight3D) -> void:
	frozen = true
	match name.to_lower():
		"high":
			tier = Tier.HIGH
		"mid":
			tier = Tier.MID
		"low":
			tier = Tier.LOW
		"min":
			tier = Tier.MIN
		_:
			frozen = false
			return
	_apply(vp, sun)


func _apply(vp: Viewport, sun: DirectionalLight3D) -> void:
	foliage_mul = 1.0
	omni_mul = 1.0
	shadows_on = true
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
			shadow_dist = 12.0
			shadow_blur = 10.0
			particle_mul = 0.45
			water_cheap = 0.7
			leaf_near_fade = 1.7
		Tier.LOW:
			# Default iOS: scale 0.7, single 1024 shadow, short range.
			scale_3d = 0.70
			shadow_dist = 10.0
			shadow_blur = 10.0
			particle_mul = 0.3
			water_cheap = 0.9
			leaf_near_fade = 1.95
		Tier.MIN:
			# &q=min: isolate GPU vs logic. Extremely cheap 3D.
			scale_3d = 0.50
			shadow_dist = 6.0
			shadow_blur = 10.5
			particle_mul = 0.0
			water_cheap = 1.0
			leaf_near_fade = 3.0
			foliage_mul = 0.5
			omni_mul = 0.0
			shadows_on = false

	if mobile:
		vp.scaling_3d_scale = scale_3d
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.positional_shadow_atlas_size = 512
		vp.mesh_lod_threshold = 2.5
	else:
		vp.scaling_3d_scale = 1.0
		vp.mesh_lod_threshold = 1.0
	if sun:
		sun.shadow_enabled = shadows_on
		sun.directional_shadow_max_distance = shadow_dist
		sun.shadow_blur = shadow_blur
		if mobile:
			# LOW/MIN: orthogonal single cascade; HIGH/MID: 2-split.
			if tier <= Tier.MID:
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			else:
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.shadow_bias = 0.09
			sun.shadow_normal_bias = 2.8
			sun.directional_shadow_pancake_size = 1.2
			sun.light_angular_distance = maxf(sun.light_angular_distance, 5.0)
			if tier <= Tier.MID:
				sun.directional_shadow_split_1 = 0.22
				sun.directional_shadow_blend_splits = true
	changed.emit(tier)


## Adaptive: step up only if p95 < 14 ms for ~5 s; step down if p95 > 20 ms.
func watch_frame(delta: float, vp: Viewport, sun: DirectionalLight3D, refl_level: int, set_refl: Callable) -> void:
	if not mobile or frozen:
		return
	var ms := delta * 1000.0
	frame_ms_ema = lerpf(frame_ms_ema, ms, 0.08)
	window_t += delta
	window_n += 1
	window_ms.append(ms)
	if window_t < 5.0:
		return
	var sorted: Array = window_ms.duplicate()
	sorted.sort()
	var p95: float = sorted[int(clampf(float(sorted.size() - 1) * 0.95, 0.0, float(sorted.size() - 1)))]
	window_t = 0.0
	window_n = 0
	window_ms.clear()
	# Ignore first hitchy seconds (shader compile / warm).
	if Engine.get_frames_drawn() < 180:
		return
	if p95 > 20.0:
		slow_windows += 1
		fast_windows = 0
	elif p95 < 14.0:
		fast_windows += 1
		slow_windows = 0
	else:
		slow_windows = 0
		fast_windows = 0
	if slow_windows >= 1:
		slow_windows = 0
		if refl_level < 2:
			set_refl.call(refl_level + 1)
		elif tier < Tier.MIN:
			tier += 1
			_apply(vp, sun)
	elif fast_windows >= 1 and tier > Tier.LOW:
		# Step up from LOW only after sustained smooth p95; never auto above MID on phones.
		fast_windows = 0
		tier -= 1
		_apply(vp, sun)


func tier_name() -> String:
	return ["高", "中", "低", "最低"][clampi(tier, 0, 3)]
