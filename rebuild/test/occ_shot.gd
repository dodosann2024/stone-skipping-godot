extends SceneTree
## Two stills of the pier / hut spot: fade on, then ?occ=0.
##   xvfb-run -a godot --path . --fixed-fps 30 -s res://test/occ_shot.gd


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	var packed := load("res://core/game.tscn") as PackedScene
	var game := packed.instantiate()
	root.add_child(game)
	for _i in 40:
		await process_frame
	var ends := IslandData.dock_ends()
	var spot := Vector3(-0.4, 0.0, ends.x + 2.6)
	spot.y = game.ground.height(spot.x, spot.z)
	if spot.y < -2.0:
		spot.y = 0.4
	game.player.global_position = spot + Vector3(0, 0.05, 0)
	game.player.face_yaw = PI
	game.player.rotation.y = PI
	for _i in 20:
		await process_frame
	var cam: Camera3D = game.rig.cam
	var eye := spot + Vector3(-1.6, 1.5, -3.4)
	cam.global_position = eye
	cam.look_at(spot + Vector3(0.4, 0.9, 1.2), Vector3.UP)
	await process_frame
	await process_frame
	var dir := ProjectSettings.globalize_path("res://../screenshots/v42/m3")
	DirAccess.make_dir_recursive_absolute(dir)
	_save(game, dir + "/occ_on.png")
	game.fader.enabled = false
	for item in game.props.items:
		item.set_target(1.0)
		item.alpha = 1.0
		item.tick(0.01)
	await process_frame
	await process_frame
	_save(game, dir + "/occ_off.png")
	print("OCC_SHOTS %s" % dir)
	quit(0)


func _save(game: Node, path: String) -> void:
	var img := game.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("WROTE ", path)
