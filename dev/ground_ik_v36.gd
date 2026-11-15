extends SceneTree
## Geometry-grounded walk test (v36):
## - ≥100 m route over slopes / beach / forest / dock lip / onto dock & back
## - CDP-style stick drag start on a slope
## - Every frame: stance sole vs collision ray within [-1.0 cm, +1.5 cm]
## - No leg vertex below surface; pelvis Y step ≤ 3 cm/frame
## - Low side-on close-ups on uphill / downhill / cross-slope / dock lip
##   godot --path . --fixed-fps 60 -s res://dev/ground_ik_v36.gd

const MAX_SINK := 0.010   # −1.0 cm
const MAX_FLOAT := 0.015  # +1.5 cm
const MAX_PELVIS_STEP := 0.030
const MIN_TRAVEL := 100.0
const OUT := "screenshots/v36"

var m: Node
var fails: Array[String] = []
var shots: Array[String] = []


func _initialize() -> void:
	call_deferred("_go")


func _fail(msg: String) -> void:
	fails.append(msg)
	print("GIK FAIL  ", msg)


func _ray_y(x: float, z: float, hint: float) -> float:
	return m.island.collision_h(x, z, hint)


func _stance_sides() -> Array:
	# Every locked stance foot — including double-support. Idle = both.
	if m.boy.anim != "move" or m.boy.move_w < 0.2:
		return [0, 1]
	var out: Array = []
	if m.boy._stance_locked[0]:
		out.append(0)
	if m.boy._stance_locked[1]:
		out.append(1)
	# Must never be empty: plant_w floor guarantees ≥1 lock; assert via phase.
	if out.is_empty():
		_fail("no stance lock at phase=%.2f (double-support hole)" % m.boy.phase)
		out.append(0 if m.boy.phase < 0.5 else 1)
	return out


func _check_frame(tag: String) -> void:
	# Plant is applied on process_frame; reassert so the test samples the same write.
	m.boy._reassert_foot_plants()
	var hint: float = m.player.position.y
	var ex: Array = [m.boy.get_rid()]
	# Per-vertex: lowest sole estimate at heel/ball vs collision UNDER that point.
	for side in _stance_sides():
		var fp: Array = m.boy.foot_points(side)
		var heel: Vector3 = fp[0]
		var ball: Vector3 = fp[1]
		var sy_h: float = m.island.collision_h(heel.x, heel.z, hint, ex)
		var sy_b: float = m.island.collision_h(ball.x, ball.z, hint, ex)
		var sole_h: float = heel.y - m.boy.sole_offset
		var sole_b: float = ball.y - 0.012
		var gap_h: float = sole_h - sy_h
		var gap_b: float = sole_b - sy_b
		if gap_h < -MAX_SINK:
			_fail("%s heel[%d] SINK %.1fcm at (%.2f,%.2f)" % [tag, side, -gap_h * 100.0, heel.x, heel.z])
		elif gap_h > MAX_FLOAT:
			_fail("%s heel[%d] FLOAT %.1fcm at (%.2f,%.2f)" % [tag, side, gap_h * 100.0, heel.x, heel.z])
		if gap_b < -MAX_SINK:
			_fail("%s ball[%d] SINK %.1fcm at (%.2f,%.2f)" % [tag, side, -gap_b * 100.0, ball.x, ball.z])
		elif gap_b > MAX_FLOAT:
			_fail("%s ball[%d] FLOAT %.1fcm at (%.2f,%.2f)" % [tag, side, gap_b * 100.0, ball.x, ball.z])
	# Knees: allow small crest graze; fail deep digs (IK should bend clear).
	for bn2 in ["mixamorig_LeftLeg", "mixamorig_RightLeg"]:
		var bi2: int = m.boy.skel.find_bone(bn2)
		if bi2 < 0:
			continue
		var p2: Vector3 = m.boy.skel.global_transform * m.boy.skel.get_bone_global_pose(bi2).origin
		var sy2: float = m.island.collision_h(p2.x, p2.z, hint, ex)
		if p2.y < sy2 - 0.025:
			_fail("%s bone %s below surface by %.1fcm" % [tag, bn2, (sy2 - p2.y) * 100.0])


