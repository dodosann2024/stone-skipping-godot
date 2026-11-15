# v39 report

Branch `cursor/v39-drawn-sole-route-d4ce`, cut from `cursor/v38-real-pipeline-d4ce` (`37454af`). `docs/index.html` is unchanged and still sends the site root to v35.

## The crushed legs

`9a62dcd` moved the foot bone until the vertices that are at least 85% foot or toe sat on the probe surface. The knee did not follow, so the shin stayed in the terrain. In the review drag the shorts sat on the sandals, and after release one leg ended at the knee, while the HUD read gnd 0.0–0.8 cm.

That slide is gone. The hips rise by this frame's penetration of the 85% sandal shell, in world up, and the lift is dropped the same frame the penetration is gone. It is not added to last frame's lift. The rise is capped at 2.9 cm so a bad sample cannot pop the pelvis. The foot bone is not translated. Shin length is the animated knee-to-ankle length (ratio 1.00 on every sample below). Knee flex on the 110 m harness peaked at 116°, which is this clip's run swing. A crushed shin would also shorten that segment.

The camera release fix is unchanged: one explore frame, arm floor 0.82, release eases over about 0.45 s. Rest, throw, HUD and demo stay in their modules. `main.gd` is 2739 lines.

## Export stills

`docs/game_v39/`, no VRAM compression, `thread_support=false`. Chromium 390×844, dpr 3, SwiftShader. Boot 60 s, tap (195, 420), then the review drag from (54, 754) by (+3, −6) × 10. `?side=1` turns the lens 90° to travel and does not change stick yaw.

The pictures have both shins and both sandals. They are not the crouched pose from `9a62dcd`. The HUD on the same still often does not match that picture. That disagreement is the remaining grounding failure.

| still | what the picture shows | HUD gnd | probe a moment later |
| --- | --- | ---: | --- |
| `screenshots/v39/side_start.png` | full shins, both sandals | 6.6 cm | sole −9.5 cm, shin −4.9 cm, knee 6°/10°, len 1.00 |
| `screenshots/v39/side_walk.png` | full stride, both sandals down | 1.9 cm | sole −7.6 cm, shin +8.6 cm, knee 48°/27°, len 1.00 |
| `screenshots/v39/side_stop.png` | both shins, both sandals | 4.1 cm | sole +0.8…+4.7 cm, shin +6.6 cm, knee 13°/9°, len 1.00 |
| `screenshots/v39/side_run.png` | full legs, sandals on the path | 10.2 cm | sole −9.9 cm, shin +1.1 cm, knee 39°/84°, len 1.00 |
| `screenshots/v39/side_run_stop.png` | boy left the frame on the steep side view | 39.0 cm | sole −30 cm, shin −13 cm, len 1.00 |
| `screenshots/v39/front_a.png` | both shins, both sandals | 4.9 cm | sole −7.5 cm, shin +3.5 cm, knee 57°/23°, len 1.00 |
| `screenshots/v39/front_b.png` | both shins, both sandals on the path | 35.4 cm | sole −10 cm, shin +6.2 cm, knee 44°/27°, len 1.00 |
| `screenshots/v39/front_c.png` | both legs complete, not cut at the knee | 6.8 cm | sole +0.8…+5.3 cm, shin +7.2 cm, knee 10°/19°, len 1.00 |
| `screenshots/v39/side_slope.png` | idle on grass, full shins, sandals down | 0.8 cm | sole +0.8…+5.4 cm, shin +6.9 cm, knee 6°/36°, len 1.00, 116636 prims |
| `screenshots/v39/side_dock.png` | idle on the deck, full shins, sandals on the planks | 0.8 cm | sole +0.8…+2.5 cm, shin +7.8 cm, knee 6°/36°, len 1.00, 107316 prims |

SwiftShader frame time on these stills was about 22–48 ms. That is not an iPhone measurement.

## 110 m harness

SwiftShader does not walk 100 m in a CDP session: the HUD can read ~1.7 m/s while the body barely moves between samples. `V39_ROUTE=1` drives the same `player_controller.gd` in headless Godot, fixed 60 Hz physics, waypoints on the beach, the grass rise, and the dock centerline. Stick-up from spawn walks off the pier; the harness does not do that.

```
ROUTE_DONE m=110.0 ok=false kinds=sand,grass,wood knee_max=116 len_min=1.00 gnd_min=-39.9 pelvis=3.4 bad=548 stop=true
```

110 m, with sand, grass, wood, and stops. `ok=false` because 548 frames missed the sole bar. The worst sole gap was −39.9 cm. One root step was 3.4 cm, over the 3 cm pelvis cap. Shin length never left 1.00. This is not a pass of the grounding bar.

