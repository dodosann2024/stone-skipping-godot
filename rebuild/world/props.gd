class_name Props
extends Node3D
## Each blocker is its own mesh. Nothing here is clipped or discarded.

var items: Array[Fadable] = []


func _ready() -> void:
	var ends := IslandData.dock_ends()
	var shore_z: float = ends.x
	_palm(Vector3(-1.7, 0.0, shore_z + 0.7), 5.4, 0.12)
	_palm(Vector3(-2.5, 0.0, shore_z + 2.4), 4.3, -0.08)
	_palm(Vector3(-3.3, 0.0, shore_z + 4.2), 3.7, 0.16)
	_palm(Vector3(-4.6, 0.0, shore_z + 6.4), 4.8, -0.1)
	_palm(Vector3(2.6, 0.0, shore_z + 0.5), 4.1, 0.06)
	_palm(Vector3(6.2, 0.0, shore_z + 5.2), 5.1, -0.14)
	_palm(Vector3(-6.4, 0.0, shore_z + 9.0), 3.5, 0.18)
	_hut(Vector3(4.2, 0.0, shore_z + 2.6))
	_bush(Vector3(1.4, 0.0, shore_z + 2.2))
	_bush(Vector3(3.2, 0.0, shore_z + 4.6))
	_barrel(Vector3(-1.15, 0.0, shore_z + 1.2))
	_barrel(Vector3(1.55, 0.0, ends.y + 2.4))
	_barrel(Vector3(-1.7, 0.0, ends.y + 2.15))
	_coil(Vector3(1.15, 0.0, ends.y + 1.7))
	_sign(Vector3(-1.6, 0.0, shore_z + 0.8))
	_lighthouse(Vector3(8.5, 0.0, 6.5))
	_bench(Vector3(3.2, 0.0, 2.2))
	_log(Vector3(-4.0, 0.0, shore_z + 7.5))
	var fire_at := Vector3(-2.5, 0.0, shore_z + 8.5)
	_campfire(fire_at)
	for i in 3:
		var ang := TAU * float(i) / 3.0 + 0.5
		_log(fire_at + Vector3(cos(ang) * 0.95, 0.0, sin(ang) * 0.95), "FireLog%d" % i)
	_hammock(Vector3(-7.4, 0.0, shore_z + 6.6))
	_towel(Vector3(-5.0, 0.0, shore_z + 4.0))
	_lounger(Vector3(-4.2, 0.0, shore_z + 5.2))
	_boat(Vector3(2.4, 0.05, ends.y + 0.35))
	_rope(Vector3(1.15, 0.95, ends.y + 1.15), Vector3(2.15, 0.42, ends.y + 0.7))
	_rope(Vector3(-1.15, 0.95, ends.y + 1.15), Vector3(-1.9, 0.35, ends.y + 0.2))
	_grass(Vector3(1.8, 0.0, shore_z + 3.2))
	_shells(Vector3(-1.4, 0.0, shore_z + 2.4))
	_distant_palms()
	_pier_rail(ends)
	_ground_cover(shore_z)


func _palm(at: Vector3, height: float, lean: float = 0.0) -> void:
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
	var crown := Vector3(0, height - 0.05, 0)
	for i in 8:
		var ang := TAU * float(i) / 8.0 + 0.2
		var dir := Vector3(cos(ang), 0.35, sin(ang))
		var col := Color(0.14, 0.46, 0.16) if i % 2 == 0 else Color(0.30, 0.62, 0.22)
		_frond(st, crown, dir, 1.7, col)
	_sphere(st, crown + Vector3(0.15, -0.15, 0.1), 0.09, Color(0.45, 0.32, 0.16))
	_sphere(st, crown + Vector3(-0.12, -0.2, -0.08), 0.08, Color(0.40, 0.28, 0.14))
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
	root.rotation.z = lean
	add_child(root)
	items.append(root)


