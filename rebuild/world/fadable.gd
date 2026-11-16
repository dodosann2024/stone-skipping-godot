class_name Fadable
extends Node3D
## One prop, one material fade. Never discarded.

var alpha := 1.0
var target := 1.0
var keep_solid := false
var mesh: MeshInstance3D
var body: StaticBody3D


func setup(visual: MeshInstance3D, solid: StaticBody3D) -> void:
	mesh = visual
	body = solid
	if body != null:
		body.set_meta("fadable", self)
	add_child(visual)
	if solid != null:
		add_child(solid)


func set_target(next: float) -> void:
	if keep_solid:
		_show_solid()
		return
	target = clampf(next, Constants.OCCLUSION_MIN, 1.0)


func hold_solid(on: bool) -> void:
	keep_solid = on
	if on:
		_show_solid()


func _show_solid() -> void:
	target = 1.0
	alpha = 1.0
	_apply(1.0)


func tick(delta: float) -> void:
	if keep_solid:
		if alpha < 0.999:
			_show_solid()
		return
	if absf(alpha - target) < 0.004:
		return
	var tau := 0.20 if target < alpha else 0.35
	alpha = lerpf(alpha, target, 1.0 - exp(-delta / tau))
	_apply(alpha)


func _apply(a: float) -> void:
	# One mesh only. The card LOD is the other mesh; drawing both is the ghost double.
	if mesh != null and mesh.visible:
		_fade_one(mesh.material_override, a)
		return
	for c in get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).visible:
			_fade_one((c as MeshInstance3D).material_override, a)


func _fade_one(mat: Material, a: float) -> void:
	var std := mat as StandardMaterial3D
	if std == null:
		return
	var col := std.albedo_color
	col.a = 1.0 if a > 0.98 else a
	std.albedo_color = col
	if a > 0.98:
		std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	else:
		# Hash dither keeps the depth, so the slats do not glass over a second copy.
		std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
		std.alpha_hash_scale = 1.0
		std.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF
