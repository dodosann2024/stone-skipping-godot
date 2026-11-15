# v39 report

Branch `cursor/v39-drawn-sole-route-d4ce`, cut from `cursor/v38-real-pipeline-d4ce` (`37454af`). `docs/index.html` is unchanged and still sends the site root to v35.

## The crushed legs

`9a62dcd` moved the foot bone until the vertices that are at least 85% foot or toe sat on the probe surface. The knee did not follow, so the shin stayed in the terrain. In the review drag the shorts sat on the sandals, and after release one leg ended at the knee, while the HUD read gnd 0.0–0.8 cm.

That slide is gone. The hips move vertically with the lower sole, in world up, and the foot bone is not translated. The shift is capped at 12 cm and eased across frames. A miss, or a face more than 30 cm off the sandal, leaves the animated leg alone. Shin length is the animated knee-to-ankle length (ratio 1.00 on every sample below). Knee flex on the 110 m harness peaked at 116°, which is this clip's run swing. A crushed shin would also shorten that segment.

The camera release fix is unchanged on flat ground: one explore frame, arm floor 0.82, release eases over about 0.45 s. On an uphill the lens now pitches with the grade and lifts until the segment from the camera to the feet stays above the drawn triangles. Rest, throw, HUD and demo stay in their modules. `main.gd` is 2739 lines.

## The rise, then the flung sandal

The 2.8 s frame was the crest in front of the lens. The side view of that gesture shows full legs. Raising the camera with the slope fixed that picture, and it is kept.

Taking the highest drawn triangle in the column did not. On `bb693a3` the 300 ms frame sank until the shorts read as a stump (HUD gnd 26.9 cm), and at 2.8 s one sandal was up by the hat while the torso folded into a crawl. That face was a steep or overlapping triangle above the foot. The query now keeps a triangle only when its XZ footprint contains the point, its normal is at least as upright as the 40° walk slope (`|n.y| ≥ cos 40°`), and its height is the nearest one at or below a probe just above the sandal. A miss leaves the animated leg alone and the root on the controller height.

The correction is a vertical hip shift of the lower sole, at most 12 cm either way, eased across frames. The knee is not retargeted, so a bad face cannot swing the foot sideways or park a sandal by the hat. The displayed root step is clamped to 3 cm.

On the re-exported build, the same drag:

| still | picture | HUD gnd |
| --- | --- | ---: |
| `screenshots/v39/front_a.png` | both shins, both sandals, shadow, not a stump | 9.1 cm |
| `screenshots/v39/front_b.png` | normal stride on the rise, both sandals, no leg by the hat | 2.0 cm |
| `screenshots/v39/front_c.png` | both sandals planted, shadow | 11.2 cm |
| `screenshots/v39/side_start.png` | profile, full shins, both sandals | 9.5 cm |
| `screenshots/v39/side_walk.png` | profile stride, full shins, both sandals | 0.8 cm |
| `screenshots/v39/side_stop.png` | profile, full shins, both sandals | 14.3 cm |

Eight slope headings are `screenshots/v39/slope_dir_*.png`. The drag test is `dev/cdp_side_v39.mjs` (390×844, dpr 3, 60 s, tap 195,420, touch from 54,754 by +3,−6 ×10 at 30 ms, shots at 300 ms, 2.8 s, and 0.8 s after release).

## Published builds

`docs/` keeps `game_v35` (live), `game_v38`, and `game_v39`. Older exports (`game_v22`–`v24`, `v27`–`v34`, and `v36`/`v37`) are removed. `docs/index.html` still points at v35. Changelog notes that name the removed folders are history. No script still falls back to those folders.

## Export stills

`docs/game_v39/`, no VRAM compression, `thread_support=false`. Chromium 390×844, dpr 3, SwiftShader. Boot 60 s, tap (195, 420), then the review drag from (54, 754) by (+3, −6) × 10. `?side=1` turns the lens 90° to travel and does not change stick yaw.

