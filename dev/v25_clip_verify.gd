extends SceneTree
## Bone error check (<2 cm vs GLB-recomputed targets) + side-by-side ref/game shots.
## Ref = same boy+prop transform, island props only (clips_preview not in upload zip).

const OUT := "/workspace/screenshots/v25/after/verify"
const W := 390
const H := 844
const TOL := 0.02
const SCALE := 1.35
const FLOOR_OFF := 0.00837


func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	DisplayServer.window_set_size(Vector2i(W, H))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(W, H)
	DirAccess.make_dir_recursive_absolute(OUT)

	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 70:
		await process_frame
	m.demo_mode = true
	m.demo_cam = true
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
	m.ui_root.visible = false
	if m.zzz and is_instance_valid(m.zzz):
		m.zzz.visible = false

	var lines: PackedStringArray = PackedStringArray()
	var all_ok := true
	for spec in [
		["bench", "长椅", "bench_sit_idle", 4.0],
		["log", "坐木", "log_sit_idle", 4.0],
		["hammock", "", "hammock_sleep", 4.0],
	]:
		var r: Dictionary = await _check_clip(m, vp, String(spec[0]), String(spec[1]), String(spec[2]), float(spec[3]))
		lines.append(String(r["line"]))
		if not bool(r["ok"]):
			all_ok = false
		print(r["line"])

	for spec2 in [
		["bench", "长椅", "bench_sit_enter", 2.8],
		["bench", "长椅", "bench_sit_idle", 4.0],
		["bench", "长椅", "bench_sit_exit", 1.2],
		["log", "坐木", "log_sit_enter", 2.8],
		["log", "坐木", "log_sit_idle", 4.0],
		["log", "坐木", "log_sit_exit", 1.2],
		["hammock", "", "hammock_enter", 4.4],
		["hammock", "", "hammock_sleep", 4.0],
		["hammock", "", "hammock_exit", 1.6],
	]:
		await _sbs(m, vp, String(spec2[0]), String(spec2[1]), String(spec2[2]), float(spec2[3]))

	var f := FileAccess.open(OUT + "/BONE_ERROR.txt", FileAccess.WRITE)
	for L in lines:
		f.store_line(L)
	f.store_line("OVERALL %s" % ("PASS" if all_ok else "FAIL"))
	f.close()
	print("VERIFY_DONE ", "PASS" if all_ok else "FAIL")
	quit(0 if all_ok else 1)


func _pick_seat(m, want: String) -> int:
	var best := 0
	var best_d := -1.0
	for i in m.island.seats.size():
		if String(m.island.seats[i]["name"]) != want:
			continue
		if want == "坐木":
			var d: float = (m.island.seats[i]["top"] as Vector3).distance_to(m.island.campfire_pos)
			if d > best_d:
				best_d = d
				best = i
		else:
			return i
	return best


func _bone_from_ap(m, clip: String, tsec: float, bone: String) -> Vector3:
	## Skeleton-space bone translation from AnimationPlayer, then model xf (rotY PI + scale).
	if m.boy.ap == null or not m.boy.ap.has_animation(clip):
		return Vector3.ZERO
	var a: Animation = m.boy.ap.get_animation(clip)
	for i in a.get_track_count():
		var path := String(a.track_get_path(i))
		if path.find(bone) < 0:
			continue
		if a.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var p: Vector3 = a.position_track_interpolate(i, tsec)
		# model: rotY(PI) * scale + floor offset (hips only get floor offset in boy.gd)
		var local := Vector3(-p.x, p.y, -p.z) * SCALE
		if bone == "Hips":
			local += Vector3(0, FLOOR_OFF, 0)
		return local
	return Vector3.ZERO


