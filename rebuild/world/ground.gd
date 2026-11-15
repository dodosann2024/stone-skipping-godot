class_name Ground
extends StaticBody3D
## One vertex list becomes the mesh and the walk collision. Rays read that body.

var faces: PackedVector3Array = PackedVector3Array()


func _ready() -> void:
	collision_layer = Constants.LAYER_GROUND
	collision_mask = 0
	var built := _build_arrays()
	var mesh := _mesh_from(built)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	faces = mesh.get_faces()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)


func height(x: float, z: float) -> float:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return 0.0
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 12.0, z), Vector3(x, -6.0, z))
	q.collision_mask = Constants.LAYER_GROUND
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	if hit.has("position"):
		return float(hit.position.y)
	return 0.0


func normal_at(x: float, z: float) -> Vector3:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return Vector3.UP
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 12.0, z), Vector3(x, -6.0, z))
	q.collision_mask = Constants.LAYER_GROUND
	var hit := space.intersect_ray(q)
	if hit.has("normal"):
		return (hit.normal as Vector3).normalized()
	return Vector3.UP


func _build_arrays() -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := IslandData.TERRAIN_STEP
	var half := IslandData.TERRAIN_HALF
	var n := int(half * 2.0 / step)
	for j in n:
		for i in n:
			var x0 := -half + float(i) * step
			var z0 := -half + float(j) * step
			var x1 := x0 + step
			var z1 := z0 + step
			var h00 := IslandData.height_at(x0, z0)
			var h10 := IslandData.height_at(x1, z0)
			var h01 := IslandData.height_at(x0, z1)
			var h11 := IslandData.height_at(x1, z1)
			if maxf(maxf(h00, h10), maxf(h01, h11)) < -0.55:
				continue
			if _on_pier((x0 + x1) * 0.5, (z0 + z1) * 0.5):
				continue
			var a := Vector3(x0, h00, z0)
			var b := Vector3(x1, h10, z0)
			var c := Vector3(x0, h01, z1)
			var d := Vector3(x1, h11, z1)
			_tri(st, a, b, c)
			_tri(st, b, d, c)
	_add_dock(st)
	return {"tool": st}


func _mesh_from(built: Dictionary) -> ArrayMesh:
	var st: SurfaceTool = built.tool
	st.generate_normals()
	return st.commit()


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, paint: Color = Color(0, 0, 0, 0)) -> void:
	var col := paint
	if paint.a <= 0.0:
		col = _color((a.y + b.y + c.y) / 3.0, (a.x + b.x + c.x) / 3.0, (a.z + b.z + c.z) / 3.0)
	st.set_color(col)
	st.add_vertex(a)
	st.set_color(col)
	st.add_vertex(b)
	st.set_color(col)
	st.add_vertex(c)


func _color(y: float, x: float, z: float) -> Color:
	if y < 0.08:
		return Color(0.76, 0.71, 0.52)
	if IslandData.shore_d(x, z) < -5.5 and y > 0.45:
		return Color(0.45, 0.62, 0.34)
	return Color(0.84, 0.76, 0.55)


func _on_pier(x: float, z: float) -> bool:
	var ends := IslandData.dock_ends()
	if absf(x) > 2.0:
		return false
	return z < ends.x + 4.0 and z > ends.y - 2.0


func _add_dock(st: SurfaceTool) -> void:
	var ends := IslandData.dock_ends()
	var z0: float = ends.x
	var z1: float = ends.y
	var z_beach := z0 - 0.8
	var mid := (z_beach + z1) * 0.5
	var length := absf(z_beach - z1)
	_box(st, Vector3(0.0, Constants.DECK_Y - 0.07, mid), Vector3(2.3, 0.14, length))
	_box(st, Vector3(0.0, Constants.DECK_Y - 0.07, z1 + 1.6), Vector3(6.2, 0.14, 3.6))
	var sand := IslandData.height_at(0.0, z0 + 3.0)
	var z_from := z_beach
	var z_to := z0 + 3.2
	var steps := 18
	for i in steps:
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var za := lerpf(z_from, z_to, t0)
		var zb := lerpf(z_from, z_to, t1)
		var top := lerpf(Constants.DECK_Y, sand, t0)
		_box(st, Vector3(0.0, top - 0.06, (za + zb) * 0.5), Vector3(2.3, 0.12, absf(zb - za) + 0.05))


func _box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var p000 := center + Vector3(-h.x, -h.y, -h.z)
	var p100 := center + Vector3(h.x, -h.y, -h.z)
	var p010 := center + Vector3(-h.x, h.y, -h.z)
	var p110 := center + Vector3(h.x, h.y, -h.z)
	var p001 := center + Vector3(-h.x, -h.y, h.z)
	var p101 := center + Vector3(h.x, -h.y, h.z)
	var p011 := center + Vector3(-h.x, h.y, h.z)
	var p111 := center + Vector3(h.x, h.y, h.z)
	var wood := Color(0.55, 0.38, 0.22)
	_tri(st, p010, p110, p011, wood)
	_tri(st, p110, p111, p011, wood)
	_tri(st, p000, p001, p100, wood)
	_tri(st, p100, p001, p101, wood)
	_tri(st, p000, p010, p001, wood)
	_tri(st, p001, p010, p011, wood)
	_tri(st, p100, p101, p110, wood)
	_tri(st, p101, p111, p110, wood)
	_tri(st, p001, p011, p101, wood)
	_tri(st, p101, p011, p111, wood)
	_tri(st, p000, p100, p010, wood)
	_tri(st, p100, p110, p010, wood)


func _ramp(st: SurfaceTool, z_sand: float, z_deck: float, y0: float, y1: float) -> void:
	var x := 1.2
	var wood := Color(0.55, 0.38, 0.22)
	var a := Vector3(-x, y0, z_sand)
	var b := Vector3(x, y0, z_sand)
	var c := Vector3(-x, y1, z_deck)
	var d := Vector3(x, y1, z_deck)
	_tri(st, a, b, c, wood)
	_tri(st, b, d, c, wood)
