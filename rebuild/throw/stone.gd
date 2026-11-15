class_name SkipStone
extends RigidBody3D
## A short skip. Side-arm clips are not in the approved set yet.

var skips := 0
var _alive := 0.0


func launch(from: Vector3, velocity_in: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.38, 0.4)
	mi.material_override = mat
	add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.06
	cs.shape = shape
	add_child(cs)
	global_position = from
	linear_velocity = velocity_in
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_hit)


func _physics_process(delta: float) -> void:
	_alive += delta
	if _alive > 8.0 or global_position.y < -2.0:
		queue_free()


func _hit(body: Node) -> void:
	if body is StaticBody3D and global_position.y < 0.25 and linear_velocity.y < -0.2:
		skips += 1
		linear_velocity.y = absf(linear_velocity.y) * 0.55
		linear_velocity *= 0.86