func _check_clip(m, vp, tag: String, seat_name: String, clip: String, tsec: float) -> Dictionary:
	if tag == "hammock":
		m._begin_rest("sleep")
	else:
		var bi := _pick_seat(m, seat_name)
		var st: Dictionary = m.island.seats[bi]
		m.seat_i = bi
		m.seat_ap = st["approach"]
		m.seat_face = st["face"]
		m._begin_rest("seat")
	m.rest_frozen = true
	if not m.rest_use_clips:
		return {"ok": false, "line": "FAIL %s clips inactive" % tag}
	m.rest_phase = 4
	m._play_rest_idle_clip()
	m.boy.seek_prop_clip(tsec)
	if tag == "hammock":
		m._sync_hammock_cloth_to_boy()
	m.boy._tick(0.0)
	for i in 8:
		await process_frame

	var pxf: Transform3D = m.rest_prop_xf
	var inv := pxf.affine_inverse()
	var hips_w: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
	var lk: Vector3 = m.boy.lie_bone_world("mixamorig_LeftLeg")
	var rk: Vector3 = m.boy.lie_bone_world("mixamorig_RightLeg")
	var la: Vector3 = m.boy.lie_bone_world("mixamorig_LeftFoot")
	var ra: Vector3 = m.boy.lie_bone_world("mixamorig_RightFoot")
	var hips_p := inv * hips_w
	var knee_p := inv * (0.5 * (lk + rk))
	var foot_p := inv * (0.5 * (la + ra))

	# Expected hips in prop frame: boy node at root_pos/yaw, hips = node_xf * model_local_hips
	var cinfo: Dictionary = m.rest_align.get("clips", {}).get(clip, {})
	# Idle clips share enter root
	var enter_key := clip.replace("_idle", "_enter").replace("_sleep", "_enter")
	if tag == "hammock" and clip == "hammock_sleep":
		enter_key = "hammock_enter"
	var einfo: Dictionary = m.rest_align.get("clips", {}).get(enter_key, cinfo)
	var rp: Array = einfo.get("root_pos_prop", [0, 0, -0.5])
	var yaw_deg := float(einfo.get("root_yaw_deg", 0.0))
	var root_local := Vector3(float(rp[0]), float(rp[1]), float(rp[2]))
	# Expected bones: re-place from alignment.json root, then re-sample the live skeleton
	# (child bone AP tracks are parent-local — not usable as world targets).
	var hips_model := _bone_from_ap(m, clip, tsec, "Hips")
	var node_yaw := deg_to_rad(yaw_deg) + PI
	var hips_exp := root_local + Basis(Vector3.UP, node_yaw) * hips_model
	# Independent re-apply of authored root, then read skeleton (must match live).
	var pos_chk := pxf * root_local
	var yaw_chk := pxf.basis.get_euler().y + node_yaw
	var saved_xf: Transform3D = m.boy.global_transform
	m.boy.global_transform = Transform3D(Basis(Vector3.UP, yaw_chk), pos_chk)
	m.boy.seek_prop_clip(tsec)
	m.boy._tick(0.0)
	for _i in 3:
		await process_frame
	var hips_re: Vector3 = inv * m.boy.lie_bone_world("mixamorig_Hips")
	var knee_re: Vector3 = inv * (0.5 * (m.boy.lie_bone_world("mixamorig_LeftLeg") + m.boy.lie_bone_world("mixamorig_RightLeg")))
	var foot_re: Vector3 = inv * (0.5 * (m.boy.lie_bone_world("mixamorig_LeftFoot") + m.boy.lie_bone_world("mixamorig_RightFoot")))
	m.boy.global_transform = saved_xf
	m.boy.seek_prop_clip(tsec)
	m.boy._tick(0.0)
	for _i2 in 2:
		await process_frame
	# Re-measure live after restore (should equal first sample if placement matched).
	hips_p = inv * m.boy.lie_bone_world("mixamorig_Hips")
	knee_p = inv * (0.5 * (m.boy.lie_bone_world("mixamorig_LeftLeg") + m.boy.lie_bone_world("mixamorig_RightLeg")))
	foot_p = inv * (0.5 * (m.boy.lie_bone_world("mixamorig_LeftFoot") + m.boy.lie_bone_world("mixamorig_RightFoot")))
	var err_h: float = maxf(hips_p.distance_to(hips_exp), hips_p.distance_to(hips_re))
	var err_k: float = knee_p.distance_to(knee_re)
	var err_f: float = foot_p.distance_to(foot_re)
	var err: float = maxf(err_h, maxf(err_k, err_f))
	var ok := err < TOL
	# Extra geometric sanity vs authored prop dims
	if tag == "bench" or tag == "log":
		ok = ok and knee_p.z < -0.10 and foot_p.y > -0.02 and hips_p.y > 0.30
	if tag == "hammock":
		ok = ok and m.island.hammock_use_v25 and m.island.hammock_clip == "hammock_sleep"
		var ah := 0.0
		if m.island.hammock_cloth_mi:
			ah = m.island.hammock_cloth_mi.get_aabb().size.y
		ok = ok and ah > 0.5

	var line := "%s %s hips_err=%.4fm knee_err=%.4fm ankle_err=%.4fm (tol %.3f) hips_prop=%s exp=%s knee_prop=%s foot_prop=%s" % [
		("PASS" if ok else "FAIL"), tag, err_h, err_k, err_f, TOL, hips_p, hips_exp, knee_p, foot_p]
	await _cam_side(m, vp, tag, "check_%s" % tag, pxf, m.boy.lie_bone_world("mixamorig_Hips"))
	m._finish_rest_exit()
	return {"ok": ok, "line": line}


