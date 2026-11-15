# v39 report

Branch `cursor/v39-drawn-sole-route-d4ce`, cut from `cursor/v38-real-pipeline-d4ce` (`37454af`). `docs/index.html` is unchanged and still sends the site root to v35.

## The crushed legs

`9a62dcd` moved the foot bone until the vertices that are at least 85% foot or toe sat on the probe surface. The knee did not follow, so the shin stayed in the terrain. In the review drag the shorts sat on the sandals, and after release one leg ended at the knee, while the HUD read gnd 0.0–0.8 cm.

That slide is gone because the v39 foot IK that aimed the legs at a drawn probe is gone. Ground, root height, and foot IK are the v38 code again. The drawn-triangle probe is used by the uphill camera only. It does not set the root and it does not move a bone. Knee flex on the 110 m harness peaked at 116°.

The camera release fix is unchanged on flat ground: one explore frame, arm floor 0.82, release eases over about 0.45 s. On an uphill the lens now pitches with the grade and lifts until the segment from the camera to the feet stays above the drawn triangles. Rest, throw, HUD and demo stay in their modules. `main.gd` is 2739 lines.

## Bisect of drag39.py frame b

`drag39.py` is Playwright, Chrome `--use-gl=swiftshader`, the iPhone 13 profile at 390×844, a fresh context, and a 6 s wait after the tap. Each row is that script against the export stored in that commit. The 2.8 s frame is the grass rise.

| commit | frame b | stills |
| --- | --- | --- |
| `37454af` (v38) | both shins, both sandals, HUD gnd 19.5 cm | `screenshots/v39/bisect/37454af_a.png` `_b.png` `_c.png` |
| `5bfc309` | shorts on the grass, no legs, HUD gnd 0.8 cm | `screenshots/v39/bisect/5bfc309_*.png` |
| `9a62dcd` | same sink, HUD gnd 0.8 cm | `screenshots/v39/bisect/9a62dcd_*.png` |
| `2e3610d` | same sink, HUD gnd 11.0 cm | `screenshots/v39/bisect/2e3610d_*.png` |
| `bb693a3` | same sink, HUD gnd 25.9 cm | `screenshots/v39/bisect/bb693a3_*.png` |
| `3440402` | same sink, HUD gnd 1.8 cm | `screenshots/v39/bisect/3440402_*.png` |
| `a3b6806` | same sink, HUD gnd 33.2 cm | `screenshots/v39/bisect/a3b6806_*.png` |

The break is `5bfc309`. That commit replaced the foot IK. The new solver aimed the legs at the probe, and every later commit kept a probe-driven pose. v38's ground, root height, and foot IK are restored. The camera release, the crest line-of-sight check, the `main.gd` split, and the removal of the old web exports stay. `drawn_h` is called by the camera only.

This commit's export, same script:

| still | picture | HUD gnd |
| --- | --- | ---: |
| `screenshots/v39/drag39_a.png` | both shins, both sandals, on the sand path | 6.5 cm |
| `screenshots/v39/drag39_b.png` | both shins, both sandals, on the grass rise | 1.6 cm |
| `screenshots/v39/drag39_c.png` | both sandals planted | 74.0 cm |

Frame c's HUD number is not the picture. The sandals are on the grass.

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
ROUTE_DONE m=110.0 ok=false kinds=sand,grass,wood, knee_max=116 len_min=0.97 gnd_min=-5.2 at=4.3,-7.4,2.04 pelvis=41.0 bad=7994 bury=101 float=6117 float_pct=76.52 scored=7994 pelvis_n=1 stop=true
```

This is the v38 ground, scored by the same collision height the feet use. It is not an improvement on the later v39 harness, and it is not bury 0 or float ≤ 1%. 101 frames are under the surface. 6117 frames, 76.52% of 7994, read the lower sole more than 1.5 cm up. The worst bury is −5.2 cm. One displayed root step was 41 cm, which is the v38 root write with no 3 cm clamp. Knee peak is 116°. A drawn-triangle score was tried as a measurement only and made the float reading worse, so the harness stays on the collision height. The pose was not changed to chase the number.

## Where this version still misses the AAA bar

`docs/AAA_BAR.md` is the standing bar. This PR does not claim it is met. No new gameplay was added.

### Release blockers

1. **Grounding.** The owner's drag is back to the v38 picture. `drag39_b.png` on this commit shows both shins and both sandals on the grass rise (HUD gnd 1.6 cm). `drag39_a.png` and `drag39_c.png` show both sandals. The 110 m harness is not met: bury 101, float 76.52% (6117 of 7994), worst gap −5.2 cm, one root step 41 cm.

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

1. Bring the 110 m sole reading inside −1…+1.5 cm without putting the probe back in charge of the pose. On this v38 ground the drag shows the legs, and the harness still reads float on 76.52% of frames.
2. The v38 root write moved 41 cm in one displayed frame. A clamp there has to be checked against `drag39_b.png` before it ships.
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
