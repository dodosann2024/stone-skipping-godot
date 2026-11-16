extends RefCounted
## Builds lie and side-arm clips from the approved library.
## The new clips are Animation resources on the same player. The model node is not rotated.


static func build(player: AnimationPlayer) -> void:
	if player == null:
		return
	var sit := _find(player, "bench_sit_idle")
	var idle := _find(player, "idle")
	if sit == "" or idle == "":
		push_warning("clip author missing sit or idle")
		return
	var sit_anim := player.get_animation(sit)
	var idle_anim := player.get_animation(idle)
	# One hip tilt lays the seated torso back onto the slats. Extra spine
	# bends were folding him into a crunch.
	_add(player, "bench_lie", _offset(sit_anim, {
		"mixamorig_Hips": 72.0,
		"mixamorig_Spine": 12.0,
		"mixamorig_Spine1": 4.0,
		"mixamorig_LeftUpLeg": -28.0,
		"mixamorig_RightUpLeg": -28.0,
		"mixamorig_LeftLeg": -48.0,
		"mixamorig_RightLeg": -48.0,
		"mixamorig_LeftArm": 18.0,
		"mixamorig_RightArm": 18.0,
		"mixamorig_Head": -18.0,
	}))
	_add(player, "lounger_lie", _offset(sit_anim, {
		"mixamorig_Spine": 46.0,
		"mixamorig_Spine1": 20.0,
		"mixamorig_Spine2": 10.0,
		"mixamorig_LeftUpLeg": -18.0,
		"mixamorig_RightUpLeg": -18.0,
		"mixamorig_Head": -8.0,
	}))
	_add(player, "throw_stand", _throw(idle_anim, false))
	_add(player, "throw_crouch", _throw(idle_anim, true))
	print("CLIP_AUTHOR bench_lie lounger_lie throw_stand throw_crouch")


static func _add(player: AnimationPlayer, clip_name: String, anim: Animation) -> void:
	if player.has_animation(clip_name):
		return
	var libs := player.get_animation_library_list()
	if libs.is_empty():
		return
	player.get_animation_library(libs[0]).add_animation(clip_name, anim)


static func _find(player: AnimationPlayer, suffix: String) -> String:
	for n in player.get_animation_list():
		var s := str(n)
		if s == suffix or s.ends_with("/" + suffix):
			return s
	return ""


static func _offset(src: Animation, degrees: Dictionary) -> Animation:
	var dup := src.duplicate() as Animation
	dup.loop_mode = Animation.LOOP_LINEAR
	for i in dup.get_track_count():
		if dup.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var path := str(dup.track_get_path(i))
		var ang := 0.0
		for bone in degrees.keys():
			if path.ends_with(str(bone)):
				ang = deg_to_rad(float(degrees[bone]))
		if ang == 0.0:
			continue
		var extra := Quaternion(Vector3(1, 0, 0), ang)
		var times: Array[float] = []
		var values: Array[Quaternion] = []
		for k in dup.track_get_key_count(i):
			var t := dup.track_get_key_time(i, k)
			times.append(t)
			values.append(dup.rotation_track_interpolate(i, t) * extra)
		while dup.track_get_key_count(i) > 0:
			dup.track_remove_key(i, dup.track_get_key_count(i) - 1)
		for j in times.size():
			dup.rotation_track_insert_key(i, times[j], values[j])
	return dup