func _cam_side(m, vp, tag: String, name: String, pxf: Transform3D, look: Vector3) -> void:
	# Bench/log: look along +X to show seat depth (−Z) and shins past the front edge.
	# Hammock: look along +Z (inland) — +X is the span, so end-on makes cloth a thin line.
	var side: Vector3
	var dist := 2.55
	var pitch := 0.10
	if tag == "hammock":
		side = pxf.basis.z.normalized()
		dist = 3.2
		pitch = 0.22
		# Aim at prop origin + slight down so cradle fills the frame.
		look = pxf.origin + pxf.basis * Vector3(0.0, -0.35, 0.0)
	else:
		side = pxf.basis.x.normalized()
	m.demo_cam = true
	m.cam_fixed = true
	m.cam_target = look
	m.cam_yaw = atan2(side.x, side.z)
	m.cam_pitch = pitch
	m.cam_dist = dist
	m.view_dist = dist
	for i in 5:
		m._apply_camera()
		await process_frame
	var img: Image = vp.get_texture().get_image()
	if img:
		img.save_png("%s/%s.png" % [OUT, name])


func _sbs(m, vp, tag: String, seat_name: String, clip: String, tsec: float) -> void:
	if tag == "hammock":
		m._begin_rest("sleep")
	else:
		var bi := _pick_seat(m, seat_name)
		var st: Dictionary = m.island.seats[bi]
		m.seat_i = bi
		m.seat_ap = st["approach"]
		m.seat_face = st["face"]
		m._begin_rest("seat")
	m.rest_frozen = true
	if clip.ends_with("enter"):
		m.rest_phase = 1
		m._play_rest_enter_clip()
	elif clip.ends_with("exit"):
		m.rest_phase = 6
		m._play_rest_exit_clip()
	else:
		m.rest_phase = 4
		m._play_rest_idle_clip()
	m.boy.seek_prop_clip(tsec)
	if tag == "hammock":
		m._sync_hammock_cloth_to_boy()
	m.boy._tick(0.0)
	for i in 5:
		await process_frame
	var pxf: Transform3D = m.rest_prop_xf
	var hips: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
	await _cam_side(m, vp, tag, "game_%s" % clip, pxf, hips)
	var game_img := Image.load_from_file("%s/game_%s.png" % [OUT, clip])

	# Reference: hide terrain / foliage clutter, keep props + boy (authored alignment).
	# Spawns are named after the glb (bench_v25 / log_v25); hammock lives under hammock_node.
	var hidden: Array = []
	if m.island.terrain_mi:
		m.island.terrain_mi.visible = false
		hidden.append(m.island.terrain_mi)
	for c in m.island.get_children():
		if c == m.island.hammock_node:
			continue
		var nm := String(c.name).to_lower()
		var keep := nm.find("bench") >= 0 or nm.find("log") >= 0 or nm.find("hammock") >= 0
		if not keep and c is Node3D:
			# Duplicate log spawns get @Node3D@N names — keep by mesh child name.
			for mi in c.find_children("*", "MeshInstance3D", true, false):
				var mn := String(mi.name).to_lower()
				if mn.find("bench") >= 0 or mn.find("log") >= 0 or mn.find("hammock") >= 0 or mn.find("cloth") >= 0:
					keep = true
					break
		if not keep and c is Node3D:
			if c.visible:
				c.visible = false
				hidden.append(c)
	for i in 4:
		m._apply_camera()
		await process_frame
	var ref: Image = vp.get_texture().get_image()
	if ref:
		ref.save_png("%s/ref_%s.png" % [OUT, clip])
	for n in hidden:
		if is_instance_valid(n):
			n.visible = true

	var ref_img := Image.load_from_file("%s/ref_%s.png" % [OUT, clip])
	if game_img and ref_img:
		if game_img.get_format() != Image.FORMAT_RGBA8:
			game_img.convert(Image.FORMAT_RGBA8)
		if ref_img.get_format() != Image.FORMAT_RGBA8:
			ref_img.convert(Image.FORMAT_RGBA8)
		var strip := Image.create(W * 2, H, false, Image.FORMAT_RGBA8)
		# Left = authored-aligned isolation, right = in-island game view (same pose/time).
		strip.blit_rect(ref_img, Rect2i(0, 0, mini(W, ref_img.get_width()), mini(H, ref_img.get_height())), Vector2i.ZERO)
		strip.blit_rect(game_img, Rect2i(0, 0, mini(W, game_img.get_width()), mini(H, game_img.get_height())), Vector2i(W, 0))
		strip.save_png("%s/sbs_%s.png" % [OUT, clip])
		print("SBS ", clip)
	m._finish_rest_exit()
