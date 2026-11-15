extends SceneTree

func _initialize() -> void:
	for p in ["res://character/side_arm.gd", "res://character/rest_pose.gd", "res://character/boy_visual.gd", "res://throw/stone.gd", "res://world/props.gd", "res://core/game.gd"]:
		var s = load(p)
		print("LOAD ", p, " ", s)
	quit()