func _hut(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z)
	var root := Fadable.new()
	root.name = "Hut"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var floor_y := 1.2
	var wood := Color(0.55, 0.38, 0.2)
	var plank := Color(0.70, 0.52, 0.3)
	var trim := Color(0.36, 0.24, 0.14)
	var straw := Color(0.93, 0.78, 0.42)
	var straw2 := Color(0.74, 0.56, 0.28)
	# Stilts and a plank floor that runs out into a porch.
	for px in [-1.35, 0.0, 1.35]:
		for pz in [-1.15, 1.15, 2.15]:
			_cylinder(st, Vector3(px, floor_y * 0.5, pz), 0.07, floor_y, trim, 5)
	for i in 8:
		var z := -1.35 + float(i) * 0.48
		_box(st, Vector3(0, floor_y, z), Vector3(3.1, 0.06, 0.42), plank if i % 2 == 0 else wood)
	# Vertical plank walls. The sea side keeps a door and a window.
	_wall_planks(st, Vector3(0, floor_y, -1.2), Vector3(1, 0, 0), 2.6, 1.7, wood, -99.0, -99.0)
	_wall_planks(st, Vector3(-1.4, floor_y, 0.3), Vector3(0, 0, 1), 2.6, 1.7, wood, -99.0, -99.0)
	_wall_planks(st, Vector3(1.4, floor_y, 0.3), Vector3(0, 0, 1), 2.6, 1.7, wood, -99.0, -99.0)
	_wall_planks(st, Vector3(0, floor_y, 1.15), Vector3(1, 0, 0), 2.6, 1.7, wood, -0.35, 0.55)
	_box(st, Vector3(0, floor_y + 1.55, 1.15), Vector3(2.7, 0.12, 0.08), trim)
	_box(st, Vector3(-1.4, floor_y + 0.85, 0.3), Vector3(0.06, 1.7, 2.7), trim)
	_box(st, Vector3(1.4, floor_y + 0.85, 0.3), Vector3(0.06, 1.7, 2.7), trim)
	# Open blue door and a warm window.
	_box(st, Vector3(0.55, floor_y + 0.75, 1.45), Vector3(0.05, 1.4, 0.55), Color(0.32, 0.58, 0.72))
	_box(st, Vector3(-0.85, floor_y + 1.15, 1.2), Vector3(0.7, 0.55, 0.04), Color(1.0, 0.78, 0.42))
	_box(st, Vector3(-0.85, floor_y + 0.82, 1.22), Vector3(0.78, 0.05, 0.06), trim)
	# Interior so the doorway reads as a room.
	_box(st, Vector3(0, floor_y + 0.9, -1.05), Vector3(2.4, 1.6, 0.05), Color(0.16, 0.11, 0.08))
	_box(st, Vector3(-0.7, floor_y + 0.48, -0.45), Vector3(0.9, 0.08, 0.4), wood)
	_box(st, Vector3(0.7, floor_y + 0.28, 0.2), Vector3(0.32, 0.4, 0.32), trim)
	# Thatched roof with overhang, two slopes.
	for side in [-1.0, 1.0]:
		for layer in 4:
			var t := float(layer) / 3.0
			var y := floor_y + 2.55 - t * 0.85
			var x := float(side) * (0.28 + t * 1.35)
			_box(st, Vector3(x, y, 0.35), Vector3(1.15, 0.1, 3.5), straw if layer % 2 == 0 else straw2)
	_box(st, Vector3(0, floor_y + 2.62, 0.35), Vector3(0.18, 0.16, 3.6), trim)
	# Porch posts and a rope rail.
	for px in [-1.45, 1.45]:
		_cylinder(st, Vector3(px, floor_y + 0.4, 2.15), 0.05, 0.8, trim, 5)
	_box(st, Vector3(0, floor_y + 0.78, 2.15), Vector3(2.8, 0.05, 0.05), wood)
	# Sign board and a lantern.
	_box(st, Vector3(0, floor_y + 1.85, 1.35), Vector3(1.15, 0.32, 0.06), Color(0.93, 0.88, 0.7))
	_box(st, Vector3(1.15, floor_y + 1.55, 2.05), Vector3(0.16, 0.22, 0.16), Color(1.0, 0.72, 0.28))
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
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.2, floor_y + 1.35, 1.15)
	lamp.light_color = Color(1.0, 0.72, 0.4)
	lamp.light_energy = 0.0
	lamp.omni_range = 3.2
	lamp.name = "Lamp"
	root.add_child(lamp)
	var sign := Label3D.new()
	sign.text = "钓鱼小屋"
	sign.font = load("res://assets/ui.otf")
	sign.font_size = 42
	sign.pixel_size = 0.006
	sign.position = Vector3(0, floor_y + 1.85, 1.4)
	sign.modulate = Color(0.35, 0.22, 0.1)
	root.add_child(sign)
	add_child(root)
	items.append(root)