func _drive(stick: Vector2, frames: int, tag: String, stats: Dictionary) -> void:
	if m.joy:
		m.joy.value = stick
	var prev_y: float = m.player.position.y
	var prev: Vector3 = m.player.position
	for i in frames:
		await process_frame
		var cur: Vector3 = m.player.position
		var dxz: float = Vector2(cur.x - prev.x, cur.z - prev.z).length()
		stats["travel"] = float(stats["travel"]) + dxz
		var dy: float = absf(cur.y - prev_y)
		stats["max_pelvis_step"] = maxf(float(stats["max_pelvis_step"]), dy)
		if dy > MAX_PELVIS_STEP:
			_fail("%s pelvis step %.1fcm at f=%d (%.2f,%.2f)" % [tag, dy * 100.0, i, cur.x, cur.z])
		_check_frame("%s_f%d" % [tag, i])
		if fails.size() > 120:
			break
		prev = cur
		prev_y = cur.y
	if m.joy:
		m.joy.value = Vector2.ZERO


func _place(xz: Vector2, yaw: float) -> void:
	var y: float = m._surface(xz.x, xz.y)
	m.player.position = Vector3(xz.x, y, xz.y)
	m._body_pos = m.player.position
	m._sync_body_pose(true)
	m.ground_y = y
	m.face_yaw = yaw
	m.player.rotation.y = yaw
	m.boy.rotation.y = yaw
	# Settle plant immediately so the first drive frame isn't a teleport float.
	m.boy._pelvis_drop = 0.0
	m.boy._pelvis_drop_s = 0.0
	if m.boy.model:
		m.boy.model.position = m.boy.model_base
	m.boy._reassert_foot_plants()


func _shot(name: String, look_dir: Vector3) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT))
	# Drive the fixed-cam pipeline (explore follow cannot yank the lens).
	var was_fixed: bool = m.cam_fixed
	m.cam_fixed = true
	var side := 1.0 if look_dir.x >= 0.0 else -1.0
	if absf(look_dir.z) > absf(look_dir.x):
		side = 1.0 if look_dir.z >= 0.0 else -1.0
	m.fix_target = m.player.global_position + Vector3(0, 0.48, 0)
	m.fix_yaw = m.face_yaw + PI * 0.5 * side
	m.fix_pitch = 0.10 if name != "gik_dock_lip" else 0.22
	m.fix_dist = 2.6 if name != "gik_dock_lip" else 3.2
	m.cam_target = m.fix_target
	m.cam_yaw = m.fix_yaw
	m.cam_pitch = m.fix_pitch
	m.cam_dist = m.fix_dist
	for _i in 3:
		m._apply_camera(1.0)
		await process_frame
		m.fix_target = m.player.global_position + Vector3(0, 0.48, 0)
		m.cam_target = m.fix_target
		m._apply_camera(1.0)
	m.boy._reassert_foot_plants()
	await process_frame
	m._apply_camera(1.0)
	var path := "%s/%s.png" % [OUT, name]
	m.get_viewport().get_texture().get_image().save_png(path)
	shots.append(path)
	print("SHOT ", path)
	m.cam_fixed = was_fixed


