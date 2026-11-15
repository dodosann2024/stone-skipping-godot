class_name Props
extends Node3D
## Each blocker is its own mesh. Nothing here is clipped or discarded.

var items: Array[Fadable] = []


func _ready() -> void:
	var ends := IslandData.dock_ends()
	var shore_z: float = ends.x
	_palm(Vector3(-2.2, 0.0, shore_z + 1.6), 4.2)
	_palm(Vector3(-3.4, 0.0, shore_z + 3.8), 3.6)
	_palm(Vector3(2.8, 0.0, shore_z + 0.8), 4.6)
	_palm(Vector3(5.5, 0.0, shore_z + 5.5), 3.8)
	_palm(Vector3(-6.0, 0.0, shore_z + 8.0), 5.0)
	_hut(Vector3(4.4, 0.0, shore_z + 2.8))
	_bush(Vector3(1.4, 0.0, shore_z + 2.2))
	_bush(Vector3(3.2, 0.0, shore_z + 4.6))
	_barrel(Vector3(-1.1, 0.0, shore_z + 1.5))
	_sign(Vector3(-1.6, 0.0, shore_z + 0.8))
	_lighthouse(Vector3(8.5, 0.0, 6.5))
	_bench(Vector3(3.2, 0.0, 2.2))
	_log(Vector3(-4.0, 0.0, shore_z + 7.5))
	_campfire(Vector3(-2.5, 0.0, shore_z + 8.5))
	_hammock(Vector3(6.2, 0.0, shore_z + 4.2))
	_towel(Vector3(-5.0, 0.0, shore_z + 4.0))
	_lounger(Vector3(-4.2, 0.0, shore_z + 5.2))


func _palm(at: Vector3, height: float) -> void:
	at.y = IslandData.height_at(at.x, at.z)
	var root := Fadable.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 8
	for i in rings:
		var t0 := float(i) / float(rings)
		var t1 := float(i + 1) / float(rings)
		var y := height * (t0 + t1) * 0.5
		var r := lerpf(0.22, 0.11, t0)
		var col := Color(0.55, 0.46, 0.36) if i % 2 == 0 else Color(0.42, 0.34, 0.26)
		_cylinder(st, Vector3(0, y, 0), r, height / float(rings) * 1.05, col, 7)
	var crown := Vector3(0, height, 0)
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var dir := Vector3(cos(ang), 0.15, sin(ang))
		_frond(st, crown, dir, Color(0.16, 0.48, 0.18) if i % 2 == 0 else Color(0.28, 0.62, 0.22))
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
	shape.height = maxf(height, 1.2)
	cap.shape = shape
	cap.position = Vector3(0, height * 0.5, 0)
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
	var floor_y := 1.15
	var wood := Color(0.62, 0.46, 0.28)
	var post := Color(0.40, 0.28, 0.16)
	for px in [-1.1, 1.1]:
		for pz in [-0.9, 0.9]:
			_cylinder(st, Vector3(px, floor_y * 0.5, pz), 0.07, floor_y, post, 6)
	_box(st, Vector3(0, floor_y, 0), Vector3(2.6, 0.08, 2.2), wood)
	_box(st, Vector3(0, floor_y + 0.9, -1.05), Vector3(2.5, 1.6, 0.08), wood)
	_box(st, Vector3(-1.25, floor_y + 0.9, 0), Vector3(0.08, 1.6, 2.0), wood)
	_box(st, Vector3(1.25, floor_y + 0.9, 0), Vector3(0.08, 1.6, 2.0), wood)
	var straw := Color(0.86, 0.72, 0.38)
	_box(st, Vector3(-0.7, floor_y + 2.15, 0), Vector3(1.5, 0.12, 2.5), straw)
	_box(st, Vector3(0.7, floor_y + 2.15, 0), Vector3(1.5, 0.12, 2.5), straw)
	_box(st, Vector3(0, floor_y + 2.45, 0), Vector3(0.35, 0.16, 2.6), Color(0.62, 0.48, 0.26))
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


