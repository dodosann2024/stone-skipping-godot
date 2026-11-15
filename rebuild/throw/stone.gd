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
var _crumbs: Array[MeshInstance3D] = []
var _next_crumb := 0.0
var _amb: Ambience
const WATER_Y := 0.04


func launch(from: Vector3, velocity_in: Vector3, amb: Ambience = null) -> void:
	_from = from
	_amb = amb
	velocity = velocity_in
	global_position = from
	var mesh := SphereMesh.new()
	mesh.radius = 0.072
	mesh.height = 0.144
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = Vector3(1.2, 0.34, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.93, 0.94, 0.95)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _process(delta: float) -> void:
	_alive += delta
	_crumb(delta)
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


func _crumb(delta: float) -> void:
	_next_crumb -= delta
	if not _sinking and _alive < 1.6 and _next_crumb <= 0.0:
		_next_crumb = 0.04
		var bit := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.035
		mesh.height = 0.07
		bit.mesh = mesh
		bit.scale = Vector3(1.3, 0.28, 1.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.95, 0.96, 0.97, 0.7)
		bit.material_override = mat
		bit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bit.top_level = true
		add_child(bit)
		bit.global_position = global_position
		_crumbs.append(bit)
	var keep: Array[MeshInstance3D] = []
	for bit in _crumbs:
		if not is_instance_valid(bit):
			continue
		var mat := bit.material_override as StandardMaterial3D
		if mat != null:
			var c := mat.albedo_color
			c.a = maxf(c.a - delta * 1.8, 0.0)
			mat.albedo_color = c
			bit.scale = bit.scale * (1.0 - delta * 0.6)
			if c.a <= 0.02:
				bit.queue_free()
				continue
		keep.append(bit)
	_crumbs = keep


func _splash(at: Vector3) -> void:
	if _amb != null:
		_amb.splash()
	_ring(at, 0.06, 0.14)
	_ring(at, 0.12, 0.26)
	var disc := MeshInstance3D.new()
	var dmesh := CylinderMesh.new()
	dmesh.top_radius = 0.16
	dmesh.bottom_radius = 0.16
	dmesh.height = 0.01
	disc.mesh = dmesh
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_color = Color(0.92, 0.97, 1.0, 0.55)
	disc.material_override = dmat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(disc)
	disc.global_position = at + Vector3(0, 0.02, 0)
	_splashes.append(disc)


func _ring(at: Vector3, inner: float, outer: float) -> void:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
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