The pictures have both shins and both sandals. They are not the crouched pose from `9a62dcd`. The HUD on the same still often does not match that picture. That disagreement is the remaining grounding failure.

| still | what the picture shows | HUD gnd | probe a moment later |
| --- | --- | ---: | --- |
| `screenshots/v39/side_start.png` | full shins, both sandals | 9.5 cm | sole −0.1…+0.7 cm, knee 34°/20°, len 1.00 |
| `screenshots/v39/side_walk.png` | stride, full shins, both sandals | 0.8 cm | sole −5.2…+1.2 cm, shin +9.3 cm, knee 33°/22°, len 1.00 |
| `screenshots/v39/side_stop.png` | full shins, both sandals | 14.3 cm | sole −8.8 cm, shin −1.3 cm, knee 13°/31°, len 1.00 |
| `screenshots/v39/side_run.png` | run, full legs, boy low in the frame | 8.3 cm | sole −15.8 cm, knee 51°/87°, len 1.00 |
| `screenshots/v39/side_run_stop.png` | boy has left the bottom of the frame | 2.9 cm | sole −4.8 cm, knee 64°/37°, len 1.00 |
| `screenshots/v39/front_a.png` | both shins, both sandals, shadow | 9.1 cm | sole −0.1…+0.9 cm, knee 21°/19°, len 1.00 |
| `screenshots/v39/front_b.png` | normal stride, both sandals, no leg by the hat | 2.0 cm | sole −4.5…+2.5 cm, shin +9.6 cm, knee 29°/18°, len 1.00 |
| `screenshots/v39/front_c.png` | both sandals planted, shadow | 11.2 cm | sole −8.1 cm, shin +3.0 cm, knee 18°/53°, len 1.00 |
| `screenshots/v39/side_slope.png` | idle on grass, full shins, sandals down | 0.8 cm | sole +0.8…+5.4 cm, shin +6.9 cm, knee 6°/36°, len 1.00 |
| `screenshots/v39/side_dock.png` | idle on the deck, full shins, sandals on the planks | 0.8 cm | sole +0.8…+2.5 cm, shin +7.8 cm, knee 6°/36°, len 1.00 |

SwiftShader frame time on these stills was about 22–48 ms. That is not an iPhone measurement.

## 110 m harness

SwiftShader does not walk 100 m in a CDP session: the HUD can read ~1.7 m/s while the body barely moves between samples. `V39_ROUTE=1` drives the same `player_controller.gd` in headless Godot, fixed 60 Hz physics, waypoints on the beach, the grass rise, and the dock centerline. Stick-up from spawn walks off the pier; the harness does not do that.

```
ROUTE_DONE m=110.0 ok=false kinds=sand,grass,wood, knee_max=116 len_min=1.00 gnd_min=-21.9 at=3.1,-10.0,1.07 pelvis=3.0 bad=1997 bury=1071 float=926 pelvis_n=0 stop=true
```

110 m, with sand, grass, wood, and stops. `ok=false`. 1997 frames missed the sole bar: 1071 with the lower sole or a same-terrace shin under the surface, 926 with the lower sole more than 1.5 cm up. No frame failed the pelvis counter. The largest displayed root step printed as 3.0 cm. Shin length stayed 1.00 and the knee stayed at this clip's 116°.

The remaining frames are the 12 cm cap. On those samples the hip shift is already at +12 cm or −12 cm and the sole is still outside −1…+1.5, because the walkable triangle under that foot is further than 12 cm from the animated sole (the downhill foot on a grade, or a straight leg over a lower terrace). A gap past 30 cm is ignored on purpose, so a cliff cannot move the leg; two samples sat there with the hip at 0 and the sole 33 cm and 38 cm up. This is not a pass.

## Where this version still misses the AAA bar

`docs/AAA_BAR.md` is the standing bar. This PR does not claim it is met. No new gameplay was added.

