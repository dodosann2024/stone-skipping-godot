extends SceneTree
## Side view, 20 cm ruler, zero on the collision under the visible lower foot.
## The print is the harness gap (dominant skinned sole, short ray) and the old
## ankle gap. Shots are at least 0.45 m apart.
##   xvfb-run -a godot --path . --fixed-fps 60 -s res://dev/v41_sole_ruler.gd

const OUT := "screenshots/v41"


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT))
	DisplayServer.window_set_size(Vector2i(960, 720))
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for _i in 36:
		await process_frame
	m.audio_started = true
	if m.start_overlay:
		m.start_overlay.visible = false
	var xz := Vector2(1.2, m.island.dock_start_z + 5.5)
	var y: float = m._surface(xz.x, xz.y)
	m.player_ctrl.write_body(Vector3(xz.x, y, xz.y), 0.0)
	m._shot_side = true
	m.joy.value = Vector2(0.0, -0.95)
	var ruler := _make_ruler(m)
	var saved := 0
	var last := Vector2(999.0, 999.0)
	for _i in 320:
		await process_frame
		if _i < 40:
			continue
		var fk = m.boy.foot_ik if m.boy != null else null
		if fk == null or not fk.pose_ready:
			continue
		if absf(fk.mesh_gap_min) > 0.5:
			continue
		var pos := Vector2(m.player.global_position.x, m.player.global_position.z)
		if saved > 0 and pos.distance_to(last) < 0.45:
			continue
		var flag: bool = fk.mesh_gap_min > 0.015 or fk.ankle_gap_min > 0.015
		if not flag:
			continue
		var sk: Skeleton3D = m.boy.skel
		var bi := sk.find_bone("mixamorig_LeftFoot" if fk.mesh_sole_y[0] <= fk.mesh_sole_y[1] else "mixamorig_RightFoot")
		var ankle: Vector3 = (sk.to_global(sk.get_bone_global_pose(bi).origin))
		var ground_y: float = m._surface(ankle.x, ankle.z)
		var lateral := Vector3(cos(float(m.face_yaw)), 0.0, -sin(float(m.face_yaw)))
		ruler.global_position = Vector3(ankle.x, ground_y, ankle.z) + lateral * 0.18
		ruler.visible = true
		RenderingServer.force_draw()
		var path := ProjectSettings.globalize_path("res://%s/ruler_%02d.png" % [OUT, saved + 1])
		m.get_viewport().get_texture().get_image().save_png(path)
		print("RULER %02d sole_cm=%.2f ankle_cm=%.2f at=%.1f,%.1f" % [
			saved + 1, fk.mesh_gap_min * 100.0, fk.ankle_gap_min * 100.0, pos.x, pos.y])
		saved += 1
		last = pos
		if saved >= 6:
			break
	print("RULER_DONE shots=%d" % saved)
	quit(0 if saved >= 5 else 1)


func _make_ruler(m) -> Node3D:
	var holder := Node3D.new()
	m.add_child(holder)
	var mi := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mi.material_override = mat
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_set_color(Color(1, 0.95, 0.2))
	mesh.surface_add_vertex(Vector3(0, 0, 0))
	mesh.surface_add_vertex(Vector3(0, 0.20, 0))
	for cm in range(0, 21):
		var yy := float(cm) * 0.01
		var w := 0.06 if cm % 5 == 0 else 0.03
		mesh.surface_set_color(Color(1, 0.15, 0.1) if cm % 5 == 0 else Color(1, 1, 0.92))
		mesh.surface_add_vertex(Vector3(0, yy, 0))
		mesh.surface_add_vertex(Vector3(w, yy, 0))
	mesh.surface_end()
	mi.mesh = mesh
	holder.add_child(mi)
	for cm in [0, 10, 20]:
		var lab := Label3D.new()
		lab.text = "%d cm" % cm
		lab.font_size = 48
		lab.pixel_size = 0.0008
		lab.outline_size = 6
		lab.modulate = Color(1, 0.95, 0.55)
		lab.position = Vector3(0.07, float(cm) * 0.01, 0)
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		holder.add_child(lab)
	return holder
