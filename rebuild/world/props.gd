class_name Props
extends Node3D
## Each blocker is its own mesh. Nothing here is clipped or discarded.

var items: Array[Fadable] = []


func _ready() -> void:
	var ends := IslandData.dock_ends()
	var shore_z: float = ends.x
	_palm(Vector3(-2.4, 0.0, shore_z + 2.4))
	_palm(Vector3(3.6, 0.0, shore_z + 1.2))
	_palm(Vector3(-4.2, 0.0, shore_z + 6.0))
	_hut(Vector3(4.8, 0.0, shore_z + 3.4))
	_bush(Vector3(2.6, 0.0, shore_z + 3.6))
	_barrel(Vector3(-1.1, 0.0, shore_z + 1.5))
	_sign(Vector3(-1.8, 0.0, shore_z + 0.6))
	_bench(Vector3(8.0, 0.0, 2.0))


func _palm(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z)
	var root := Fadable.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cylinder(st, Vector3(0, 1.3, 0), 0.18, 2.6, Color(0.45, 0.30, 0.16), 8)
	for i in 6:
		var ang := TAU * float(i) / 6.0
		var dir := Vector3(cos(ang), 0.35, sin(ang)).normalized()
		_frond(st, Vector3(0, 2.55, 0), dir, Color(0.28, 0.55, 0.28))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color(1, 1, 1))
	var body := StaticBody3D.new()
	body.collision_layer = Constants.LAYER_BLOCK
	body.collision_mask = 0
	var cap := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.22
	shape.height = 2.6
	cap.shape = shape
	cap.position = Vector3(0, 1.3, 0)
	body.add_child(cap)
	root.setup(mi, body)
	root.position = at
	add_child(root)
	items.append(root)


func _hut(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z)
	var root := Fadable.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(0, 1.55, 0), Vector3(2.4, 1.5, 2.2), Color(0.62, 0.48, 0.32))
	_box(st, Vector3(0, 2.55, 0), Vector3(2.8, 0.28, 2.6), Color(0.72, 0.55, 0.32))
	for p in [Vector3(-0.9, 0.45, -0.9), Vector3(0.9, 0.45, -0.9), Vector3(-0.9, 0.45, 0.9), Vector3(0.9, 0.45, 0.9)]:
		_cylinder(st, p, 0.08, 0.9, Color(0.40, 0.28, 0.16), 6)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color(1, 1, 1))
	var body := StaticBody3D.new()
	body.collision_layer = Constants.LAYER_BLOCK
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 2.4, 2.2)
	cs.shape = box
	cs.position = Vector3(0, 1.3, 0)
	body.add_child(cs)
	root.setup(mi, body)
	root.position = at
	add_child(root)
	items.append(root)


func _bush(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z)
	var root := Fadable.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sphere(st, Vector3(0, 0.45, 0), 0.55, Color(0.30, 0.58, 0.30))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color(1, 1, 1))
	var body := StaticBody3D.new()
	body.collision_layer = Constants.LAYER_PROP
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.5
	cs.shape = sph
	cs.position = Vector3(0, 0.45, 0)
	body.add_child(cs)
	root.setup(mi, body)
	root.position = at
	add_child(root)
	items.append(root)


func _barrel(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z)
	var root := Fadable.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cylinder(st, Vector3(0, 0.4, 0), 0.28, 0.8, Color(0.48, 0.32, 0.18), 8)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color(1, 1, 1))
	var body := StaticBody3D.new()
	body.collision_layer = Constants.LAYER_PROP
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 0.8
	cs.shape = cap
	cs.position = Vector3(0, 0.4, 0)
	body.add_child(cs)
	root.setup(mi, body)
	root.position = at
	add_child(root)
	items.append(root)