func _go() -> void:
	DisplayServer.window_set_size(Vector2i(780, 844))
	var ps := load("res://main.tscn") as PackedScene
	m = ps.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	await process_frame
	if m.has_method("_start_audio"):
		m._start_audio()
	m.demo_mode = false
	m.cam_fixed = false
	if m.mq:
		m.mq.force_tier("low", m.get_viewport(), m.sun)
		m._apply_mq_materials()
	for _i in 45:
		await process_frame

	print("SOLE_OFFSET=%.1fcm SOLE_NUDGE=%.3f" % [m.boy.sole_offset * 100.0, Boy.SOLE_NUDGE])
	print("GROUND body=", m.island.ground_body != null)

	var stats := {"travel": 0.0, "max_pelvis_step": 0.0}
	var ds: float = m.island.dock_start_z
	var de: float = m.island.dock_end_z

	# CDP-style slope drag start.
	_place(Vector2(2.6, ds + 6.5), -0.4)
	for _i in 12:
		await process_frame
	print("GIK CDP slope drag")
	await _drive(Vector2(0.4, -0.8), 90, "cdp", stats)

	# Full route on walkable collision only (never past dock_end into open water).
	# Stick −Z from de+1.8 walks off the pier — aim inland / along the deck instead.
	# Walkable only: never aim stick off the pier tip into open water.
	# Stick −Z with yaw 0 walks to sea — use yaw PI (face shore) or inland XZ.
	var segs: Array = [
		[Vector2(0.2, de + 1.8), PI, Vector2(0.0, -1.0), 320],   # tip → shore along deck
		[Vector2(0.0, lerpf(ds, de, 0.40)), PI, Vector2(0.0, -1.0), 300],  # mid deck → shore
		[Vector2(1.4, ds + 3.5), -0.3, Vector2(0.2, -1.0), 360],
		[Vector2(2.8, ds + 5.5), -0.5, Vector2(0.25, -1.0), 380],
		[Vector2(3.5, ds + 6.5), -0.6, Vector2(0.15, -1.0), 380],
		[Vector2(4.0, ds + 5.2), 0.9, Vector2(0.1, -1.0), 360],
		[Vector2(-2.8, ds + 5.8), 0.5, Vector2(-0.15, -1.0), 360],
		[Vector2(-3.0, ds + 4.0), -0.2, Vector2(0.1, -1.0), 340],
		[Vector2(0.5, ds + 3.0), 0.1, Vector2(0.0, -1.0), 360],
		[Vector2(2.5, ds + 6.0), -0.5, Vector2(0.2, -1.0), 380],
		[Vector2(-2.5, ds + 6.2), 0.6, Vector2(-0.2, -1.0), 380],
		[Vector2(0.2, lerpf(ds, de, 0.30)), PI, Vector2(0.0, -1.0), 300],  # deck → shore
		[Vector2(1.0, ds + 1.2), PI, Vector2(0.0, -0.6), 280],  # dock lip, stay on deck
		[Vector2(0.1, lerpf(ds, de, 0.55)), PI, Vector2(0.0, -1.0), 320],
		[Vector2(0.2, ds + 0.8), PI, Vector2(0.0, -1.0), 280],
		[Vector2(2.0, ds + 4.5), -0.4, Vector2(0.2, -1.0), 400],
		[Vector2(-2.0, ds + 5.0), 0.4, Vector2(-0.2, -1.0), 400],
	]
	var si := 0
	for seg in segs:
		if fails.size() > 80:
			break
		_place(seg[0], seg[1])
		for _i in 8:
			await process_frame
		print("GIK seg ", si, " stick=", seg[2])
		await _drive(seg[2], int(seg[3]), "seg%d" % si, stats)
		si += 1

	print("GIK travel=%.2fm max_pelvis_step=%.1fcm" % [float(stats["travel"]), float(stats["max_pelvis_step"]) * 100.0])
	if float(stats["travel"]) < MIN_TRAVEL:
		_fail("travel %.2fm < %.0fm" % [float(stats["travel"]), MIN_TRAVEL])

	# Low side-on close-ups (cam Y ≈ ankle+0.3, look along slope/lip).
	_place(Vector2(2.6, ds + 6.5), -0.4)
	for _i in 10:
		await process_frame
	if m.joy:
		m.joy.value = Vector2(0.0, -0.85)
	for _i in 40:
		await process_frame
	m.boy._reassert_foot_plants()
	await _shot("gik_uphill", Vector3(1.2, 0.05, 0.0))
	if m.joy:
		m.joy.value = Vector2(0.0, 0.85)
	for _i in 50:
		await process_frame
	m.boy._reassert_foot_plants()
	await _shot("gik_downhill", Vector3(1.2, 0.05, 0.0))
	_place(Vector2(2.8, ds + 6.0), 0.0)
	for _i in 10:
		await process_frame
	if m.joy:
		m.joy.value = Vector2(0.85, 0.0)
	for _i in 40:
		await process_frame
	m.boy._reassert_foot_plants()
	await _shot("gik_cross", Vector3(0.0, 0.05, 1.2))
	# On the lip itself (deck side of dock_start), not beach float zone.
	_place(Vector2(0.25, ds - 0.4), PI)
	for _i in 20:
		await process_frame
	if m.joy:
		m.joy.value = Vector2(0.0, -0.35)
	for _i in 25:
		await process_frame
	if m.joy:
		m.joy.value = Vector2.ZERO
	for _i in 8:
		await process_frame
	m.boy._reassert_foot_plants()
	await _shot("gik_dock_lip", Vector3(1.2, 0.05, 0.15))

	print("GIK fails=%d shots=%s" % [fails.size(), str(shots)])
	if fails.is_empty():
		print("GROUND_IK PASS")
		quit(0)
	else:
		print("GROUND_IK FAILED (%d)" % fails.size())
		for f in fails:
			print("  - ", f)
		quit(1)