func _lighthouse(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z)
	var root := _solid_visual(at, "Lighthouse", Constants.LAYER_BLOCK, Vector3(0, 2.2, 0), Vector3(1.4, 4.4, 1.4))
	var st: SurfaceTool = root.get_meta("st")
	_cylinder(st, Vector3(0, 1.6, 0), 0.55, 3.2, Color(0.9, 0.9, 0.86), 10)
	_cylinder(st, Vector3(0, 2.4, 0), 0.58, 0.35, Color(0.75, 0.22, 0.18), 10)
	_cylinder(st, Vector3(0, 3.5, 0), 0.42, 0.7, Color(0.85, 0.92, 0.95), 8)
	_cylinder(st, Vector3(0, 3.95, 0), 0.7, 0.12, Color(0.35, 0.32, 0.3), 8)
	_finish(root)


func _log(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z)
	var root := _solid_visual(at, "Log", Constants.LAYER_PROP, Vector3(0, 0.16, 0), Vector3(1.4, 0.4, 0.4))
	var st: SurfaceTool = root.get_meta("st")
	_cylinder(st, Vector3(0, 0.16, 0), 0.16, 1.3, Color(0.42, 0.28, 0.16), 8)
	_finish(root)


func _campfire(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z)
	var root := _solid_visual(at, "Campfire", Constants.LAYER_PROP, Vector3(0, 0.2, 0), Vector3(0.9, 0.5, 0.9))
	var st: SurfaceTool = root.get_meta("st")
	for i in 6:
		var a := TAU * float(i) / 6.0
		_sphere(st, Vector3(cos(a) * 0.38, 0.1, sin(a) * 0.38), 0.12, Color(0.45, 0.44, 0.42))
	_box(st, Vector3(0.1, 0.18, 0), Vector3(0.5, 0.08, 0.08), Color(0.28, 0.16, 0.08))
	_box(st, Vector3(-0.05, 0.2, 0.05), Vector3(0.08, 0.08, 0.45), Color(0.32, 0.18, 0.1))
	var flame := Color(1.0, 0.55, 0.12)
	_box(st, Vector3(0, 0.45, 0), Vector3(0.12, 0.35, 0.12), flame)
	_finish(root)


func _hammock(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z)
	var root := _solid_visual(at, "Hammock", Constants.LAYER_PROP, Vector3(0, 0.6, 0), Vector3(2.2, 1.4, 0.6))
	var st: SurfaceTool = root.get_meta("st")
	var post := Color(0.4, 0.28, 0.16)
	_cylinder(st, Vector3(-0.9, 0.7, 0), 0.06, 1.4, post, 6)
	_cylinder(st, Vector3(0.9, 0.7, 0), 0.06, 1.4, post, 6)
	var cloth := Color(0.85, 0.45, 0.38)
	_box(st, Vector3(0, 0.72, 0), Vector3(1.6, 0.05, 0.45), cloth)
	_finish(root)


func _towel(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z) + 0.02
	var root := _solid_visual(at, "Towel", Constants.LAYER_PROP, Vector3(0, 0.02, 0), Vector3(0.7, 0.05, 1.4))
	var st: SurfaceTool = root.get_meta("st")
	_box(st, Vector3(0, 0.02, 0), Vector3(0.7, 0.02, 1.4), Color(0.85, 0.35, 0.38))
	_finish(root)


func _lounger(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z)
	var root := _solid_visual(at, "Lounger", Constants.LAYER_PROP, Vector3(0, 0.25, 0), Vector3(0.7, 0.6, 1.6))
	var st: SurfaceTool = root.get_meta("st")
	var cloth := Color(0.25, 0.45, 0.72)
	_box(st, Vector3(0, 0.28, 0.15), Vector3(0.62, 0.05, 1.1), cloth)
	_box(st, Vector3(0, 0.5, -0.55), Vector3(0.62, 0.4, 0.06), cloth)
	_finish(root)


func _solid_visual(at: Vector3, node_name: String, layer: int, shape_pos: Vector3, shape_size: Vector3) -> Fadable:
	var root := Fadable.new()
	root.name = node_name
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	root.set_meta("st", st)
	root.set_meta("layer", layer)
	root.set_meta("shape_pos", shape_pos)
	root.set_meta("shape_size", shape_size)
	root.position = at
	return root


func _finish(root: Fadable) -> void:
	var st: SurfaceTool = root.get_meta("st")
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color(1, 1, 1))
	var body := StaticBody3D.new()
	body.collision_layer = int(root.get_meta("layer"))
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = root.get_meta("shape_size")
	cs.shape = box
	cs.position = root.get_meta("shape_pos")
	body.add_child(cs)
	root.setup(mi, body)
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
