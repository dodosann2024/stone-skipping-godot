# v38 pipeline — what actually moved

`docs/index.html` is unchanged and still points at v35.

## Line counts (this branch, before this change → after)

| File | Before | After |
|------|--------|-------|
| `main.gd` | 7601 | 6557 |
| `boy.gd` | 2494 | 2260 |
| `follow_camera.gd` | 30 | 1007 |
| `foot_ik.gd` | 287 | 472 |
| `player_controller.gd` | 30 | 270 |
| `locomotion_anim.gd` | 24 | 288 |
| `input_joystick.gd` | 4 | 27 |
| `ground.gd` | 51 | 51 |
| `foliage_occlusion.gd` | — | 39 |
| `boy_foot_late.gd` | 83 | deleted |

The v37 shells that only called back into `main.gd` / `boy.gd` are gone. Camera math, explore movement, the locomotion tick, and foot contact now live in those modules. Rest, throw, UI, audio, and the demo sequences are still in `main.gd`. Character build, face, hat, and sit/lie poses are still in `boy.gd`. That is why those two files did not halve.

## Who writes what

Per frame:

1. `InputJoystick.read_move` — stick and keys.
2. `PlayerController.physics_step` — explore XZ and a ground height into internal state. It does not move the node.
3. `PlayerController.present` — the only explore-frame write of the boy root. Y comes from one `Ground.height` query (render-mesh collision) at the displayed XZ. Rest, throw, and placement go through `write_position` / `write_yaw` on the same object.
4. `LocomotionAnim` — AnimationTree only. No foot bones.
5. `FootIK` (`SkeletonModifier3D`) — the only foot/pelvis contact step.
6. `skeleton_updated` — `FollowCamera`, then `FoliageOcclusion`, then the ground/frame probes. That signal fires after the modifier and before Godot restores the pre-modifier bone poses, which is the pose just uploaded to the renderer.

Deleted: the second plant in `boy_foot_late.gd`, the duplicate walk-Y clamp in the old display interp, and `set_bone_global_pose_override` on the feet and hands (those calls now go through `set_bone_global_pose`).

## Which pose path the web renderer draws

Godot 4.7.2 `Skeleton3D::NOTIFICATION_UPDATE_SKELETON` runs `SkeletonModifier3D`, uploads `global_pose * bind_pose` to the RenderingServer, then restores the pre-modifier bone poses. That upload is what the Compatibility renderer skins, including the single-thread web export.

Proved on `docs/game_v38` in headless Chromium (ANGLE / SwiftShader), not in the editor:

- `?poseproof=lift` — the modifier adds 42 cm to the left foot. `screenshots/v38/cdp_proof_lift.png` shows that leg in the air. The other shoe stays on the path.
- `?poseproof=override` — the modifier is skipped and the same 42 cm is written with `set_bone_global_pose_override`. `screenshots/v38/cdp_proof_override.png` shows both shoes on the ground. The override is not in the picture.

## Acceptance (exported web build)

Served `docs/game_v38/game_v38.html?v=38&debug=1`. Chromium 390×844, device scale 3. Load, wait 60 s, tap (195, 420), wait 6 s, then CDP `Input.dispatchTouchEvent`: touchStart (54, 754), 10 touchMoves of (+3i, −6i) 30 ms apart, hold, release.

Stills are in `screenshots/v38/` (spawn, the 300 ms / 2.8 s / 0.8 s-after-release trio, idle, side, side zoom, run, run stop, sand side, slope side, eight directions, route).

What those stills show, inspected directly:

- Spawn, the first drag frame, the grass walk, the stop, and the run all show both sandals, normal-length legs, and the shoes at the surface. The boy is not buried to the shorts.
- The run frame is beside the dock lamp. The lamp does not cover him. Bushes in the side and stop frames sit beside him rather than across his chest. Foliage along the camera–boy segment is discarded in the core of a body capsule and dithered outside it, and the leaf/foliage vertex shaders bend those cards off the segment.

The numeric sole probe is not the old constant 0.80 cm. At rest it reads about 0.40–0.54 cm and the two feet differ. It is the minimum of the foot-weighted skinned vertices when that minimum agrees with the foot bone the renderer uploaded, otherwise that bone minus the rest-pose ankle-to-sole drop (12.2 cm).

It does **not** stay inside −1…+1.5 cm for the whole drag. On some walking frames the skinned-vertex sample and the foot-bone reading disagree by several centimetres, and the logged gap then spikes (burial around 7 cm, or a large positive gap when the foot ray hits a lower triangle than the surface the body is standing on). `CDP_SINK` therefore fails: 78 samples, 61 outside the bar, route only 1.3 m because the scripted stick spent the long run jammed against the dock edge. Pelvis steps that were logged stayed under 3 cm. `body_gnd_cm` stayed 0. Prim count in the HUD was about 13k–16k. Textures are not VRAM-compressed in the web preset.

## Left in main / boy on purpose

Throw simulation, rest/sit/sleep, audio, night, HUD, and the old demo sequences. Sit and lie still pose the spine and arms in `boy.gd`; foot and hand contact from those poses uses `set_bone_global_pose` so it is on the same channel the web build draws.
