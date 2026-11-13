extends SceneTree
## Side-view walk + run mp4 frames for v24 posture review.

func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	DisplayServer.window_set_size(Vector2i(390, 844))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(390, 844)
	DirAccess.make_dir_recursive_absolute("/workspace/screenshots/v24/walk_frames")
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 40:
		await process_frame
	m.demo_mode = true
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
	m.ui_root.visible = false
	m._place(Vector3(3.5, 0, -7.5), 0.0)
	m.face_yaw = 0.0
	m.boy.rotation = Vector3.ZERO
	# Walk ~2.0 s then run ~2.0 s
	var frame := 0
	m.boy.set_move(1.2)
	for i in 60:
		m.boy.phase = fposmod(m.boy.phase + 0.035, 1.0)
		m.boy._tick(1.0 / 30.0)
		m.player.global_position.x += 0.04
		m.boy.global_position = m.player.global_position
		m.cam_target = m.player.global_position + Vector3(0, 0.62, 0)
		m.cam_yaw = PI * 0.5
		m.cam_pitch = 0.06
		m.cam_dist = 2.7
		m._apply_camera()
		await process_frame
		vp.get_texture().get_image().save_png("/workspace/screenshots/v24/walk_frames/f%04d.png" % frame)
		frame += 1
	m.boy.set_move(2.15)
	for i in 60:
		m.boy.phase = fposmod(m.boy.phase + 0.05, 1.0)
		m.boy._tick(1.0 / 30.0)
		m.player.global_position.x += 0.07
		m.boy.global_position = m.player.global_position
		m.cam_target = m.player.global_position + Vector3(0, 0.62, 0)
		m.cam_yaw = PI * 0.5
		m.cam_pitch = 0.06
		m.cam_dist = 2.7
		m._apply_camera()
		await process_frame
		vp.get_texture().get_image().save_png("/workspace/screenshots/v24/walk_frames/f%04d.png" % frame)
		frame += 1
	print("WALK_FRAMES ", frame)
	quit(0)