## Where this version still misses the AAA bar

`docs/AAA_BAR.md` is the standing bar. This PR does not claim it is met. No new gameplay was added.

### Release blockers

1. **Grounding.** Not met. The foot-bone slide that hid the shins is gone, and idle on the slope and the dock reads sole min +0.8 cm with the shin about 7 cm clear and the knee-to-ankle length unchanged. The review drag's pictures match that. The probe does not: the same frames report sole gaps of −8 to −30 cm, or a HUD of 35 cm, while the sandals are visibly on the path. The harness over 110 m recorded a worst gap of −39.9 cm and 548 frames outside the bar, and one pelvis step of 3.4 cm. A sample that sits well above the shoe, especially on the beach rise, is still being treated as the ground under the foot.

2. **Occluder dither.** Not re-proven. `shaders/cutout.gdshaderinc`, `foliage.gdshader`, `leaf.gdshader` and `static.gdshader` still dither foliage and props in the compatibility renderer. This version has no on/off pair from the export. The drag stills are not a proof: nothing thick was between the lens and the boy, and `side_run_stop.png` loses him for a different reason.

3. **Full island route.** Distance only. The headless harness covered 110 m of sand, grass and dock wood, including the beach rise and stops. It did not stay inside the sole bar, the pelvis cap was broken once, and it is not a CDP touch route on the export. Chrome on SwiftShader still cannot accumulate that distance. "Every major grass slope" is not shown.

### Self-audit

| Area | This version |
| --- | --- |
| **Feel** | The stick still has a small deadzone, a run gate at magnitude 0.90, and a spot-turn only from a near stop. Nothing here was retuned. The harness stop at speed 0.05 left the sole 16 cm up for several frames before it settled to about 1 cm. That is a skate/float at the end of a step, and it is still in the build. |
| **Camera** | The release crop from v38 is still fixed, and `front_c.png` keeps the hat and both shoes. `?side=1` is a stills lens only. On the steep path, `side_run_stop.png` loses the boy entirely while gnd reads 39 cm. Slope framing is not done. |
| **Grounding** | See blocker 1. Idle dock and slope are inside the spirit of the bar. The moving probe is not. |
| **Character** | The review pose is a walk again: shins visible, sandals present, knee angle in the clip's own range (about 6–116°), length ratio 1.00. Face and hat are readable in the side stills. Sit, sleep and throw were not re-shot. |
| **World** | Night lamps, shore foam and foliage occlusion were not re-shot. The iPhone audio toast covers the middle of every still. |
| **UI / touch** | The review drag still walks. Buttons and the toast were not hit-tested. The toast does not time out during a 60 s boot plus a drag, so it blocks the picture the player is judging. |
| **Audio** | The unlock path and the footstep hook are still in the project. No phone played them this version. The stills show the silent-mode toast, which is the iOS path not yet confirmed. |
| **Perf** | Export is still single-thread, no VRAM compression. These stills are SwiftShader at about 22–48 ms, not 60 fps on an iPhone. Prims were 107316 on the dock and 116636 beside the hut. The hut frame is over the ~110k note. |
| **Replay** | Not met, and this PR did not move it. Walk, throw, sit, sleep and day/night are the same systems as v38. Two minutes on the island is still one circuit. The bar forbids inventing a mode to hide that. |

## What the next versions should do, in order

1. Make the drawn sole and the shin sample agree with the picture on the review drag and across the 110 m. The failure is the ground sample under the shoe on a rise, not a missing constant offset. Until gnd on a moving still matches the sandals in that still, the grounding blocker stays open.
2. Hold the pelvis to 3 cm/frame on that same route. The harness already saw 3.4 cm.
3. Keep the boy in frame on a steep side view after release. `side_run_stop.png` is the miss.
4. Shoot foliage and prop dither on and off from the export.
5. Tighten the stop so the sole does not hang 16 cm up while the stick is already at zero.
6. Measure frame time on an iPhone-class device, and get the hut view back under ~110k prims without bringing VRAM compression back.
7. Confirm the iOS audio unlock and that footsteps change with sand, grass and wood.
8. Only then deepen throw, rest and the day loop so a second visit is different in the hands and in the light. No new mode.

## Modules

| module | lines |
| --- | ---: |
| `main.gd` | 2739 |
| `rest_pose.gd` | 1311 |
| `throw_session.gd` | 442 |
| `game_ui.gd` | 422 |
| `demo_sequence.gd` | 2183 |
| `foot_ik.gd` | 603 |
| `follow_camera.gd` | 1002 |
| `boy.gd` | 2260 |
| `player_controller.gd` | 458 |
