# v41 report

Branch `cursor/v41-sole-sample-d4ce`, cut from `main` at `38d0351` (v40). `docs/index.html` is unchanged and still sends the site root to v35. The export is `docs/game_v41/`, no VRAM compression, single-thread web.

The standing sentence is in `docs/V41_SPEC.md` and has to be copied into the next version's spec. This report does not claim the bar is met.

## The 17 cm float

The first ruler set (`ruler_02` … `ruler_05`) did not show the feet. Those files are gone. The reshoot is an orthographic camera, perpendicular to travel, framed on the lower foot, with a 20 cm ruler whose zero is the terrain under that foot. The sandal fills about a third of the frame. Stills are `screenshots/v41/feet_float_01.png` … `feet_float_06.png` and `feet_bury_01.png`.

| still | lower skin | other skin | what the ruler shows |
| --- | ---: | ---: | --- |
| `feet_float_01.png` | +3.4 cm | +4.0 cm | sole bottom is on the 0 line. The skin vertex is the top of the sandal. Probe miss of about 3 cm. |
| `feet_float_02.png` | +6.7 cm | +3.7 cm | sole bottom is about 5 cm above 0. Real air under that foot. The other foot is the planted one, not a second foot in the air, so this is not flight. |
| `feet_float_03.png` | +3.8 cm | +12.7 cm | sole bottom is on the 0 line. Same 3 cm skin-versus-sole miss. The other foot is the swing. |
| `feet_float_04.png` | +3.3 cm | +12.0 cm | same class as 03: stance sole on the ground, swing foot up. |
| `feet_float_05.png` | +3.2 cm | +39.4 cm | the foot left this particular frame; the numbers match 03. |
| `feet_float_06.png` | +2.7 cm | +10.6 cm | sole bottom is on the 0 line, toes just kissing it. Probe miss, not a bury. |
| `feet_bury_01.png` | −5.2 cm | +1.0 cm | the sole is under the 0 line by about 5 cm. Real bury. |

The harness now does three things with that reading. Both skin soles more than 8 cm up are flight and are not scored (`feet_float_02` is not in that set). A positive gap loses 3.2 cm for the sandal under the skin vertex, and the result is clamped at zero so a planted sandal is not then called a bury. A negative gap is the skin vertex itself, which is what `feet_bury_01` shows.

```
ROUTE_DONE m=110.0 ok=false kinds=sand,grass,wood, knee_max=135 len_min=0.98 gnd_min=-15.8 at=2.3,-12.8,0.45 pelvis=2.9 bad=2613 bury=192 float=243 float_pct=9.30 scored=2613 pelvis_n=0 stop=true slide_max=0.90 slide_n=0
```

Stance float is 9.30% (243 of 2613), down from 32.93% before this classification and from 68.79% in v40. It is not under 5%. The worst bury is still −15.8 cm. Bury count is 192.

A knee rotation that lifted the buried sole and dropped the 6 cm float was tried. Shin length fell to 0.72 and the bury count went up, so that correction is not in the build. The root is still the v39/v40 collision height. `drag39_b.png` still has both shins.

## Feel

Checked against a short third-person phone feel: a step should be underway within a tenth of a second, the camera should not drift while the stick is held, and the stick has to stay big enough for a thumb without dropping the review drag under the run gate.

The stick radius stays 70 px on a 390 pt screen. The base is 140 px across and the knob is about 59 px. The review drag travels about 66 px, which is 0.94 of 70 and still a run. A larger base would make that same gesture a walk, and frame b would miss the grass. Dead zone stays 6%. Run latch stays 0.90 on / 0.82 off.

Touch-to-motion was already one physics frame. The first step was the slow part: speed eased toward the run with a 0.70 s smooth time from the first sample. Below 0.50 m/s the smooth time is now 0.22 s. Cruise is still 0.70 s, so the 2.8 s drag still reaches the grass. Turn ease is 6.2 rad/s instead of 7.5. Camera yaw error stays 0 while the stick is held (`cam_dist` 6.35). It still opens to the wide orbit after release.

Full lines are `docs/traces/v41_feel_before.txt` and `docs/traces/v41_feel_after.txt`. A full push starts at t = 0.20 s.

Walk only, stick held at 0.5 (not a run). The trace is `docs/traces/v41_feel_walk.txt`. First motion is one physics frame (0.033 s). Camera distance stays 6.35 m and yaw error stays 0.

| t | walk m/s |
| --- | ---: |
| 0.25 | 0.173 |
| 0.40 | 0.508 |
| 0.80 | 0.657 |
| 1.20 | 0.742 |

| t | before m/s | after m/s | cam dist after |
| --- | ---: | ---: | ---: |
| 0.25 | 0.189 | 0.556 | 6.35 |
| 0.30 | 0.364 | 0.706 | 6.35 |
| 0.50 | 0.953 | 1.210 | 6.35 |
| 1.00 | 1.865 | 1.991 | 6.35 |
| 1.40 (stick up) | 2.029 | 2.091 | 6.51 |

Yaw error is 0 on both traces for the whole push. The camera does not drift.

## drag39.py

Playwright, Chrome SwiftShader, iPhone 13 at 390×844, on `docs/game_v41/`.

| still | picture | HUD gnd | p50 |
| --- | --- | ---: | ---: |
| `screenshots/v41/drag39_a.png` | both shins, both sandals, on the sand | 12.9 cm | 33.3 ms |
| `screenshots/v41/drag39_b.png` | both shins, both sandals, on the rise | 13.2 cm | 33.6 ms |
| `screenshots/v41/drag39_c.png` | wide orbit, hat below the toast, both sandals | 67.4 cm | 33.3 ms |

Frame c's HUD number is not the picture. The sandals are down. SwiftShader at 33 ms is not 60 fps on an iPhone.

## AAA bar — what is still open

| Item | This version |
| --- | --- |
| **Grounding over 110 m** | Not met. After the ortho ruler pass, stance float is 9.30% (243/2613) and bury is 192, worst −15.8 cm. Planted frames were a 3.2 cm skin-versus-sandal miss. `feet_float_02` is about 5 cm of real air. `feet_bury_01` is about 5 cm of sole under the ground. A knee correction that tried to close those crushed shin length to 0.72 and was not kept. The root was not moved. |
| **Dither** | Unchanged from v40. On/off pair is `screenshots/v40/dither_on.png` and `dither_off.png`. |
| **Steep side view** | Unchanged from v40. `screenshots/v40/side_run_stop.png` keeps him in frame. |
| **iPhone frame time** | Not measured on a phone. `?debug=1` still copies `walk_30s` p50/p95/p99 and dropped frames. These stills are p50 33 ms on SwiftShader. No VRAM compression. |
| **Audio** | Unchanged from v40. Steps follow the plant and sit under the wave bed. No phone has played them. |
| **Replay** | Not this version. No new mode. |

## What the next version should do

Copy the standing sentence into that version's spec. The stance frames that are still above 1.5 cm, and the −15.8 cm bury, are the grounding gap. Do that without sinking `drag39_b.png`. Then time `game_v41` on an iPhone.
