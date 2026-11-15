extends SceneTree
## One-shot evidence for the rebuild gates.
##   R42_PASS=shots|rest|throw|ruler|latency|drag|occ
##   xvfb-run -a godot --path . --fixed-fps 30 -s res://test/pass.gd


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	var mode := OS.get_environment("R42_PASS")
	var game := (load("res://core/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 20:
		await process_frame
	game.night = false
	game._apply_night()
	if mode == "shots":
		await _shots(game)
	elif mode == "rest":
		await _rest(game)
	elif mode == "throw":
		await _throw(game)
	elif mode == "ruler":
		await _ruler(game)
	elif mode == "latency":
		await _latency(game)
	elif mode == "drag":
		await _drag(game)
	elif mode == "occ":
		await _occ(game)
	else:
		print("UNKNOWN_PASS ", mode)
		quit(1)
		return
	print("PASS_DONE ", mode)
	quit(0)


func _shots(game: Node) -> void:
	var ends := IslandData.dock_ends()
	var dir := _dir("m6")
	var hut := _find(game, "Hut")
	var hammock := _find(game, "Hammock")
	var hut_spot := Vector3(2.2, 0.4, ends.x + 3.0)
	var hammock_spot := Vector3(4.0, 0.4, ends.x + 4.0)
	if hut != null:
		hut_spot = hut.global_position + Vector3(-1.6, 0.0, 2.2)
	if hammock != null:
		hammock_spot = hammock.global_position + Vector3(-1.8, 0.0, 1.6)
	var spots := {
		"spawn": Vector3(0.0, Constants.DECK_Y, ends.y + 1.3),
		"pier": Vector3(0.2, 0.0, ends.x + 0.6),
		"hut": hut_spot,
		"hammock": hammock_spot,
	}
	for name in ["spawn", "pier", "hut", "hammock"]:
		var spot: Vector3 = spots[name]
		if name != "spawn":
			var gy: float = game.ground.height(spot.x, spot.z)
			if gy > -2.0:
				spot.y = gy
		await _place(game, spot, PI)
		var cam: Camera3D = game.rig.cam
		game.rig.set_process(false)
		if name == "hut" or name == "hammock":
			cam.global_position = spot + Vector3(-3.2, 2.6, 3.4)
			cam.look_at(spot + Vector3(1.2, 1.3, -0.4), Vector3.UP)
		else:
			cam.global_position = spot + Vector3(-5.5, 5.2, -7.5)
			cam.look_at(spot + Vector3(1.5, 1.2, 4.0), Vector3.UP)
		for _i in 6:
			await process_frame
		_save(game, dir + "/v42_%s.png" % name)
		game.rig.set_process(true)
	var face_at := Vector3(0.0, Constants.DECK_Y, ends.y + 1.3)
	await _place(game, face_at, PI)
	game.rig.set_process(false)
	var face_cam: Camera3D = game.rig.cam
	face_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	face_cam.global_position = face_at + Vector3(0.0, 1.15, 1.35)
	face_cam.look_at(face_at + Vector3(0, 0.95, 0), Vector3.UP)
	for _i in 6:
		await process_frame
	_save(game, dir + "/face_lod.png")
	game.rig.set_process(true)


func _rest(game: Node) -> void:
	var dir := _dir("m4")
	var wanted := ["Bench", "Lounger", "Hammock", "Towel"]
	for name in wanted:
		var item := _find(game, name)
		if item == null:
			print("MISSING_SEAT ", name)
			continue
		game.fader.enabled = false
		await game._begin_rest(item)
		_frame_rest(game)
		for _i in 4:
			await process_frame
		print("REST_CLIP ", name, " ", game.player.boy._clip, " yaw ", game.player.face_yaw)
		_save(game, dir + "/%s_idle.png" % name)
		var kind := str(item.get_meta("kind", ""))
		if kind == "bench" or kind == "log":
			game._begin_lie()
			for _i in 8:
				await process_frame
			_frame_rest(game)
			await process_frame
			_save(game, dir + "/%s_lie.png" % name)
		await game._end_rest()
		print("REST_OK ", name)


func _throw(game: Node) -> void:
	var dir := _dir("m5")
	var ends := IslandData.dock_ends()
	var spot := Vector3(0.0, Constants.DECK_Y, ends.y + 1.3)
	await _place(game, spot, 0.0)
	await _throw_keys(game, dir, "stand", "throw_stand")
	await _throw_keys(game, dir, "crouch", "throw_crouch")
	game._crouch = false
	game._throw()
	for _i in 16:
		await process_frame
	_save(game, dir + "/throw_stand.png")
	await _until_throw_done(game)
	_save(game, dir + "/throw_stand_water.png")
	print("THROW_BANNER ", game.hud.banner.text)
	print("THROW_RECORD ", game.hud.record.text)
	await _place(game, spot, 0.0)
	game._crouch = true
	game._throw()
	for _i in 16:
		await process_frame
	_save(game, dir + "/throw_crouch.png")
	await _until_throw_done(game)
	print("THROW_CROUCH ", game.hud.banner.text)


func _ruler(game: Node) -> void:
	var dir := _dir("a2")
	var ends := IslandData.dock_ends()
	var spots: Array[Vector3] = []
	spots.append(Vector3(0.0, Constants.DECK_Y, ends.y + 1.6))
	for i in 8:
		var z := lerpf(ends.y + 2.0, ends.x + 0.4, float(i) / 7.0)
		spots.append(Vector3(0.15, 0.0, z))
	spots.append(Vector3(2.0, 0.0, 3.5))
	spots.append(Vector3(4.5, 0.0, 1.0))
	spots.append(Vector3(-3.0, 0.0, 2.0))
	spots.append(Vector3(-5.5, 0.0, ends.x + 6.0))
	spots.append(Vector3(1.0, 0.0, ends.x + 5.0))
	spots.append(Vector3(6.0, 0.0, -1.0))
	spots.append(Vector3(-6.0, 0.0, 1.5))
	for i in 10:
		var z := lerpf(ends.x + 2.0, 6.0, float(i) / 9.0)
		var x := sin(float(i) * 0.7) * 3.0
		spots.append(Vector3(x, 0.0, z))
	for i in 8:
		spots.append(Vector3(-2.0 + float(i) * 0.7, 0.0, 1.5 + float(i % 3)))
	var rows: Array[String] = []
	var n := 0
	for spot in spots:
		var p: Vector3 = spot
		if absf(p.y) < 0.01:
			p.y = game.ground.height(p.x, p.z)
		if p.y < -0.3:
			continue
		var yaw := 0.4 if n % 5 == 0 else PI
		await _place(game, p, yaw)
		if n % 7 == 0:
			game.player.boy.set_speed(0.0)
		elif n % 6 == 0:
			game.player.boy.set_speed(2.2)
		else:
			game.player.boy.set_speed(0.64)
		for _i in 12:
			await process_frame
		var foot := _foot(game)
		var gy: float = game.ground.height(foot.x, foot.z)
		var ruler := _make_ruler(gy)
		ruler.position = Vector3(foot.x, 0, foot.z)
		root.add_child(ruler)
		var side := Vector3(cos(yaw), 0, -sin(yaw))
		game.rig.set_process(false)
		var cam: Camera3D = game.rig.cam
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 0.46
		cam.global_position = Vector3(foot.x, gy + 0.08, foot.z) + side * 1.1
		cam.look_at(Vector3(foot.x, gy + 0.08, foot.z), Vector3.UP)
		var gap := 0.0
		if game.player.boy.ik != null:
			gap = game.player.boy.ik.sole_gap[0] * 100.0
		game.hud.banner.text = "间隙 %.2f cm" % gap
		for _i in 3:
			await process_frame
		var path := dir + "/foot_%02d.png" % n
		_save(game, path)
		rows.append("%02d gap_cm=%.2f y=%.3f %s" % [n, gap, p.y, path])
		ruler.queue_free()
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		game.rig.set_process(true)
		n += 1
	var log := FileAccess.open(dir + "/ruler.log", FileAccess.WRITE)
	for row in rows:
		log.store_line(row)
		print("RULER ", row)
	log.close()
	print("RULER_N ", n)


func _latency(game: Node) -> void:
	var ends := IslandData.dock_ends()
	await _place(game, Vector3(0.2, Constants.DECK_Y, ends.y + 2.2), 0.0)
	for _i in 10:
		await process_frame
	var origin: Vector3 = game.player.global_position
	var t0 := Time.get_ticks_usec()
	var down := InputEventScreenTouch.new()
	down.index = 3
	down.pressed = true
	down.position = game.joy._origin
	Input.parse_input_event(down)
	await process_frame
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = game.joy._origin + Vector2(0, -70)
	drag.relative = Vector2(0, -70)
	drag.velocity = Vector2(0, -400)
	Input.parse_input_event(drag)
	var moved := -1.0
	for i in 20:
		await process_frame
		var d := Vector2(game.player.global_position.x - origin.x, game.player.global_position.z - origin.z).length()
		if d > 0.01:
			moved = float(Time.get_ticks_usec() - t0) / 1000.0
			print("LATENCY_MS %.1f frames=%d dist_cm=%.2f stick=%s" % [moved, i + 1, d * 100.0, game.joy.value])
			break
	if moved < 0.0:
		print("LATENCY_FAIL stick=%s speed=%.3f" % [game.joy.value, game.player.speed])
	else:
		print("LATENCY_OK")


func _drag(game: Node) -> void:
	game.dbg.on = true
	game.dbg.visible = true
	var ends := IslandData.dock_ends()
	await _place(game, Vector3(0.15, Constants.DECK_Y, ends.y + 2.4), 0.0)
	for _i in 15:
		await process_frame
	var down := InputEventScreenTouch.new()
	down.index = 4
	down.pressed = true
	down.position = game.joy._origin
	Input.parse_input_event(down)
	await process_frame
	var drag := InputEventScreenDrag.new()
	drag.index = 4
	drag.position = game.joy._origin + Vector2(0, -68)
	drag.relative = Vector2(0, -68)
	Input.parse_input_event(drag)
	var dir := _dir("drag")
	for i in 40:
		await process_frame
		if i == 8:
			_save(game, dir + "/d41_a.png")
			_prims("A")
		elif i == 22:
			_save(game, dir + "/d41_b.png")
			_prims("B")
	var up := InputEventScreenTouch.new()
	up.index = 4
	up.pressed = false
	up.position = drag.position
	Input.parse_input_event(up)
	for i in 28:
		await process_frame
		if i == 24:
			_save(game, dir + "/d41_c.png")
			_prims("C")
	print("DRAG_STICK ", game.joy.value, " speed ", game.player.speed)


func _occ(game: Node) -> void:
	var ends := IslandData.dock_ends()
	# Inland of the hut, looking out to sea, so the hut sits on the right and the palm row on the left.
	var spot := Vector3(0.35, 0.0, ends.x + 3.3)
	spot.y = game.ground.height(spot.x, spot.z)
	await _place(game, spot, 0.0)
	for _i in 12:
		await process_frame
	game.rig.set_process(false)
	var cam: Camera3D = game.rig.cam
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 52.0
	cam.global_position = Vector3(-0.15, spot.y + 1.55, ends.x + 5.6)
	cam.look_at(Vector3(1.1, spot.y + 0.85, ends.x + 0.4), Vector3.UP)
	for _i in 4:
		await process_frame
	var dir := _dir("m3")
	_save(game, dir + "/occ_match_on.png")
	game.fader.enabled = false
	for item in game.props.items:
		item.set_target(1.0)
		item.alpha = 1.0
		item.tick(0.01)
	for _i in 3:
		await process_frame
	_save(game, dir + "/occ_match_off.png")
	print("OCC_MATCH")


func _frame_rest(game: Node) -> void:
	game.rig.set_process(false)
	var cam: Camera3D = game.rig.cam
	var p: Vector3 = game.player.global_position
	var yaw: float = game.player.face_yaw
	var face := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var side := Vector3(face.z, 0.0, -face.x)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.global_position = p + side * 3.4 + Vector3(0, 1.45, 0) + face * 1.1
	cam.look_at(p + Vector3(0, 0.55, 0), Vector3.UP)


func _throw_keys(game: Node, dir: String, tag: String, clip: String) -> void:
	var boy: BoyVisual = game.player.boy
	if boy.play_clip(clip, 0.0) == "":
		print("THROW_CLIP_MISSING ", clip)
		return
	if boy.ik != null:
		boy.ik.paused = true
	game.rig.set_process(false)
	var cam: Camera3D = game.rig.cam
	var p: Vector3 = game.player.global_position
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.global_position = p + Vector3(2.4, 1.45, 2.6)
	cam.look_at(p + Vector3(0, 0.9, 0), Vector3.UP)
	var times := [0.0, 0.18, 0.36, 0.50, 0.72, 1.05]
	var names := ["windup", "load", "whip", "release", "follow", "finish"]
	for i in times.size():
		boy.anim.seek(times[i], true)
		boy.anim.pause()
		for _k in 3:
			await process_frame
		_save(game, dir + "/throw_%s_%s.png" % [tag, names[i]])
	game.rig.set_process(true)


func _until_throw_done(game: Node) -> void:
	for _i in 160:
		await process_frame
		if not game._throwing and game.hud.banner.text != "" and game.hud.banner.text != "出手":
			return
	print("THROW_TIMEOUT ", game.hud.banner.text)


func _place(game: Node, spot: Vector3, yaw: float) -> void:
	game.player.locked = true
	game.player.use_anchor = true
	game.player.anchor = spot
	game.player.global_position = spot
	game.player.face_yaw = yaw
	game.player.rotation.y = yaw
	game.player.velocity = Vector3.ZERO
	game.player.speed = 0.0
	for _i in 4:
		await process_frame
	game.player.locked = false
	game.player.use_anchor = false


func _find(game: Node, name: String) -> Fadable:
	for item in game.props.items:
		if item.name == name:
			return item
	return null


func _foot(game: Node) -> Vector3:
	var skel: Skeleton3D = game.player.boy.skel
	var b := skel.find_bone("mixamorig_RightFoot")
	if b < 0:
		b = skel.find_bone("mixamorig_LeftFoot")
	return (skel.global_transform * skel.get_bone_global_pose(b)).origin


func _make_ruler(gy: float) -> Node3D:
	var root_n := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 11:
		var y := gy + float(i) * 0.02
		var wide := 0.06 if i == 0 or i == 10 else 0.035
		var col := Color(0.9, 0.15, 0.12) if i == 0 else Color(0.95, 0.95, 0.9)
		_box(st, Vector3(0, y, 0), Vector3(0.008, 0.004, wide), col)
	_box(st, Vector3(0, gy + 0.10, 0), Vector3(0.006, 0.20, 0.006), Color(0.95, 0.95, 0.9))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	root_n.add_child(mi)
	return root_n


func _box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var c := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, h.y, -h.z), center + Vector3(-h.x, h.y, -h.z),
		center + Vector3(-h.x, -h.y, h.z), center + Vector3(h.x, -h.y, h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
	]
	_quad(st, c[0], c[1], c[2], c[3], col)
	_quad(st, c[4], c[7], c[6], c[5], col)
	_quad(st, c[0], c[4], c[5], c[1], col)
	_quad(st, c[2], c[6], c[7], c[3], col)
	_quad(st, c[0], c[3], c[7], c[4], col)
	_quad(st, c[1], c[5], c[6], c[2], col)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(v)


func _dir(name: String) -> String:
	var dir := ProjectSettings.globalize_path("res://../screenshots/v42/" + name)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func _save(game: Node, path: String) -> void:
	var img := game.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("WROTE ", path)


func _prims(tag: String) -> void:
	var n := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	print("PRIMS_%s %d" % [tag, n])