func _bush(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z)
	var root := Fadable.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sphere(st, Vector3(0, 0.42, 0), 0.42, Color(0.24, 0.52, 0.22))
	_sphere(st, Vector3(0.28, 0.32, 0.1), 0.28, Color(0.34, 0.62, 0.26))
	_sphere(st, Vector3(-0.22, 0.30, -0.08), 0.26, Color(0.20, 0.46, 0.20))
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
	_seat(root, "bench", PI, Vector3(0, 0, -0.22))
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


func _log(at: Vector3, node_name: String = "Log") -> void:
	at.y = IslandData.height_at(at.x, at.z)
	var root := _solid_visual(at, node_name, Constants.LAYER_PROP, Vector3(0, 0.18, 0), Vector3(1.3, 0.36, 0.36))
	var st: SurfaceTool = root.get_meta("st")
	_cylinder_x(st, Vector3(0, 0.18, 0), 0.16, 1.25, Color(0.42, 0.28, 0.16), 8)
	_seat(root, "log", PI, Vector3(0, 0.02, -0.05))
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
	_finish(root)
	var flame := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.16
	cone.height = 0.42
	flame.mesh = cone
	flame.position = Vector3(0, 0.42, 0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.55, 0.12, 0.85)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.45, 0.08)
	fmat.emission_energy_multiplier = 1.4
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.material_override = fmat
	flame.name = "Flame"
	root.add_child(flame)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 0.55, 0)
	light.light_color = Color(1.0, 0.62, 0.28)
	light.light_energy = 0.55
	light.omni_range = 5.0
	light.name = "FireLight"
	root.add_child(light)


func _hammock(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z)
	var root := _solid_visual(at, "Hammock", Constants.LAYER_PROP, Vector3(0, 0.6, 0), Vector3(2.2, 1.4, 0.6))
	var st: SurfaceTool = root.get_meta("st")
	var post := Color(0.4, 0.28, 0.16)
	_cylinder(st, Vector3(-0.9, 0.7, 0), 0.06, 1.4, post, 6)
	_cylinder(st, Vector3(0.9, 0.7, 0), 0.06, 1.4, post, 6)
	var cloth := Color(0.85, 0.45, 0.38)
	_box(st, Vector3(0, 0.72, 0), Vector3(1.6, 0.06, 0.42), cloth)
	_seat(root, "hammock", PI * 0.5, Vector3(0, 0.15, 0), 0.48)
	_finish(root)


func _towel(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z) + 0.02
	var root := _solid_visual(at, "Towel", Constants.LAYER_PROP, Vector3(0, 0.02, 0), Vector3(0.7, 0.05, 1.4))
	var st: SurfaceTool = root.get_meta("st")
	_box(st, Vector3(0, 0.02, 0), Vector3(0.7, 0.02, 1.4), Color(0.86, 0.32, 0.34))
	_box(st, Vector3(0, 0.025, 0.35), Vector3(0.7, 0.012, 0.28), Color(0.95, 0.9, 0.82))
	_seat(root, "towel", 0.0, Vector3(0, 0.05, 0))
	_finish(root)


func _lounger(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z)
	var root := _solid_visual(at, "Lounger", Constants.LAYER_PROP, Vector3(0, 0.25, 0), Vector3(0.7, 0.6, 1.6))
	var st: SurfaceTool = root.get_meta("st")
	var cloth := Color(0.25, 0.45, 0.72)
	_box(st, Vector3(0, 0.28, 0.15), Vector3(0.62, 0.05, 1.1), cloth)
	_box(st, Vector3(0, 0.5, -0.55), Vector3(0.62, 0.4, 0.06), cloth)
	_seat(root, "lounger", PI, Vector3(0, 0.2, -0.15), 0.12)
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


