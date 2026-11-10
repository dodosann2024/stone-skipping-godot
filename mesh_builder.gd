class_name MeshBuilder
extends RefCounted
## Accumulates flat-shaded, vertex-coloured triangles into one mesh (one draw call).
## Vertex colour alpha is used as a wind-sway weight by the foliage shader.

var st := SurfaceTool.new()
var tris := 0

func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, n := Vector3.ZERO) -> void:
	tri3(a, b, c, col, col, col, n)

func tri3(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, n := Vector3.ZERO) -> void:
	var nn := n
	if nn == Vector3.ZERO:
		nn = (c - a).cross(b - a)
		if nn.length_squared() < 1e-12:
			return
		nn = nn.normalized()
	st.set_normal(nn); st.set_color(ca); st.add_vertex(a)
	st.set_normal(nn); st.set_color(cb); st.add_vertex(b)
	st.set_normal(nn); st.set_color(cc); st.add_vertex(c)
	tris += 1

## Triangle whose front face points along `outward` (winding fixed automatically).
func face(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, outward: Vector3, n := Vector3.ZERO) -> void:
	var cr := (c - a).cross(b - a)
	if cr.dot(outward) < 0.0:
		var t := b; b = c; c = t
		var tc := cb; cb = cc; cc = tc
	tri3(a, b, c, ca, cb, cc, n if n != Vector3.ZERO else cr.normalized() * signf(cr.dot(outward)))

## Smooth-shaded triangle (per-vertex normals); winding is fixed from the normals.
func tri_sm(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var cr := (c - a).cross(b - a)
	if cr.length_squared() < 1e-16:
		return
	if cr.dot(na + nb + nc) < 0.0:
		var t := b; b = c; c = t
		var tn := nb; nb = nc; nc = tn
		var tc := cb; cb = cc; cc = tc
	st.set_normal(na); st.set_color(ca); st.add_vertex(a)
	st.set_normal(nb); st.set_color(cb); st.add_vertex(b)
	st.set_normal(nc); st.set_color(cc); st.add_vertex(c)
	tris += 1

## Append a primitive mesh keeping its own smooth normals.
func prim_smooth(mesh: Mesh, xf: Transform3D, col: Color) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var nb := xf.basis.inverse().transposed()
	var n := idx.size() if idx.size() > 0 else verts.size()
	for i in range(0, n, 3):
		var ia := idx[i] if idx.size() > 0 else i
		var ib := idx[i + 1] if idx.size() > 0 else i + 1
		var ic := idx[i + 2] if idx.size() > 0 else i + 2
		tri_sm(xf * verts[ia], xf * verts[ib], xf * verts[ic], (nb * norms[ia]).normalized(), (nb * norms[ib]).normalized(), (nb * norms[ic]).normalized(), col, col, col)

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	tri(a, b, c, col)
	tri(a, c, d, col)

## Append a primitive mesh, transformed, optionally jittered (low-poly rock look).
func prim(mesh: Mesh, xf: Transform3D, col: Color, rng: RandomNumberGenerator = null, jitter := 0.0, col_var := 0.0, sway := -1.0) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var moved := {}
	var vl := PackedVector3Array()
	vl.resize(verts.size())
	for i in verts.size():
		var v := verts[i]
		if jitter > 0.0 and rng:
			var key := Vector3i(roundi(v.x * 997.0), roundi(v.y * 997.0), roundi(v.z * 997.0))
			if not moved.has(key):
				moved[key] = v + Vector3(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
			v = moved[key]
		vl[i] = xf * v
	var n := idx.size() if idx.size() > 0 else vl.size()
	for i in range(0, n, 3):
		var ia := idx[i] if idx.size() > 0 else i
		var ib := idx[i + 1] if idx.size() > 0 else i + 1
		var ic := idx[i + 2] if idx.size() > 0 else i + 2
		var c := col
		if col_var > 0.0 and rng:
			var k := rng.randf_range(-col_var, col_var)
			c = Color(col.r + k, col.g + k, col.b + k, col.a)
		if sway >= 0.0:
			# sway weight grows with height inside the primitive
			var a := vl[ia]; var b := vl[ib]; var cc := vl[ic]
			tri3(a, b, cc, Color(c, sway), Color(c, sway), Color(c, sway))
		else:
			tri(vl[ia], vl[ib], vl[ic], c)

func commit() -> ArrayMesh:
	return st.commit()
