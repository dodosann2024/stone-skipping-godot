# v40 report

Branch `cursor/v40-feel-and-bar-d4ce`, cut from `main` at `d1b1398` (the v39 merge). `docs/index.html` is unchanged and still sends the site root to v35. The export is `docs/game_v40/`, no VRAM compression, single-thread web.

The standing sentence is in `docs/V40_SPEC.md` and has to be copied into the next version's spec. This report does not claim the bar is met.

## Feel

The review drag still pushes the stick almost to the rim. The run gate is the raw magnitude, 0.90 on and 0.82 off, so it does not flicker. Above the 6% dead zone the walk blend is `pow((mag - 0.06) / 0.94, 0.85)`. Speed eases in over 0.70 s and brakes in 0.16 s. The chest leans into that start, and the stop is a 0.28 s settle step at 0.22 m/s. A stick reversed more than about 120° while moving becomes a turn in place instead of a snap. Uphill grade above 0.10 trims speed, down to 90% on a steep rise, and the spine pitches with the grade. The review path is a mild rise, so that trim is small.

The stick base still jumps under the thumb. The drawn ring shows the dead zone and the run threshold. The knob swells when the thumb leaves the dead zone and turns amber while the run latch is on.

A planted sole may move at most 0.9 cm in one frame. The swing foot is free. On the 110 m route with a 1 cm hold, `slide_max=1.00` and `slide_n=0` (no planted frame over 1 cm). Knee peak on that run was 134°.

While the stick is down and he is running, the camera looks 0.18 m ahead and eases back to 0.10 m as soon as the stick lifts, so the release frame is not a crop. A manual orbit coasts for about 0.4 s, then, 1.5 s after the finger leaves, yaw eases behind travel. The review drag never orbits, so yaw still locks behind him. Pulling the arm in for a tree eases at rate 1.35 instead of snapping.

`drag39.py` on this export (Playwright, Chrome SwiftShader, iPhone 13 at 390×844):

| still | picture | HUD gnd | frame p50 |
| --- | --- | ---: | ---: |
| `screenshots/v40/drag39_a.png` | both shins, both sandals, on the sand, hat under the toast | 0.4 cm | 33.0 ms |
| `screenshots/v40/drag39_b.png` | both shins, both sandals, on the grass rise, full hat | 12.0 cm | 33.3 ms |
| `screenshots/v40/drag39_c.png` | wide orbit, hat below the toast, both sandals on the grass | 79.2 cm | 39.1 ms |

Frame b and frame c HUD numbers are not the picture. The sandals are on the ground. SwiftShader at about 33–39 ms is not 60 fps on an iPhone.

## iPhone frame time

`?debug=1` keeps a 30 s window of frames where speed is above 0.12 m/s. The panel shows `walk30 p50 p95 p99` and `drop` / `miss`. **复制数据** copies:

`walk_30s n=… p50=… p95=… p99=… dropped=… missed_slots=…`

`dropped` is frames longer than 20 ms. `missed_slots` is `floor(ms / 16.7) - 1`. On an iPhone, open `docs/game_v40/game_v40.html?v=40&debug=1`, walk the dock, the sand, and the grass rise for half a minute, tap 复制数据, and paste that line. Pass is p50 under 16.7 ms. Textures are still uncompressed.

## Footsteps

A step sound fires when the lower sole plants (gap inside −2…+2.5 cm), not on the animation phase. The clip is `step_sand`, `step_grass`, `step_wood`, or `step_water`. Volume sits 4.5 dB under the live wave bed while walking and 1.5 dB under it while running, clamped to −16…−6 dB. Waves near the shore are about −7 dB, so a walk step is quieter than the water and a run step is close to it. A phone still has to confirm that.

## 110 m float, measured on the drawn pose

`dev/v40_float_side.gd` walks with `?side=1` framing and saves the viewport on the same frame as the sole reading. Startup frames where the skeleton is still a metre off are ignored.

| still | skinned sole vs collision under the ankle | picture |
| --- | --- | --- |
| `screenshots/v40/float_flag_0.png` | gap 17.7 cm. Soles 1.566 / 1.620, hits 1.389 / 1.368, root 1.622 | stride on the sand. The lower sandal is down; the back foot is the swing. |
| `screenshots/v40/float_flag_1.png` | gap 17.6 cm. Root 1.616 | same stride. |
| `screenshots/v40/float_flag_2.png` | gap 19.1 cm. Root 1.610 | same stride. |
| `screenshots/v40/float_plant.png` | gap 0.70 cm. One hit is the surface under that sole; the other sample is 0.42 m lower | sandal on the sand. |

The root and the skinned sole agree (within about 6 cm). The collision sample under the ankle is the thing 17 cm lower, on a slope, while the side view shows the sandal on the sand. That is the v39 "77% float": the ankle query, not a body hanging in the air. Dropping the root to chase it would sink the pose `drag39_b.png` just passed, so the root was not moved. The latest 110 m line is `float_pct=68.79`, bury 89, pelvis 2.9 cm, `slide_max=1.00`, `slide_n=0`. It is still not bury 0 or float ≤ 1%.

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
| **iPhone frame time** | Not measured on a phone. `?debug=1` now puts a 30 s walk's p50/p95/p99 and dropped frames on 复制数据. SwiftShader on these drag stills was p50 33–39 ms. No VRAM compression. Pass on a phone is p50 under 16.7 ms. |
| **Audio** | Steps fire on the plant and sit under the wave bed (walk −4.5 dB, run −1.5 dB, clamped −16…−6). Sand, grass, wood, and water each have a clip. No phone has played them. |
| **Replay** | Not this version. Feel and the bar items above came first. Throw, rest, and the day loop are the v39 systems. No new mode. |

## What the next version should do

Copy the standing sentence into that version's spec. Then, in order: get the ankle collision sample onto the triangle the sandal is standing on without sinking `drag39_b.png`; time the export on an iPhone and bring p50 under 16.7 ms; confirm footsteps on sand, grass, and wood after the unlock tap; only then deepen throw, rest, and the day loop. No new mode.
