# v40 report

Branch `cursor/v40-feel-and-bar-d4ce`, cut from `main` at `d1b1398` (the v39 merge). `docs/index.html` is unchanged and still sends the site root to v35. The export is `docs/game_v40/`, no VRAM compression, single-thread web.

The standing sentence is in `docs/V40_SPEC.md` and has to be copied into the next version's spec. This report does not claim the bar is met.

## Feel

The review drag pushes the stick almost to the rim, so the run gate is still the raw magnitude (0.90 on, 0.82 off) and a full push is still a run. Above the 6% dead zone the speed blend is `pow((mag - 0.06) / 0.94, 0.85)`, so the middle of the stick is a walk. Speed eases toward the target with a 0.70 s smooth time while speeding up, which covers about the same ground over the 2.8 s drag as the old stepped accel, and 0.16 s while braking. The post-release settle is 0.28 s at 0.22 m/s. Turning eases at 7.5 rad/s and is still capped by the old steer rate. Explore follow is the v39 camera, including the wide orbit 0.8 s after release.

`drag39.py` on this export (Playwright, Chrome SwiftShader, iPhone 13 at 390×844):

| still | picture | HUD gnd | frame p50 |
| --- | --- | ---: | ---: |
| `screenshots/v40/drag39_a.png` | both shins, both sandals, on the sand, hat under the toast | 0.6 cm | 33.3 ms |
| `screenshots/v40/drag39_b.png` | both shins, both sandals, on the grass rise, full hat | 3.0 cm | 30.5 ms |
| `screenshots/v40/drag39_c.png` | wide orbit, hat below the toast, both sandals on the grass | 71.7 cm | 31.0 ms |

Frame c's HUD number is not the picture. The sandals are on the grass. SwiftShader at ~31 ms is not 60 fps on an iPhone.

## 110 m float, measured on the drawn pose

`dev/v40_float_side.gd` walks with `?side=1` framing and saves the viewport on the same frame as the sole reading. Startup frames where the skeleton is still a metre off are ignored.

| still | skinned sole vs collision under the ankle | picture |
| --- | --- | --- |
| `screenshots/v40/float_flag_0.png` | gap 17.7 cm. Soles 1.566 / 1.620, hits 1.389 / 1.368, root 1.622 | stride on the sand. The lower sandal is down; the back foot is the swing. |
| `screenshots/v40/float_flag_1.png` | gap 17.6 cm. Root 1.616 | same stride. |
| `screenshots/v40/float_flag_2.png` | gap 19.1 cm. Root 1.610 | same stride. |
| `screenshots/v40/float_plant.png` | gap 0.70 cm. One hit is the surface under that sole; the other sample is 0.42 m lower | sandal on the sand. |

The root and the skinned sole agree (within about 6 cm). The collision sample under the ankle is the thing 17 cm lower, on a slope, while the side view shows the sandal on the sand. That is the v39 "77% float": the ankle query, not a body hanging in the air. Dropping the root to chase it would sink the pose `drag39_b.png` just passed, so the root was not moved. The 110 m harness is still not bury 0 or float ≤ 1%. The v39 line stands: worst bury −5.2 cm, displayed root step 2.9 cm.

## Dither

Same camera, cutout on then off (`demo_nocut`, which is also `?dither=0` on the export). `dev/v40_dither.gd` measured 19.5% of sampled pixels changed.

- `screenshots/v40/dither_on.png` — palm fronds between the lens and the boy are open. Shirt, shorts, and both sandals are visible.
- `screenshots/v40/dither_off.png` — the same fronds are solid and cover the shorts and the legs.

## Side view

`?side=1` no longer inherits the slope lift that looked down past the boy. The lens is pinned to the chest, 6.6 m out, pitch 0.18. `screenshots/v40/side_run_stop.png` is 0.8 s after a full-stick run is released: hat, both arms, both sandals, on the sand, in frame. The explore drag does not use this lens, and `drag39_c.png` is still the wide follow frame.

## AAA bar — what is still open

`docs/AAA_BAR.md` is the checklist. v40 does not ship it.

| Item | This version |
| --- | --- |
| **Grounding over 110 m** | Not met. The side stills show the sandal down while the ankle collision sample reads 17 cm low. The root was not dropped. Bury and the 77% float flag remain. |
| **Dither** | Met for this camera. On/off pair above, 19.5% of pixels differ. |
| **Steep side view** | The side lens keeps him in frame after a run release (`side_run_stop.png`). That shot is on the sand by the boardwalk, not the old grass-rise crop. The follow camera on `drag39_b.png` still shows the grass rise. |
| **iPhone frame time** | Not measured on a phone. This export is still no VRAM compression, single thread. SwiftShader on the drag stills was p50 30.5–33.3 ms, about 30 fps, not 60. Prims were about 107k–117k on the v39 hut and dock views; this export does not change the meshes. Plan: on an iPhone, open `docs/game_v40/game_v40.html?v=40&debug=1`, walk dock, sand, and the grass rise, and read the HUD p50 and the prim line. Pass is a stable p50 under 16.7 ms with prims around 110k. |
| **Audio** | The build wires it. The first tap calls `__unlockAudio` and sets `audio_started`. Each footstep plays `step_<sand\|grass\|wood\|water>_<0\|1>` from `_surface_kind`, with a splash on water. Those files are in the pck. No phone has played them. The stills still show the silent-mode toast. |
| **Replay** | Not this version. Feel and the bar items above came first. Throw, rest, and the day loop are the v39 systems. No new mode. |

## What the next version should do

Copy the standing sentence into that version's spec. Then, in order: get the ankle collision sample onto the triangle the sandal is standing on without sinking `drag39_b.png`; time the export on an iPhone and bring p50 under 16.7 ms; confirm footsteps on sand, grass, and wood after the unlock tap; only then deepen throw, rest, and the day loop. No new mode.
