class_name Fadable
extends Node3D
## One prop, one material fade. Never discarded.

var alpha := 1.0
var target := 1.0
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
	target = clampf(next, Constants.OCCLUSION_MIN, 1.0)


func tick(delta: float) -> void:
	var tau := 0.20 if target < alpha else 0.35
	alpha = lerpf(alpha, target, 1.0 - exp(-delta / tau))
	if mesh == null or mesh.material_override == null:
		return
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	var c := mat.albedo_color
	c.a = alpha
	mat.albedo_color = c
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 0.99 else BaseMaterial3D.TRANSPARENCY_DISABLED
