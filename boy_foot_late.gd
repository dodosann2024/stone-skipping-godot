extends Node
## v37 FramePipelineTail — runs on SceneTree.process_frame AFTER every node's
## _process. Order: (boy already planted drawable poses) → blob → camera/cutout
## → HUD/probes from the same sole verts. No second plant / contact_lift.

var frames := 0
var last_gap_cm := 0.0
var last_ankle_y := 0.0
var last_hit_y := 0.0
var last_blob_xz := Vector2.ZERO
var last_stance_mid := Vector3.ZERO


func _ready() -> void:
	set_process(false)
	get_tree().process_frame.connect(_on_process_frame)


func _on_process_frame() -> void:
	frames += 1
	var b := get_parent()
	if b == null:
		return
	# Final drawable plant HERE — last writer before skin/HUD (web AnimationTree
	# can otherwise advance after boy._process and lift the mixer feet again).
	if b.has_method("_update_foot_ik"):
		b._update_foot_ik(0.0)
	if b.has_method("_update_blob"):
		b._update_blob()
	_record_blob(b)
	var main := b.get_parent()
	if main == null:
		return
	# Camera + foliage AFTER plant (FollowCamera gate).
	if main.get("follow_cam") != null:
		var fc = main.follow_cam
		if fc != null and fc.has_method("finalize"):
			fc.finalize()
	elif main.has_method("_finalize_view"):
		main._finalize_view()
	if main.has_method("_upload_foot_ao"):
		main._upload_foot_ao()
	if main.has_method("_export_ground_probe"):
		main._export_ground_probe()
	if b.skel == null:
		return
	var bi: int = b.skel.find_bone("mixamorig_LeftFoot")
	if bi < 0:
		return
	var ank: Vector3 = b.skel.global_transform * b.skel.get_bone_global_pose(bi).origin
	var hit: Dictionary = {}
	if b.has_method("_ray_foot"):
		hit = b._ray_foot(ank)
	if not hit.has("position"):
		return
	last_hit_y = float(hit.position.y)
	last_ankle_y = ank.y
	var off: float = float(b.sole_offset) if b.get("sole_offset") != null else 0.055
	last_gap_cm = (ank.y - off - last_hit_y) * 100.0
	b.set_meta("late_ankle_xz", Vector2(ank.x, ank.z))


func _record_blob(b: Node) -> void:
	if b.blob != null and b.blob.visible:
		var wp: Vector3 = b.blob.global_position
		last_blob_xz = Vector2(wp.x, wp.z)
	else:
		var acc := Vector2.ZERO
		var n := 0
		for d in [b.blob_l, b.blob_r]:
			if d != null and d.visible:
				var p: Vector3 = d.global_position
				acc += Vector2(p.x, p.z)
				n += 1
		last_blob_xz = acc / float(n) if n > 0 else Vector2.ZERO
	var mids: Array = b.stance_sole_midpoints() if b.has_method("stance_sole_midpoints") else []
	if mids.size() > 0:
		var s: Vector3 = mids[0]
		if mids.size() > 1:
			s = (mids[0] as Vector3).lerp(mids[1] as Vector3, 0.5)
		last_stance_mid = s
	b.set_meta("late_blob_xz", last_blob_xz)
	b.set_meta("late_stance_mid", last_stance_mid)
