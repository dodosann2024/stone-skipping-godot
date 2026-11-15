extends SceneTree
## Orthographic side view, perpendicular to travel, framed on the lower foot.
## A 20 cm ruler stands on the terrain under that foot. Zero is the surface.
##   xvfb-run -a godot --path . --fixed-fps 60 -s res://dev/v41_sole_ruler.gd

const OUT := "screenshots/v41"


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT))
	DisplayServer.window_set_size(Vector2i(960, 720))
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for _i in 30:
		await process_frame
	m.audio_started = true
	if m.start_overlay:
		m.start_overlay.visible = false
	_make_ruler(m)
	m.set_meta("feet_debug", true)
	var spots := [
		Vector2(1.2, m.island.dock_start_z + 5.5),
		Vector2(2.3, -12.8),
		Vector2(0.4, m.island.dock_start_z + 2.0),
	]
	var saved_f := 0
	var saved_b := 0
	for xz in spots:
		var y: float = m._surface(xz.x, xz.y)
		m.player_ctrl.write_body(Vector3(xz.x, y, xz.y), 0.2)
		m.joy.value = Vector2(0.15, -0.95)
		var last := Vector2(999.0, 999.0)
		for _i in 150:
			await process_frame
			if _i < 12:
				continue
			var fk = m.boy.foot_ik if m.boy != null else null
			if fk == null or not fk.pose_ready:
				continue
			var low := 0 if fk.mesh_sole_y[0] <= fk.mesh_sole_y[1] else 1
			var gap: float = fk.mesh_sole_y[low] - fk.mesh_hit_y[low]
			var other: float = fk.mesh_sole_y[1 - low] - fk.mesh_hit_y[1 - low]
			var flight: bool = gap > 0.04 and other > 0.04
			var pos := Vector2(m.player.global_position.x, m.player.global_position.z)
			if pos.distance_to(last) < 0.35 and saved_f + saved_b > 0:
				continue
			var want_bury: bool = gap < -0.01 and saved_b < 2
			var want_float: bool = (not flight) and gap > 0.015 and saved_f < 6
			if not want_bury and not want_float:
				continue
			var kind := "bury" if want_bury else "float"
			var n := (saved_b + 1) if want_bury else (saved_f + 1)
			var path := ProjectSettings.globalize_path("res://%s/feet_%s_%02d.png" % [OUT, kind, n])
			m.get_viewport().get_texture().get_image().save_png(path)
			print("FEET %s %02d low_cm=%.2f other_cm=%.2f flight=%s at=%.2f,%.2f" % [
				kind, n, gap * 100.0, other * 100.0, flight, pos.x, pos.y])
			if want_bury:
				saved_b += 1
			else:
				saved_f += 1
			last = pos
			if saved_f >= 6 and saved_b >= 1:
				break
		if saved_f >= 6 and saved_b >= 1:
			break
	print("FEET_DONE float=%d bury=%d" % [saved_f, saved_b])
	quit(0 if saved_f >= 6 and saved_b >= 1 else 1)


func _make_ruler(m) -> void:
	var holder := Node3D.new()
	holder.name = "FeetRuler"
	m.add_child(holder)
	var post := MeshInstance3D.new()
	var post_box := BoxMesh.new()
	post_box.size = Vector3(0.014, 0.22, 0.014)
	post.mesh = post_box
	post.position = Vector3(0.0, 0.11, 0.0)
	post.material_override = _mat(Color(0.95, 0.12, 0.05))
	holder.add_child(post)
	for cm in range(0, 21):
		var tick := MeshInstance3D.new()
		var box := BoxMesh.new()
		var long := cm % 5 == 0
		box.size = Vector3(0.08 if long else 0.04, 0.005, 0.01)
		tick.mesh = box
		tick.position = Vector3(0.03, float(cm) * 0.01, 0.0)
		tick.material_override = _mat(Color(1, 0.92, 0.15) if long else Color(1, 1, 1))
		holder.add_child(tick)
		if long:
			var lab := Label3D.new()
			lab.text = "%d" % cm
			lab.font_size = 48
			lab.pixel_size = 0.0011
			lab.outline_size = 8
			lab.modulate = Color(1, 0.25, 0.05)
			lab.position = Vector3(0.09, float(cm) * 0.01, 0.0)
			lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			holder.add_child(lab)


func _mat(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = c
	return mat