func _sign(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z)
	var root := Fadable.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cylinder(st, Vector3(0, 0.7, 0), 0.06, 1.4, Color(0.42, 0.30, 0.18), 6)
	_box(st, Vector3(0, 1.45, 0), Vector3(0.7, 0.4, 0.06), Color(0.82, 0.78, 0.62))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color(1, 1, 1))
	var body := StaticBody3D.new()
	body.collision_layer = Constants.LAYER_PROP
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 1.6, 0.2)
	cs.shape = box
	cs.position = Vector3(0, 0.8, 0)
	body.add_child(cs)
	root.setup(mi, body)
	root.position = at
	add_child(root)
	items.append(root)


func _bench(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z)
	var root := Fadable.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(0, 0.28, 0), Vector3(1.4, 0.08, 0.42), Color(0.50, 0.36, 0.22))
	_box(st, Vector3(0, 0.55, -0.16), Vector3(1.4, 0.4, 0.08), Color(0.50, 0.36, 0.22))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color(1, 1, 1))
	var body := StaticBody3D.new()
	body.collision_layer = Constants.LAYER_PROP
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 0.7, 0.5)
	cs.shape = box
	cs.position = Vector3(0, 0.35, 0)
	body.add_child(cs)
	root.setup(mi, body)
	root.position = at
	root.name = "Bench"
	add_child(root)
	items.append(root)


func _mat(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = c
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat


func _box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var corners: Array[Vector3] = [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(-h.x, h.y, -h.z), center + Vector3(h.x, h.y, -h.z),
		center + Vector3(-h.x, -h.y, h.z), center + Vector3(h.x, -h.y, h.z),
		center + Vector3(-h.x, h.y, h.z), center + Vector3(h.x, h.y, h.z),
	]
	_face(st, corners[2], corners[3], corners[6], corners[7], col)
	_face(st, corners[0], corners[4], corners[1], corners[5], col)
	_face(st, corners[0], corners[2], corners[4], corners[6], col)
	_face(st, corners[1], corners[5], corners[3], corners[7], col)
	_face(st, corners[4], corners[6], corners[5], corners[7], col)
	_face(st, corners[0], corners[1], corners[2], corners[3], col)


func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a)
	st.set_color(col)
	st.add_vertex(b)
	st.set_color(col)
	st.add_vertex(c)
	st.set_color(col)
	st.add_vertex(b)
	st.set_color(col)
	st.add_vertex(d)
	st.set_color(col)
	st.add_vertex(c)


func _cylinder(st: SurfaceTool, center: Vector3, radius: float, height: float, col: Color, sides: int) -> void:
	var y0 := center.y - height * 0.5
	var y1 := center.y + height * 0.5
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var p0 := center + Vector3(cos(a0) * radius, y0 - center.y, sin(a0) * radius)
		var p1 := center + Vector3(cos(a1) * radius, y0 - center.y, sin(a1) * radius)
		var q0 := Vector3(p0.x, y1, p0.z)
		var q1 := Vector3(p1.x, y1, p1.z)
		_face(st, p0, p1, q0, q1, col)


func _sphere(st: SurfaceTool, center: Vector3, radius: float, col: Color) -> void:
	var rings := 5
	var seg := 8
	for r in rings:
		var v0 := PI * float(r) / float(rings)
		var v1 := PI * float(r + 1) / float(rings)
		for s in seg:
			var u0 := TAU * float(s) / float(seg)
			var u1 := TAU * float(s + 1) / float(seg)
			var a := center + _sph(radius, u0, v0)
			var b := center + _sph(radius, u1, v0)
			var c := center + _sph(radius, u0, v1)
			var d := center + _sph(radius, u1, v1)
			_face(st, a, b, c, d, col)


func _sph(radius: float, u: float, v: float) -> Vector3:
	return Vector3(cos(u) * sin(v), cos(v), sin(u) * sin(v)) * radius


func _frond(st: SurfaceTool, origin: Vector3, dir: Vector3, col: Color) -> void:
	var tip := origin + dir * 1.6
	var side := dir.cross(Vector3.UP).normalized() * 0.18
	st.set_color(col)
	st.add_vertex(origin)
	st.set_color(col)
	st.add_vertex(tip + side)
	st.set_color(col)
	st.add_vertex(tip - side)