static func _throw(src: Animation, crouch: bool) -> Animation:
	var dup := src.duplicate() as Animation
	dup.length = 1.15
	dup.loop_mode = Animation.LOOP_NONE
	var times := [0.0, 0.18, 0.36, 0.5, 0.72, 1.15]
	# Local X bends a mixamo limb. Local Y twists the trunk.
	var x_deg := {
		"mixamorig_RightArm": [-80.0, -120.0, -30.0, 35.0, 85.0, 15.0],
		"mixamorig_RightForeArm": [20.0, 35.0, 10.0, -15.0, -40.0, -8.0],
		"mixamorig_LeftArm": [-20.0, -55.0, -40.0, 10.0, 25.0, 0.0],
		"mixamorig_LeftForeArm": [10.0, 15.0, 8.0, 20.0, 10.0, 0.0],
		"mixamorig_RightUpLeg": [8.0, 18.0, 28.0, 22.0, 10.0, 0.0],
		"mixamorig_LeftUpLeg": [4.0, 10.0, 16.0, 12.0, 6.0, 0.0],
		"mixamorig_RightLeg": [-10.0, -28.0, -40.0, -30.0, -12.0, 0.0],
		"mixamorig_LeftLeg": [-6.0, -16.0, -24.0, -18.0, -8.0, 0.0],
	}
	var z_deg := {
		"mixamorig_RightArm": [10.0, -70.0, -20.0, 55.0, 110.0, 25.0],
		"mixamorig_RightForeArm": [0.0, -25.0, -10.0, 15.0, 35.0, 5.0],
		"mixamorig_LeftArm": [0.0, 30.0, 20.0, -15.0, -25.0, 0.0],
	}
	var y_deg := {
		"mixamorig_Hips": [0.0, -18.0, 10.0, 28.0, 12.0, 0.0],
		"mixamorig_Spine": [0.0, 14.0, -6.0, -18.0, -8.0, 0.0],
		"mixamorig_Spine1": [0.0, 8.0, -4.0, -10.0, -4.0, 0.0],
	}
	if crouch:
		x_deg["mixamorig_RightUpLeg"] = [20.0, 40.0, 55.0, 48.0, 22.0, 6.0]
		x_deg["mixamorig_LeftUpLeg"] = [16.0, 32.0, 46.0, 40.0, 18.0, 4.0]
		x_deg["mixamorig_RightLeg"] = [-24.0, -50.0, -70.0, -60.0, -28.0, -8.0]
		x_deg["mixamorig_LeftLeg"] = [-18.0, -40.0, -58.0, -48.0, -22.0, -6.0]
		x_deg["mixamorig_RightArm"] = [-90.0, -130.0, -40.0, 20.0, 70.0, 10.0]
	for i in dup.get_track_count():
		var path := str(dup.track_get_path(i))
		var bone := ""
		var use_y := false
		for name in x_deg.keys():
			if path.ends_with(str(name)):
				bone = str(name)
		if bone == "":
			for name in y_deg.keys():
				if path.ends_with(str(name)):
					bone = str(name)
					use_y = true
		if bone == "":
			continue
		if dup.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			var base: Quaternion = dup.rotation_track_interpolate(i, 0.2)
			while dup.track_get_key_count(i) > 0:
				dup.track_remove_key(i, dup.track_get_key_count(i) - 1)
			var series: Array = y_deg[bone] if use_y else x_deg[bone]
			var z_series: Array = z_deg[bone] if z_deg.has(bone) else []
			for k in times.size():
				var extra := Quaternion(Vector3(0, 1, 0) if use_y else Vector3(1, 0, 0), deg_to_rad(float(series[k])))
				if z_series.size() == times.size():
					extra = extra * Quaternion(Vector3(0, 0, 1), deg_to_rad(float(z_series[k])))
				dup.rotation_track_insert_key(i, times[k], base * extra)
		elif crouch and dup.track_get_type(i) == Animation.TYPE_POSITION_3D and path.ends_with("mixamorig_Hips"):
			var origin: Vector3 = dup.position_track_interpolate(i, 0.2)
			while dup.track_get_key_count(i) > 0:
				dup.track_remove_key(i, dup.track_get_key_count(i) - 1)
			var drops := [0.02, 0.06, 0.09, 0.08, 0.04, 0.0]
			for k in times.size():
				var p := origin
				p.y -= drops[k]
				dup.position_track_insert_key(i, times[k], p)
	return dup
