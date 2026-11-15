extends SceneTree
## Same four viewpoints in the old build, for the v40-vs-v42 stills.
##   xvfb-run -a godot --path . --fixed-fps 20 -s res://dev/v40_four_spots.gd


func _initialize() -> void:
	root.size = Vector2i(390, 844)
	call_deferred("_go")


func _go() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _i in 30:
		await process_frame
	if main.has_method("_start_audio"):
		main._start_audio()
	for _i in 8:
		await process_frame
	main.set_process(false)
	main.set_physics_process(false)
	if main.boy != null:
		main.boy.set_process(false)
		main.boy.set_physics_process(false)
	var island = main.island
	var hammock: Vector3 = (island.hammock_a + island.hammock_b) * 0.5
	var spots := {
		"spawn": island.player_spot,
		"pier": Vector3(0.2, island.DECK_Y, island.dock_start_z + 1.2),
		"hut": island.hut_pos + Vector3(-1.2, 0, 1.0),
		"hammock": hammock,
	}
	var dir := ProjectSettings.globalize_path("res://screenshots/v42/m6")
	DirAccess.make_dir_recursive_absolute(dir)
	for name in ["spawn", "pier", "hut", "hammock"]:
		var spot: Vector3 = spots[name]
		if main.player_ctrl != null and main.player_ctrl.has_method("write_position"):
			main.player_ctrl.write_position(spot)
		main.player.global_position = spot
		main.camera.current = true
		main.camera.global_position = spot + Vector3(-5.5, 5.2, -7.5)
		main.camera.look_at(spot + Vector3(1.5, 1.2, 4.0), Vector3.UP)
		for _i in 3:
			await process_frame
		var active := root.get_viewport().get_camera_3d()
		print("CAM set ", main.camera.global_position, " active ", active, " at ", active.global_position if active != null else Vector3.ZERO)
		var img := root.get_viewport().get_texture().get_image()
		var path := dir + "/v40_%s.png" % name
		img.save_png(path)
		print("WROTE ", path, " spot ", spot)
	print("V40_SHOTS")
	quit(0)
