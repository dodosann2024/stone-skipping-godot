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
	mesh.radius = 0.028
	mesh.height = 0.056
	mesh.radial_segments = 12
	mesh.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = Vector3(1.1, 0.36, 0.9)
	mi.material_override = _pebble_mat()
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
			next.y = WATER_Y + 0.02
			velocity.y = absf(velocity.y) * 0.38 + 0.45
			velocity.x *= 0.90
			velocity.z *= 0.90
			_skip_fx(Vector3(next.x, WATER_Y, next.z), false)
		else:
			_sinking = true
			_skip_fx(Vector3(next.x, WATER_Y, next.z), true)
	global_position = next
	var keep: Array[MeshInstance3D] = []
	for drop in _splashes:
		if not is_instance_valid(drop):
			continue
		var life := float(drop.get_meta("life", 0.4)) - delta
		drop.set_meta("life", life)
		var vel: Vector3 = drop.get_meta("vel", Vector3.ZERO)
		vel.y -= 9.8 * delta
		drop.set_meta("vel", vel)
		drop.global_position += vel * delta
		if life <= 0.0 or drop.global_position.y < WATER_Y - 0.02:
			drop.queue_free()
			continue
		keep.append(drop)
	_splashes = keep
	if _alive > 7.0 or global_position.y < -1.2:
		var dist := Vector2(global_position.x - _from.x, global_position.z - _from.z).length()
		emit_signal("settled", skips, dist)
		queue_free()


func _pebble_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.51, 0.48)
	mat.roughness = 0.38
	mat.metallic = 0.06
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.45
	mat.clearcoat_roughness = 0.22
	return mat


func _crumb(delta: float) -> void:
	_next_crumb -= delta
	if not _sinking and _alive < 2.0 and _next_crumb <= 0.0:
		_next_crumb = 0.03
		var bit := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.008
		mesh.height = 0.016
		mesh.radial_segments = 6
		mesh.rings = 3
		bit.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.75, 0.76, 0.74, 0.45)
		mat.roughness = 0.4
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


func _skip_fx(at: Vector3, plunk: bool) -> void:
	if _amb != null:
		_amb.splash()
	var host := get_parent()
	if host != null and host.has_method("add_ripple"):
		host.add_ripple(at)
		if plunk:
			host.add_ripple(at + Vector3(0.05, 0, 0.04))
	var n := 14 if plunk else 8
	var parent := host if host != null else self
	for i in n:
		var drop := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.012 if plunk else 0.009
		mesh.height = mesh.radius * 2.0
		mesh.radial_segments = 6
		mesh.rings = 3
		drop.mesh = mesh
		var dmat := _pebble_mat()
		dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dmat.albedo_color.a = 0.85
		drop.material_override = dmat
		drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drop.set_meta("life", 0.55 if plunk else 0.4)
		drop.set_meta("vel", Vector3(cos(float(i) * 0.9) * 0.8, 1.4 + float(i % 3) * 0.25, sin(float(i) * 0.9) * 0.8))
		parent.add_child(drop)
		drop.global_position = at + Vector3(0, 0.05, 0)
		_splashes.append(drop)
