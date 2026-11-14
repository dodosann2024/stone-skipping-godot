extends SceneTree
## v27 verification stills — day path (user spot), day beach, night beach/campfire/forest/dock.
## screenshots/v27/*.png — no docs/ export.

const OUT := "/workspace/screenshots/v27"
const W := 390
const H := 844


func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	DisplayServer.window_set_size(Vector2i(W, H))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(W, H)
	DirAccess.make_dir_recursive_absolute(OUT)
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 90:
		await process_frame
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
		m.start_overlay = null
	m.demo_mode = false
	m.demo_cam = false
	m.cam_fixed = false
	# Desktop resolution for stills; MID-like soft 2-split + short range for dense near dapples.
	m.mq.setup(false, false, vp, m.sun)
	if m.sun:
		m.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		m.sun.directional_shadow_max_distance = 12.0
		m.sun.directional_shadow_split_1 = 0.22
		m.sun.directional_shadow_blend_splits = true
		m.sun.shadow_blur = 10.0
		m.sun.light_angular_distance = 4.5
		m.sun.shadow_bias = 0.09
		m.sun.shadow_normal_bias = 2.8
		m.sun.directional_shadow_pancake_size = 1.2
		m.sun.light_angular_distance = 5.0
	m.refl_auto = false
	m._set_refl_level(0)
	if m.boy:
		m.boy.show_stone(false)
		# Soft radial contact blob stays visible (replaces hard foot-square cast).

	# Day path — user iPhone: behind boy on lighthouse climb, rope fence left, lighthouse top-right.
	await _set_tod(m, "day")
	var path_p := _lighthouse_climb_spot(m)
	var to_lh: Vector3 = m.island.lighthouse_pos - path_p
	to_lh.y = 0.0
	var face := atan2(-to_lh.x, -to_lh.z) if to_lh.length_squared() > 1e-6 else -0.4
	m._place(path_p, face)
	m.ex_yaw = m.face_yaw
	m.ex_pitch = 0.16
	m.ex_dist = 3.8
	m.cam_yaw = m.ex_yaw
	m.cam_pitch = m.ex_pitch
	m.cam_dist = m.ex_dist
	m._cam_arm_k = 1.0
	m._cam_arm_want = 1.0
	m._cam_slide = 0.0
	m._cam_slide_want = 0.0
	for _i in 45:
		m.ex_yaw = m.face_yaw
		m.ex_pitch = 0.16
		m.ex_dist = 3.8
		if m.sun:
			m.sun.shadow_blur = 10.0
			m.sun.light_angular_distance = 4.5
			m.sun.directional_shadow_max_distance = 12.0
			m.sun.directional_shadow_split_1 = 0.22
			m.sun.directional_shadow_blend_splits = true
		await process_frame
	await _shot(vp, "day_path.png")

	# Day beach
	m._place(Vector3(1.6, 0, m.island.dock_start_z + 3.5), 0.2)
	m.ex_yaw = m.face_yaw + PI + 0.2
	m.ex_pitch = 0.20
	m.ex_dist = 5.0
	for _i in 25:
		await process_frame
	await _shot(vp, "day_beach.png")

	# Night beach — same spot/framing as v26 night_beach_boy.
	await _set_tod(m, "night")
	var beach: Vector3 = m.island.shore_pt(-0.85, 1.7)
	m._place(beach, 0.12)
	m.player.position.y = m._surface(m.player.position.x, m.player.position.z)
	m.ground_y = m.player.position.y
	m.boy.global_position = m.player.global_position
	m.island.foliage_mat.set_shader_parameter("cut_radius", 3.8)
	m.island.leaf_mat.set_shader_parameter("cut_radius", 3.8)
	m.island.static_mat.set_shader_parameter("cut_radius", 3.8)
	m.ex_yaw = m.face_yaw + PI + 0.05
	m.ex_pitch = 0.28
	m.ex_dist = 4.6
	m._cam_arm_k = 1.0
	m._cam_arm_want = 1.0
	for _i in 45:
		m._cam_arm_k = 1.0
		m._cam_arm_want = 1.0
		await process_frame
	await _shot(vp, "night_beach.png")

	# Night campfire — exact v26 framing (ex_dist 3.6, stand offset).
	var fire: Vector3 = m.island.campfire_pos
	var stand := fire + Vector3(1.05, 0, 0.35)
	stand.y = m._surface(stand.x, stand.z)
	var to_fire := fire - stand
	to_fire.y = 0.0
	m._place(stand, atan2(-to_fire.x, -to_fire.z))
	m.ex_yaw = m.face_yaw + PI + 0.55
	m.ex_pitch = 0.18
	m.ex_dist = 3.6
	m.cam_yaw = m.ex_yaw
	m.cam_pitch = m.ex_pitch
	m.cam_dist = m.ex_dist
	m._cam_arm_k = 1.0
	m._cam_arm_want = 1.0
	for _i in 40:
		m.ex_yaw = m.face_yaw + PI + 0.55
		m.ex_pitch = 0.18
		m.ex_dist = 3.6
		m.cam_yaw = m.ex_yaw
		m.cam_pitch = m.ex_pitch
		m.cam_dist = m.ex_dist
		await process_frame
	await _shot(vp, "night_campfire.png")

	# Night forest path — 7b65342 framing (face toward camera; lantern beside him).
	m.mode = m.Mode.EXPLORE
	m.cam_fixed = false
	m.demo_cam = false
	m.demo_track = []
	var ref_p := Vector3(-0.8, 0, 6.5)
	var lamp_p := ref_p
	var best_ld := 999.0
	for L in m.island.lamps:
		if str(L[1]) != "path":
			continue
		var lp: Vector3 = L[0]
		var ld := Vector2(lp.x - ref_p.x, lp.z - ref_p.z).length()
		if ld < best_ld:
			best_ld = ld
			lamp_p = lp
	var away: Vector3 = Vector3(ref_p.x - lamp_p.x, 0.0, ref_p.z - lamp_p.z)
	if away.length_squared() < 1e-6:
		away = Vector3(-0.6, 0.0, -0.4)
	var forest_p: Vector3 = Vector3(lamp_p.x, 0.0, lamp_p.z) + away.normalized() * 1.35
	forest_p = forest_p.lerp(Vector3(ref_p.x, 0.0, ref_p.z), 0.35)
	forest_p.y = m._surface(forest_p.x, forest_p.z)
	var to_lamp: Vector3 = lamp_p - forest_p
	to_lamp.y = 0.0
	var face_f := atan2(-(forest_p.x - 1.5), -(forest_p.z - 3.0))
	if to_lamp.length_squared() > 1e-6:
		var side := atan2(-to_lamp.x, -to_lamp.z) + PI * 0.62
		face_f = lerp_angle(face_f, side, 0.40)
	m._place(forest_p, face_f)
	m.ex_yaw = m.face_yaw + PI + 0.22
	m.ex_pitch = 0.16
	m.ex_dist = 4.1
	m._cam_arm_k = 1.0
	m._cam_arm_want = 1.0
	m._cam_slide = 0.0
	m._cam_slide_want = 0.0
	m.cam_yaw = m.ex_yaw
	m.cam_pitch = m.ex_pitch
	m.cam_dist = m.ex_dist
	m.cam_target = m.player.global_position + Vector3(0, 0.70, 0) + to_lamp.normalized() * 0.15
	m.island.foliage_mat.set_shader_parameter("cut_radius", 4.5)
	m.island.leaf_mat.set_shader_parameter("cut_radius", 4.5)
	m.island.static_mat.set_shader_parameter("cut_radius", 4.5)
	print("FOREST lamp=", lamp_p, " boy=", forest_p, " dist=", forest_p.distance_to(Vector3(lamp_p.x, forest_p.y, lamp_p.z)))
	for _i in 55:
		m.ex_yaw = m.face_yaw + PI + 0.22
		m.ex_pitch = 0.16
		m.ex_dist = 4.1
		m.cam_yaw = m.ex_yaw
		m.cam_pitch = m.ex_pitch
		m.cam_dist = m.ex_dist
		m.cam_target = m.player.global_position + Vector3(0, 0.70, 0) + to_lamp.normalized() * 0.15
		m._cap_night_omnis()
		m._update_path_lamp_pool()
		await process_frame
	await _shot(vp, "night_forest_path.png")

	# Night dock
	m._place(Vector3(0.8, 0, m.island.dock_start_z + 1.5), 0.0)
	if m.mode != m.Mode.VIEW:
		m._toggle_view()
	m.view_yaw = 0.55
	m.view_pitch = 0.20
	m.view_dist = 36.0
	for _i in 40:
		await process_frame
	await _shot(vp, "night_dock.png")

	print("V27_SHOTS_DONE")
	quit(0)


