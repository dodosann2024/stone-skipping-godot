extends SceneTree
## Four views for the visual pass.
##   xvfb-run -a godot --path . --fixed-fps 30 -s res://test/m6_shots.gd


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	var game := (load("res://core/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 45:
		await process_frame
	var ends := IslandData.dock_ends()
	var dir := ProjectSettings.globalize_path("res://../screenshots/v42/m6")
	DirAccess.make_dir_recursive_absolute(dir)
	var spots := {
		"spawn": Vector3(0.0, Constants.DECK_Y, ends.y + 1.3),
		"pier": Vector3(0.2, 0.0, ends.x + 1.2),
		"hut": Vector3(2.2, 0.0, ends.x + 3.6),
		"hammock": Vector3(4.6, 0.0, ends.x + 5.0),
	}
	for name in ["spawn", "pier", "hut", "hammock"]:
		var spot: Vector3 = spots[name]
		if name != "spawn":
			spot.y = game.ground.height(spot.x, spot.z)
			if spot.y < -2.0:
				spot.y = 0.3
		game.player.global_position = spot + Vector3(0, 0.05, 0)
		game.player.rotation.y = PI
		var cam: Camera3D = game.rig.cam
		var eye := spot + Vector3(-2.2, 2.4, -4.6)
		cam.global_position = eye
		cam.look_at(spot + Vector3(0, 1.0, 1.5), Vector3.UP)
		for _i in 8:
			await process_frame
		var img := game.get_viewport().get_texture().get_image()
		var path := dir + "/v42_%s.png" % name
		img.save_png(path)
		print("WROTE ", path)
	print("M6_SHOTS")
	quit(0)
