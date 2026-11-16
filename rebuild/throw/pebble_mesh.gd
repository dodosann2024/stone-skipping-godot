class_name PebbleMesh
extends RefCounted
## One irregular pebble, built once. About 6 cm across and flatter than it is wide.


static var _mesh: ArrayMesh


static func mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 6
	var seg := 9
	var grid: Array = []
	for r in rings + 1:
		var row: Array[Vector3] = []
		var v := PI * float(r) / float(rings)
		for s in seg:
			var u := TAU * float(s) / float(seg)
			var n := 1.0 + 0.15 * sin(u * 3.0 + 0.5) * sin(v * 2.0) + 0.07 * cos(u * 5.0 - 0.8)
			var flat := 0.36 + 0.1 * sin(u * 2.0 + 0.3)
			var p := Vector3(sin(v) * cos(u) * n, cos(v) * flat * n, sin(v) * sin(u) * (n * 0.92)) * 0.031
			row.append(p)
		grid.append(row)
	for r in rings:
		for s in seg:
			var s2 := (s + 1) % seg
			var a: Vector3 = grid[r][s]
			var b: Vector3 = grid[r][s2]
			var c: Vector3 = grid[r + 1][s]
			var d: Vector3 = grid[r + 1][s2]
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(b)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(d)
	st.generate_normals()
	_mesh = st.commit()
	return _mesh