## Mid-segment of the lighthouse fence path (paths[1]) — rope left when facing the tower.
func _lighthouse_climb_spot(m) -> Vector3:
	var pl: Array = m.island.paths[1]
	var a: Vector2 = pl[mini(3, pl.size() - 2)]
	var b: Vector2 = pl[mini(4, pl.size() - 1)]
	var xz: Vector2 = a.lerp(b, 0.55)
	var n := (b - a).normalized().orthogonal() * -0.15
	var p := Vector3(xz.x + n.x, 0.0, xz.y + n.y)
	p.y = m._surface(p.x, p.z)
	return p


func _set_tod(m, tod: String) -> void:
	if tod == "day":
		if m.night_on:
			m.night_btn.pressed.emit()
			for _i in 80:
				await process_frame
		m.night_k = 0.0
		m._update_night(0.0, true)
	elif tod == "night":
		if not m.night_on:
			m.night_btn.pressed.emit()
			for _i in 90:
				await process_frame
		m.night_k = 1.0
		m._update_night(0.0, true)
	m._cap_night_omnis()
	m._update_path_lamp_pool()
	if m.night_fx and m.camera and m.sun:
		m.night_fx.apply(m.night_k, m.camera.global_position, m.sun.global_basis.z.normalized(), 0.05)
	for _i in 15:
		m._cap_night_omnis()
		m._update_path_lamp_pool()
		if m.night_fx and m.camera and m.sun:
			m.night_fx.apply(m.night_k, m.camera.global_position, m.sun.global_basis.z.normalized(), 0.05)
		await process_frame


func _shot(vp: Viewport, name: String) -> void:
	var m = root.get_child(root.get_child_count() - 1)
	if m and m.get("night_k") != null and float(m.night_k) > 0.5:
		m._cap_night_omnis()
		m._update_path_lamp_pool()
		if m.night_fx and m.camera and m.sun:
			m.night_fx.apply(m.night_k, m.camera.global_position, m.sun.global_basis.z.normalized(), 0.05)
	await process_frame
	await process_frame
	var img: Image = vp.get_texture().get_image()
	img.save_png("%s/%s" % [OUT, name])
	print("WROTE ", name)
