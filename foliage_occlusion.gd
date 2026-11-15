class_name FoliageOcclusion
extends RefCounted
## Opens foliage along the camera–boy segment and around the posed body.
## Fed the head and feet captured inside FootIK, i.e. the pose that was just
## uploaded to the renderer. Bushes and leaf cards on that volume dither, fade
## and bend so they cannot hide the boy.

var focus := Vector3(0, -100, 0)
var focus_lo := Vector3(0, -100, 0)
var focus_hi := Vector3(0, -100, 0)


func apply(island: Node, cam_pos: Vector3, head: Vector3, feet: Vector3, speed: float, exploring: bool) -> void:
	if island == null:
		return
	var hi := head if head.y > -50.0 else feet + Vector3(0, 1.2, 0)
	var lo := feet if feet.y > -50.0 else hi - Vector3(0, 1.1, 0)
	focus_hi = hi
	focus_lo = lo
	focus = lo.lerp(hi, 0.55)
	var move := clampf(speed / 1.15, 0.0, 1.0)
	# Cone along the view ray, plus a body capsule in the shader (~0.9 m).
	var radius := lerpf(1.35, 1.85, move) if exploring else 1.15
	var body_r := 0.92
	for mat_name in ["foliage_mat", "leaf_mat", "static_mat", "torch_mat"]:
		var mat: ShaderMaterial = island.get(mat_name)
		if mat == null:
			continue
		mat.set_shader_parameter("focus", focus)
		mat.set_shader_parameter("focus_lo", focus_lo)
		mat.set_shader_parameter("focus_hi", focus_hi)
		mat.set_shader_parameter("cut_radius", radius)
		mat.set_shader_parameter("body_radius", body_r)
	var leaf: ShaderMaterial = island.get("leaf_mat")
	if leaf != null:
		# Only drop cards that actually intersect the lens. The body capsule
		# opens the bush the boy is standing in; a multi-metre near-fade used
		# to delete the wall and still leave the leaves on his chest.
		leaf.set_shader_parameter("near_fade", 0.85)
