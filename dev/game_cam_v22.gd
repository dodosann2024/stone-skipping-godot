extends SceneTree
func _initialize() -> void:
	call_deferred("_run")

func _dismiss(main) -> void:
	main.audio_started = true
	if main.start_overlay:
		main.start_overlay.queue_free()
		main.start_overlay = null

func _face_cam(main, pitch := 0.26, dist := 3.6) -> void:
	main.ex_yaw = main.face_yaw + PI
	main.ex_pitch = pitch
	main.ex_dist = dist
	var c: Array = main._explore_cam()
	main.cam_target = c[0]
	main.cam_yaw = c[1]
	main.cam_pitch = c[2]
	main.cam_dist = c[3]
	main._apply_camera()

func _run() -> void:
	var main = load("res://main.tscn").instantiate()
	get_root().add_child(main)
	for i in 55:
		await process_frame
	_dismiss(main)
	var vp = get_root().get_viewport()
	vp.size = Vector2i(390, 844)

	# Day dock face-on
	main.night_on = false
	main.night_k = 0.0
	main._update_night(0.0, true)
	main._place(Vector3(0.15, 0, main.island.dock_end_z + 1.35), 0.0)
	_face_cam(main, 0.24, 3.5)
	for i in 28:
		await process_frame
	_face_cam(main, 0.24, 3.5)
	await process_frame
	vp.get_texture().get_image().save_png("/tmp/v22/game_day.png")
	print("DAY")

	# Night by campfire, lit face
	main.night_on = true
	main.night_k = 1.0
	main._update_night(0.0, true)
	var c: Vector3 = main.island.campfire_pos
	# stand just outside fire ring, facing camera (and roughly toward fire light from side)
	var to_cam := Vector3(1.2, 0, 1.4)
	main._place(c + to_cam, atan2(-to_cam.x, -to_cam.z))
	_face_cam(main, 0.20, 3.2)
	for i in 45:
		await process_frame
	_face_cam(main, 0.20, 3.2)
	await process_frame
	vp.get_texture().get_image().save_png("/tmp/v22/game_night.png")
	print("NIGHT at ", c)
	quit(0)
