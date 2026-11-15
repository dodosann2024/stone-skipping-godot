# v41 report

Branch `cursor/v41-sole-sample-d4ce`, cut from `main` at `38d0351` (v40). `docs/index.html` is unchanged and still sends the site root to v35. The export is `docs/game_v41/`, no VRAM compression, single-thread web.

The standing sentence is in `docs/V41_SPEC.md` and has to be copied into the next version's spec. This report does not claim the bar is met.

## The 17 cm float

v40 scored every physics frame with the ankle bone, minus a fixed drop, against a long ray under the ankle. That read `float_pct` 68.79.

v41 scores the lowest skinned vertex that is at least 72% foot or toe, with a short ray that starts 8 cm above that vertex and ends 40 cm below it. A frame where both soles are more than 4 cm up is flight and is not scored. The pose solver is unchanged, so the picture does not move to chase the number.

110 m, fixed 60 Hz:

```
ROUTE_DONE m=110.0 ok=false kinds=sand,grass,wood, knee_max=123 len_min=0.98 gnd_min=-15.8 at=2.3,-12.8,0.45 pelvis=2.9 bad=2302 bury=87 float=758 float_pct=32.93 scored=2302 pelvis_n=0 stop=true slide_max=0.90 slide_n=0
```

Stance float is 32.93% (758 of 2302), not ~0. The worst bury is still −15.8 cm. Moving the sample off the ankle removed the swing frames and the worst of the ankle-terrace miss. It did not make the stance sole sit inside −1…+1.5 cm on every scored frame. The root was not lowered.

Side views, 0.45 m apart, with a 20 cm ruler whose zero is the collision under the visible lower foot (`dev/v41_sole_ruler.gd`):

| still | sole vertex | old ankle sample | picture |
| --- | ---: | ---: | --- |
| `screenshots/v41/ruler_01.png` | 1.11 cm | 5.37 cm | stride, sandals on the sand |
| `screenshots/v41/ruler_02.png` | 11.84 cm | 16.90 cm | later on the same run |
| `screenshots/v41/ruler_03.png` | 46.08 cm | 78.24 cm | sole sample still far above the hit |
| `screenshots/v41/ruler_04.png` | 43.23 cm | 48.82 cm | same |
| `screenshots/v41/ruler_05.png` | 25.63 cm | 24.68 cm | same |
| `screenshots/v41/ruler_06.png` | 0.40 cm | 4.57 cm | planted; the sole vertex is inside the bar, the ankle sample is not |

On the two contact frames the sole vertex is 0.4 cm and 1.1 cm, and the ankle sample on those same frames is 4.6 cm and 5.4 cm. That part was the probe. The 12–46 cm frames are the lower foot actually up in the run. Those are not fixed by a different ray.

## Feel

Checked against a short third-person phone feel: a step should be underway within a tenth of a second, the camera should not drift while the stick is held, and the stick has to stay big enough for a thumb without dropping the review drag under the run gate.

The stick radius stays 70 px on a 390 pt screen. The base is 140 px across and the knob is about 59 px. The review drag travels about 66 px, which is 0.94 of 70 and still a run. A larger base would make that same gesture a walk, and frame b would miss the grass. Dead zone stays 6%. Run latch stays 0.90 on / 0.82 off.

Touch-to-motion was already one physics frame. The first step was the slow part: speed eased toward the run with a 0.70 s smooth time from the first sample. Below 0.50 m/s the smooth time is now 0.22 s. Cruise is still 0.70 s, so the 2.8 s drag still reaches the grass. Turn ease is 6.2 rad/s instead of 7.5. Camera yaw error stays 0 while the stick is held (`cam_dist` 6.35). It still opens to the wide orbit after release.

Full lines are `docs/traces/v41_feel_before.txt` and `docs/traces/v41_feel_after.txt`. A full push starts at t = 0.20 s.

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
| **Grounding over 110 m** | Not met. Stance sole float is 32.93% (758/2302) after dropping flight frames and scoring the skinned sole. Worst bury −15.8 cm. Contact frames in the ruler set are 0.4 cm and 1.1 cm. The root was not dropped. |
| **Dither** | Unchanged from v40. On/off pair is `screenshots/v40/dither_on.png` and `dither_off.png`. |
| **Steep side view** | Unchanged from v40. `screenshots/v40/side_run_stop.png` keeps him in frame. |
| **iPhone frame time** | Not measured on a phone. `?debug=1` still copies `walk_30s` p50/p95/p99 and dropped frames. These stills are p50 33 ms on SwiftShader. No VRAM compression. |
| **Audio** | Unchanged from v40. Steps follow the plant and sit under the wave bed. No phone has played them. |
| **Replay** | Not this version. No new mode. |

## What the next version should do

Copy the standing sentence into that version's spec. The stance frames that are still above 1.5 cm, and the −15.8 cm bury, are the grounding gap. Do that without sinking `drag39_b.png`. Then time `game_v41` on an iPhone.