func _frond(st: SurfaceTool, origin: Vector3, dir: Vector3, length: float, col: Color) -> void:
	var steps := 5
	var side0 := dir.cross(Vector3.UP)
	if side0.length_squared() < 1e-6:
		side0 = Vector3.RIGHT
	side0 = side0.normalized()
	var prev := origin
	for i in steps:
		var t := float(i + 1) / float(steps)
		var droop := t * t * 0.85
		var p := origin + dir.normalized() * (length * t) + Vector3.DOWN * droop * length * 0.55
		var w := lerpf(0.16, 0.02, t)
		var side := side0 * w
		var tip_col := col.lerp(Color(0.55, 0.75, 0.28), t * 0.45)
		_face(st, prev + side, prev - side, p + side * 0.6, p - side * 0.6, tip_col)
		prev = p


func _cylinder_x(st: SurfaceTool, center: Vector3, radius: float, length: float, col: Color, sides: int) -> void:
	var x0 := center.x - length * 0.5
	var x1 := center.x + length * 0.5
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var p0 := Vector3(x0, center.y + cos(a0) * radius, center.z + sin(a0) * radius)
		var p1 := Vector3(x0, center.y + cos(a1) * radius, center.z + sin(a1) * radius)
		var q0 := Vector3(x1, p0.y, p0.z)
		var q1 := Vector3(x1, p1.y, p1.z)
		_face(st, p0, p1, q0, q1, col)


func _coil(at: Vector3) -> void:
	at.y = Constants.DECK_Y + 0.04
	var root := Fadable.new()
	root.name = "Coil"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rope := Color(0.72, 0.62, 0.42)
	for turn in 3:
		var rad := 0.12 + float(turn) * 0.045
		var y := 0.03 + float(turn) * 0.015
		for i in 8:
			var a0 := TAU * float(i) / 8.0
			var a1 := TAU * float(i + 1) / 8.0
			var p0 := Vector3(cos(a0) * rad, y, sin(a0) * rad)
			var p1 := Vector3(cos(a1) * rad, y, sin(a1) * rad)
			_face(st, p0, p1, p0 + Vector3(0, 0.02, 0), p1 + Vector3(0, 0.02, 0), rope)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color(1, 1, 1))
	root.setup(mi, null)
	root.position = at
	add_child(root)
	items.append(root)


func _rope(a: Vector3, b: Vector3) -> void:
	var root := Fadable.new()
	root.name = "Rope"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.75, 0.66, 0.46)
	var steps := 6
	var prev := a
	for i in steps:
		var t := float(i + 1) / float(steps)
		var p := a.lerp(b, t)
		p.y -= sin(t * PI) * 0.18
		var dir := (p - prev)
		var side := dir.cross(Vector3.UP).normalized() * 0.015
		if side.length_squared() < 1e-8:
			side = Vector3(0.015, 0, 0)
		_face(st, prev + side, prev - side, p + side, p - side, col)
		prev = p
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color(1, 1, 1))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.setup(mi, null)
	add_child(root)
	items.append(root)


func _wall_planks(st: SurfaceTool, origin: Vector3, along: Vector3, length: float, height: float, col: Color, gap0: float, gap1: float) -> void:
	var n := int(length / 0.22)
	var dir := along.normalized()
	for i in n:
		var u := -length * 0.5 + 0.11 + float(i) * (length / float(n))
		if u > gap0 and u < gap1:
			_box(st, origin + dir * u + Vector3(0, height * 0.82, 0), Vector3(0.2, height * 0.32, 0.06) if absf(dir.x) > 0.5 else Vector3(0.06, height * 0.32, 0.2), col)
			continue
		var size := Vector3(0.2, height, 0.06) if absf(dir.x) > 0.5 else Vector3(0.06, height, 0.2)
		var tone := col.lightened(0.05) if i % 2 == 0 else col.darkened(0.06)
		_box(st, origin + dir * u + Vector3(0, height * 0.5, 0), size, tone)


