class_name LocomotionAnim
extends RefCounted
## v37: mixer / gait polish owner. Writes AnimationTree + soft upper-body polish
## only — never foot overrides. Foot contact is FootIK's job after this runs.

var boy: CharacterBody3D


func setup(p_boy: CharacterBody3D) -> void:
	boy = p_boy


## Advance AnimationTree / activity poses. Returns false if this frame is a
## prop-clip early-out (no foot plant wanted).
func advance(delta: float) -> bool:
	if boy == null or not boy.has_method("_loco_advance"):
		return false
	return bool(boy.call("_loco_advance", delta))


## Soft arm/hip polish after mixer; legs untouched.
func polish(delta: float) -> void:
	if boy != null and boy.has_method("_polish_gait"):
		boy.call("_polish_gait", delta)
