class_name Constants
extends Object
## Numbers read once from the old layout, then owned here.
## Wade limit is the old "too deep" cutoff (main.gd, h < -0.42).

const MODEL_SCALE := 1.35
const WALK_SPEED := 1.15
const RUN_SPEED := 2.7
const DECK_Y := 0.8
const WADE_MIN_Y := -0.42
const DEADZONE := 0.06
const RUN_ON := 0.90
const RUN_OFF := 0.82
const STICK_RADIUS := 70.0
const ACCEL_S := 0.70
const FIRST_STEP_S := 0.18
const BRAKE_S := 0.16
const TURN_RATE := 7.5
const STOP_S := 0.28
## Outsole sits this far under the lowest skinned sole vertex (v41 ruler).
const SANDAL_BELOW := 0.032
const CAM_PITCH := 0.610865  # 35 degrees, inside the 30–40 decision
const CAM_DIST := 6.4
const CAM_DIST_WIDE := 8.8
const CAM_MIN_DIST := 2.2
const CAM_CLEAR := 0.25
const OCCLUSION_MIN := 0.35
const LAYER_GROUND := 1
const LAYER_BLOCK := 2
const LAYER_PROP := 4
const LAYER_PLAYER := 8
