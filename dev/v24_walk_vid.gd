extends SceneTree
## Side-view walk + run mp4 frames for v24 — real gait with locomotion advancing.

func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	DisplayServer.window_set_size(Vector2i(390, 844))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(390, 844)
	DirAccess.make_dir_recursive_absolute("/workspace/screenshots/v24/walk_frames")
	# Clear old frames
	var dir := DirAccess.open("/workspace/screenshots/v24/walk_frames")
	if dir:
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if fn.ends_with(".png"):
				dir.remove(fn)
			fn = dir.get_next()
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 40:
		await process_frame
	m.demo_mode = true
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
	m.ui_root.visible = false
	m._place(Vector3(2.5, 0, -7.5), 0.0)
	m.face_yaw = 0.0
	m.boy.rotation = Vector3.ZERO
	m.boy.set_idle()
	for _i in 6:
		await process_frame
	var frame := 0
	# Walk ~2.0 s (60 frames @ 30fps) with real position advance driving phase
	m.boy.set_move(1.2)
	m.boy.anim = "move"
	m.boy.move_w = 1.0
	m.boy.act_w = 0.0
	m.boy.act_target = 0.0
	m.boy.has_prev = false
	for i in 60:
		var dt := 1.0 / 30.0
		m.boy.set_move(1.2)
		m.boy.move_w = 1.0
		m.boy.act_w = 0.0
		# Advance root so stride phase tracks distance (real walk cycle).
		m.player.global_position.x += 1.2 * dt
		m.boy.global_position = m.player.global_position
		m.boy._tick(dt)
		# Bake after mixer so llvmpipe shows stride; restore before next tick.
		m.boy.bake_pose_mesh()
		m.cam_target = m.player.global_position + Vector3(0, 0.62, 0)
		m.cam_yaw = PI * 0.5
		m.cam_pitch = 0.06
		m.cam_dist = 2.7
		m.cam_fixed = true
		m._apply_camera()
		for _w in 2:
			m._apply_camera()
			await process_frame
		vp.get_texture().get_image().save_png("/workspace/screenshots/v24/walk_frames/f%04d.png" % frame)
		m.boy.restore_pose_mesh()
		frame += 1
	# Run ~2.0 s
	m.boy.set_move(2.15)
	m.boy.move_w = 1.0
	m.boy.run_k = 1.0
	for i in 60:
		var dt2 := 1.0 / 30.0
		m.boy.set_move(2.15)
		m.boy.move_w = 1.0
		m.boy.run_k = 1.0
		m.boy.act_w = 0.0
		m.player.global_position.x += 2.15 * dt2
		m.boy.global_position = m.player.global_position
		m.boy._tick(dt2)
		m.boy.bake_pose_mesh()
		m.cam_target = m.player.global_position + Vector3(0, 0.62, 0)
		m.cam_yaw = PI * 0.5
		m.cam_pitch = 0.06
		m.cam_dist = 2.7
		m._apply_camera()
		for _w in 2:
			m._apply_camera()
			await process_frame
		vp.get_texture().get_image().save_png("/workspace/screenshots/v24/walk_frames/f%04d.png" % frame)
		m.boy.restore_pose_mesh()
		frame += 1
	print("WALK_FRAMES ", frame)
	quit(0)