### Release blockers

1. **Grounding.** Not met. The foot-bone slide is gone, and the flung sandal from `bb693a3` is gone: `front_a.png` is a walk with both shins (HUD 9.1 cm), `front_b.png` is a normal stride on the rise (HUD 2.0 cm, no leg by the hat), `front_c.png` has both sandals (HUD 11.2 cm). The eight slope headings are normal walks. The query is the walkable triangle whose XZ contains the foot, nearest below a probe just above the sandal. The 110 m harness is still outside the bar: 1997 bad frames (1071 bury, 926 float), worst gap −21.9 cm at (3.1, −10.0), pelvis step 3.0 cm, knee max 116°, shin length 1.00. Those frames are already on the 12 cm cap.

2. **Occluder dither.** Not re-proven. `shaders/cutout.gdshaderinc`, `foliage.gdshader`, `leaf.gdshader` and `static.gdshader` still dither foliage and props in the compatibility renderer. This version has no on/off pair from the export. The drag stills are not a proof: nothing thick was between the lens and the boy, and `side_run_stop.png` loses him for a different reason.

3. **Full island route.** Distance only. The headless harness covered 110 m of sand, grass and dock wood, including the beach rise and stops. It did not stay inside the sole bar. It is not a CDP touch route on the export. Chrome on SwiftShader still cannot accumulate that distance. The eight slope headings are stills, not a circuit of every grass slope.

### Self-audit

| Area | This version |
| --- | --- |
| **Feel** | The stick still has a small deadzone, a run gate at magnitude 0.90, and a spot-turn only from a near stop. Nothing here was retuned. The harness stop at speed 0.05 left the sole 16 cm up for several frames before it settled to about 1 cm. That is a skate/float at the end of a step, and it is still in the build. |
| **Camera** | The release crop from v38 is still fixed, and `front_c.png` keeps the hat and both shoes. `?side=1` is a stills lens only. On the steep path, `side_run_stop.png` loses the boy off the bottom of the frame while gnd reads 2.9 cm. The uphill crest raise is kept. |
| **Grounding** | See blocker 1. Idle dock and slope are inside the spirit of the bar. The moving probe is not. |
| **Character** | The review pose is a walk again: shins visible, sandals present, knee angle in the clip's own range (about 6–116°), length ratio 1.00. Face and hat are readable in the side stills. Sit, sleep and throw were not re-shot. |
| **World** | Night lamps, shore foam and foliage occlusion were not re-shot. The iPhone audio toast covers the middle of every still. |
| **UI / touch** | The review drag still walks. Buttons and the toast were not hit-tested. The toast does not time out during a 60 s boot plus a drag, so it blocks the picture the player is judging. |
| **Audio** | The unlock path and the footstep hook are still in the project. No phone played them this version. The stills show the silent-mode toast, which is the iOS path not yet confirmed. |
| **Perf** | Export is still single-thread, no VRAM compression. These stills are SwiftShader at about 22–48 ms, not 60 fps on an iPhone. Prims were 107316 on the dock and 116636 beside the hut. The hut frame is over the ~110k note. |
| **Replay** | Not met, and this PR did not move it. Walk, throw, sit, sleep and day/night are the same systems as v38. Two minutes on the island is still one circuit. The bar forbids inventing a mode to hide that. |

## What the next versions should do, in order

1. Close the frames the 12 cm cap leaves outside −1…+1.5 cm. On the 110 m route that is 1997 frames, almost all of them already sitting on the cap, where the walkable triangle is further than 12 cm from the animated sole. The review drag no longer sinks into a stump or throws a sandal at the hat.
2. Keep the displayed root step at 3 cm. This run's largest printed step was 3.0 cm and the pelvis counter stayed at 0.
3. Keep the boy in frame on a steep side view after release. `side_run_stop.png` still loses him off the bottom.
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
