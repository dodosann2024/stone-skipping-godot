# v39 report

Branch `cursor/v39-drawn-sole-route-d4ce`, cut from `cursor/v38-real-pipeline-d4ce` (`37454af`). `docs/index.html` is unchanged and still sends the site root to v35.

## Why the HUD said gnd 97.8 cm

`gnd` is the worst skinned-sole gap. Foot IK kept a hip-lift accumulator. Godot restores bone poses after the skin upload, so the next frame measured the animation again and, whenever that sole was more than 8 cm under the ray, added another 2.9 cm. After a short walk the accumulator was about a metre. The HUD printed that risen pose. The sandals in the picture were the planted animation. The accumulator is gone. The probe now takes the lowest shoe vertex skinned with the matrix the renderer uploads (`skeleton.global * (global_pose * bind_pose)`), on vertices that are at least 85% foot or toe, and compares it to the ground sample closest to that vertex.

## CDP sole bar

Exported `docs/game_v39/` (no VRAM compression, `thread_support=false`). Headless Chromium 390×844, dpr 3, `?v=39&debug=1`.

Drag through run-stop, both soles, AAA bar −1.0…+1.5 cm, no swing-foot exemption. Every sample in that run was inside the bar. Release, which used to read ~97.8 cm, read 0.80 cm with both sandals on the grass:

| still | sole min cm | sole max cm |
| --- | ---: | ---: |
| spawn | 0.80 | 0.87 |
| walk start | 0.77 | 0.78 |
| mid walk (slope) | 0.80 | 0.86 |
| 0.8 s after release | 0.77 | 0.80 |
| idle | 0.80 | 0.82 |
| run | 0.80 | 0.80 |
| run stop | 0.80 | 0.80 |

Pelvis step on those samples stayed under 3 cm. Prims on the release still: 106992. SwiftShader frame time on that still was about 21 ms (the iPhone target is the export settings above, not the software GL renderer).

## Camera

Release used to collapse a speed-scaled look-ahead and crush the explore arm (down to 0.42) when the idle probe thought the lens was blocked. That is the head crop. The arm no longer pulls in while exploring. Walk, run and idle share one frame: look at the neck, distance floored at 6.70 m (tall phone) / 6.35 m, pitch 0.28–0.36. Stick release eases back to that frame over about 0.45 s. On the release still the hat, face and both shoes are in frame.

## Route

The old 1.3 m route held one screen-space stick into the dock edge. `dev/cdp_route_v39.mjs` steers from `window.__ground.yaw` and also has a camera-forward hold, which is the drag that leaves the lip (spawn z −9.18 toward z −7.6, body y 1.49 → 1.85, soles still in the bar). Eight compass headings on that slope were shot; each sample was inside the bar (`screenshots/v39/cdp_dir_*.png`).

A single headless Chrome session did not accumulate 100 m. SwiftShader only advances a fraction of a metre between CDP samples even while the HUD speed reads ~1.7 m/s, so a multi-minute hold still measured a few metres. The script and the stills are in the tree; the 100 m figure is not claimed.

## Modules

`main.gd` 6557 → 2730 lines. Rest, throw, HUD and demo sequences moved out with the same call wrappers, so behaviour is unchanged:

| module | lines |
| --- | ---: |
| `rest_pose.gd` | 1311 |
| `throw_session.gd` | 442 |
| `game_ui.gd` | 422 |
| `demo_sequence.gd` | 2183 |
| `foot_ik.gd` | 531 |
| `follow_camera.gd` | 995 |
| `boy.gd` | 2260 |

## Stills

`screenshots/v39/cdp_sink_A.png`, `cdp_sink_B.png`, `cdp_sink_C.png`, `cdp_sink_idle.png`, `cdp_run.png`, `cdp_run_stop.png`, `cdp_dir_n.png`, `cdp_dir_ne.png`, `cdp_dir_e.png`, `cdp_dir_se.png`, `cdp_dir_s.png`, `cdp_dir_sw.png`, `cdp_dir_w.png`, `cdp_dir_nw.png`.