func _pier_rail(ends: Vector2) -> void:
	var z := ends.y + 1.2
	while z < ends.x - 0.4:
		for side in [-1.0, 1.0]:
			var p := Vector3(side * 1.05, Constants.DECK_Y, z)
			_post(p)
		z += 2.4
	_rope(Vector3(1.05, Constants.DECK_Y + 0.72, ends.y + 1.2), Vector3(1.05, Constants.DECK_Y + 0.72, ends.x - 0.6))
	_rope(Vector3(-1.05, Constants.DECK_Y + 0.72, ends.y + 1.2), Vector3(-1.05, Constants.DECK_Y + 0.72, ends.x - 0.6))


func _post(at: Vector3) -> void:
	var root := Fadable.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cylinder(st, Vector3(0, 0.4, 0), 0.045, 0.8, Color(0.4, 0.28, 0.16), 5)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color(1, 1, 1))
	var body := StaticBody3D.new()
	body.collision_layer = Constants.LAYER_PROP
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.06
	cap.height = 0.8
	cs.shape = cap
	cs.position = Vector3(0, 0.4, 0)
	body.add_child(cs)
	root.setup(mi, body)
	root.position = at
	add_child(root)
	items.append(root)


func _ground_cover(shore_z: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_face(st, Vector3(-0.04, 0, 0), Vector3(0.04, 0, 0), Vector3(0.01, 0.32, 0.02), Vector3(-0.01, 0.28, -0.02), Color(0.28, 0.55, 0.22))
	_face(st, Vector3(0, 0, -0.04), Vector3(0, 0, 0.04), Vector3(0.02, 0.26, 0.01), Vector3(-0.02, 0.22, -0.01), Color(0.4, 0.66, 0.28))
	st.generate_normals()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = st.commit()
	var spots: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 28:
		var p := Vector3(rng.randf_range(-8.0, 8.0), 0, shore_z + rng.randf_range(0.8, 8.0))
		if absf(p.x) < 1.4 and p.z < shore_z + 2.0:
			continue
		p.y = IslandData.height_at(p.x, p.z)
		if p.y < 0.05:
			continue
		spots.append(p)
	mm.instance_count = spots.size()
	for i in spots.size():
		var b := Basis(Vector3.UP, float(i) * 0.9).scaled(Vector3.ONE * rng.randf_range(0.7, 1.3))
		mm.set_instance_transform(i, Transform3D(b, spots[i]))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _mat(Color(1, 1, 1))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _distant_palms() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cylinder(st, Vector3(0, 1.6, 0), 0.12, 3.2, Color(0.48, 0.36, 0.24), 5)
	for i in 5:
		var ang := TAU * float(i) / 5.0
		_frond(st, Vector3(0, 3.2, 0), Vector3(cos(ang), 0.2, sin(ang)), 1.3, Color(0.22, 0.5, 0.18))
	st.generate_normals()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = st.commit()
	var spots: Array[Vector3] = [
		Vector3(-8.0, 0.0, 4.0), Vector3(9.0, 0.0, 2.0), Vector3(-9.0, 0.0, -2.0),
		Vector3(7.5, 0.0, 8.0), Vector3(-3.0, 0.0, 9.5),
	]
	mm.instance_count = spots.size()
	for i in spots.size():
		var p: Vector3 = spots[i]
		p.y = IslandData.height_at(p.x, p.z)
		var basis := Basis(Vector3.UP, float(i) * 0.7)
		mm.set_instance_transform(i, Transform3D(basis, p))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _mat(Color(1, 1, 1))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _seat(root: Fadable, kind: String, yaw: float, local_pos: Vector3, lift: float = 0.0) -> void:
	root.set_meta("kind", kind)
	root.set_meta("yaw", yaw)
	root.set_meta("seat_local", local_pos)
	root.set_meta("lift", lift)


func _boat(at: Vector3) -> void:
	var root := Fadable.new()
	root.name = "Boat"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hull := Color(0.62, 0.44, 0.26)
	var stripe := Color(0.25, 0.45, 0.62)
	var pts: Array[Vector3] = []
	for i in 7:
		var t := float(i) / 6.0
		var z := lerpf(-1.15, 1.15, t)
		var flare := sin(t * PI)
		pts.append(Vector3(0.15 + flare * 0.42, 0.08 + flare * 0.08, z))
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var al := Vector3(-a.x, a.y, a.z)
		var bl := Vector3(-b.x, b.y, b.z)
		var keel_a := Vector3(0, -0.08, a.z)
		var keel_b := Vector3(0, -0.08, b.z)
		_face(st, keel_a, keel_b, a, b, hull)
		_face(st, keel_a, al, keel_b, bl, hull)
		_face(st, a, b, a + Vector3(0, 0.16, 0), b + Vector3(0, 0.16, 0), stripe if i == 3 else hull)
		_face(st, al, al + Vector3(0, 0.16, 0), bl, bl + Vector3(0, 0.16, 0), stripe if i == 3 else Color(0.93, 0.92, 0.88))
	_box(st, Vector3(0, 0.16, -0.35), Vector3(0.55, 0.05, 0.28), Color(0.4, 0.26, 0.14))
	_box(st, Vector3(0, 0.16, 0.4), Vector3(0.55, 0.05, 0.28), Color(0.4, 0.26, 0.14))
	_box(st, Vector3(0.42, 0.2, 0.85), Vector3(0.9, 0.04, 0.08), Color(0.45, 0.3, 0.16))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color(1, 1, 1))
	var body := StaticBody3D.new()
	body.collision_layer = Constants.LAYER_PROP
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.4, 2.3)
	cs.shape = box
	cs.position = Vector3(0, 0.1, 0)
	body.add_child(cs)
	root.setup(mi, body)
	root.position = at
	add_child(root)
	items.append(root)


