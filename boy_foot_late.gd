extends Node
## Plants on SceneTree.process_frame — after every node's _process — so nothing
## else can slide the ankles before the frame is observed / drawn.

var frames := 0
var last_gap_cm := 0.0
var last_ankle_y := 0.0
var last_hit_y := 0.0


func _ready() -> void:
	set_process(false)
	get_tree().process_frame.connect(_on_process_frame)


func _on_process_frame() -> void:
	frames += 1
	var b := get_parent()
	if b == null or not b.has_method("_reassert_foot_plants"):
		return
	b._reassert_foot_plants()
	if b.skel == null:
		return
	var bi: int = b.skel.find_bone("mixamorig_LeftFoot")
	if bi < 0:
		return
	var ank: Vector3 = b.skel.global_transform * b.skel.get_bone_global_pose(bi).origin
	var hit: Dictionary = b._ray_foot(ank)
	if not hit.has("position"):
		return
	last_hit_y = float(hit.position.y)
	last_ankle_y = ank.y
	last_gap_cm = (ank.y - b.sole_offset - last_hit_y) * 100.0
	b.set_meta("late_ankle_xz", Vector2(ank.x, ank.z))
	if absf(last_gap_cm) > 0.15:
		var want := Vector3(ank.x, last_hit_y + b.sole_offset, ank.z)
		b._plant_foot_override(0, bi, want, hit.get("normal", Vector3.UP), 1.0)
		ank = b.skel.global_transform * b.skel.get_bone_global_pose(bi).origin
		last_ankle_y = ank.y
		last_gap_cm = (ank.y - b.sole_offset - last_hit_y) * 100.0
		b.set_meta("late_ankle_xz", Vector2(ank.x, ank.z))
