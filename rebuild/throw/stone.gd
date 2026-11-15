class_name SkipStone
extends Node3D
## Kinematic skip. Shallow hits bounce; a steep or slow hit sinks.

signal settled(skips: int, dist: float)

var skips := 0
var velocity := Vector3.ZERO
var _from := Vector3.ZERO
var _alive := 0.0
var _sinking := false
var _splashes: Array[MeshInstance3D] = []
var _amb: Ambience
const WATER_Y := 0.04


func launch(from: Vector3, velocity_in: Vector3, amb: Ambience = null) -> void:
	_from = from
	_amb = amb
	velocity = velocity_in
	global_position = from
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.44, 0.42)
	mat.roughness = 0.55
	mi.material_override = mat
	add_child(mi)


func _process(delta: float) -> void:
	_alive += delta
	rotate_x(velocity.length() * delta * 3.0)
	var next := global_position + velocity * delta
	velocity.y -= 9.8 * delta
	if not _sinking and global_position.y > WATER_Y and next.y <= WATER_Y and velocity.y < 0.0:
		var flat := Vector2(velocity.x, velocity.z).length()
		var incidence := absf(velocity.y) / maxf(flat, 0.2)
		if incidence < 0.62 and flat > 2.4 and skips < 12:
			skips += 1
			next.y = WATER_Y + 0.01
			velocity.y = absf(velocity.y) * 0.38 + 0.55
			velocity.x *= 0.90
			velocity.z *= 0.90
			_splash(Vector3(next.x, WATER_Y, next.z))
		else:
			_sinking = true
			_splash(Vector3(next.x, WATER_Y, next.z))
	global_position = next
	var keep: Array[MeshInstance3D] = []
	for ring in _splashes:
		if not is_instance_valid(ring):
			continue
		ring.scale += Vector3.ONE * delta * 2.4
		var mat := ring.material_override as StandardMaterial3D
		if mat != null:
			var c := mat.albedo_color
			c.a = maxf(c.a - delta * 0.8, 0.0)
			mat.albedo_color = c
			if c.a <= 0.02:
				ring.queue_free()
				continue
		keep.append(ring)
	_splashes = keep
	if _alive > 7.0 or global_position.y < -1.2:
		var dist := Vector2(global_position.x - _from.x, global_position.z - _from.z).length()
		emit_signal("settled", skips, dist)
		queue_free()


func _splash(at: Vector3) -> void:
	if _amb != null:
		_amb.splash()
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.08
	mesh.outer_radius = 0.16
	mesh.rings = 8
	mesh.ring_segments = 6
	ring.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.98, 0.98, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	var parent := get_parent()
	if parent == null:
		return
	parent.add_child(ring)
	ring.global_position = at
	_splashes.append(ring)