func _grass(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z)
	var root := Fadable.new()
	root.name = "Grass"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 14:
		var p := Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-0.8, 0.8))
		var h := rng.randf_range(0.22, 0.4)
		var lean := Vector3(rng.randf_range(-0.08, 0.08), h, rng.randf_range(-0.08, 0.08))
		var col := Color(0.30, 0.58, 0.24) if i % 2 == 0 else Color(0.42, 0.66, 0.28)
		_face(st, p + Vector3(-0.03, 0, 0), p + Vector3(0.03, 0, 0), p + lean, p + lean + Vector3(0.01, 0, 0.02), col)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color(1, 1, 1))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.setup(mi, null)
	root.position = at
	add_child(root)
	items.append(root)


func _shells(at: Vector3) -> void:
	at.y = IslandData.height_at(at.x, at.z) + 0.02
	var root := Fadable.new()
	root.name = "Shells"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sphere(st, Vector3(0, 0.04, 0), 0.06, Color(0.92, 0.86, 0.72))
	_sphere(st, Vector3(0.2, 0.03, 0.1), 0.04, Color(0.95, 0.55, 0.45))
	for i in 5:
		var ang := TAU * float(i) / 5.0
		var tip := Vector3(cos(ang) * 0.12, 0.02, sin(ang) * 0.12)
		_face(st, Vector3(0.45, 0.02, 0.2), tip + Vector3(0.45, 0.03, 0.2), tip + Vector3(0.45, 0.02, 0.2) + Vector3(-sin(ang), 0, cos(ang)) * 0.03, Vector3(0.45, 0.02, 0.2) + Vector3(0, 0.01, 0), Color(0.9, 0.35, 0.38))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color(1, 1, 1))
	root.setup(mi, null)
	root.position = at
	add_child(root)
	items.append(root)


func apply_night(on: bool) -> void:
	for item in items:
		var lamp := item.get_node_or_null("Lamp") as OmniLight3D
		if lamp != null:
			lamp.light_energy = 0.8 if on else 0.0
		var fire := item.get_node_or_null("FireLight") as OmniLight3D
		if fire != null:
			fire.light_energy = 1.3 if on else 0.5


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for item in items:
		var flame := item.get_node_or_null("Flame") as MeshInstance3D
		if flame == null:
			continue
		var s := 0.85 + 0.2 * sin(t * 11.0) + 0.08 * sin(t * 23.0)
		flame.scale = Vector3(s, 0.75 + 0.35 * sin(t * 9.0 + 1.0), s)
