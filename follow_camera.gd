class_name FollowCamera
extends RefCounted
## v37: camera owner. Must run AFTER foot_ik so framing / crest LOS / stick-lock
## see the same final posed soles the GPU draws. main still holds the orbit
## state; this module is the call-order gate + cutout focus helper.

var main: Node
var pending_delta := 0.016
var deferred := false


func setup(p_main: Node) -> void:
	main = p_main


## Latch the render delta; real apply happens in finalize() after plant.
func defer_view(delta: float) -> void:
	pending_delta = delta
	deferred = true


## Camera + foliage cutout from the post-plant boy pose.
func finalize() -> void:
	if main == null or not deferred:
		return
	deferred = false
	if main.has_method("_update_camera"):
		main.call("_update_camera", pending_delta)
	if main.has_method("_apply_foliage_cutout"):
		main.call("_apply_foliage_cutout")
