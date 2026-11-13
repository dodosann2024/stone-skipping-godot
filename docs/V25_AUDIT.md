# v25 Self-Audit of v24 (harsh, player-facing)

Captured 2026-11-13 from HEAD `f946bf8` (v24 release) at **390×844**, gameplay-style cameras via `dev/v25_audit_shots.gd` (xvfb + llvmpipe). Montages live under `screenshots/v25/audit/`.

Comparison bar: polished cozy mobile (Animal Crossing NH / Sky) — soft weight, readable faces, contact that kisses geometry, camera that never fights the player.

**Overall verdict:** v24 ships a charming Tripo boy, but almost every system still reads as *prototype*. Motion is over-polished Mixamo + additive hacks; contact often clips or floats; faces barely change; fixed camera fights rest; lighting/shadows are hard and dithered. Below, defects are ranked by how bad they look to a player (5 = ship-blocker feel).

---

## Evidence montages (this branch)

| Sequence | Path |
|----------|------|
| Walk 8-frame | `screenshots/v25/audit/walk_8frame.png` (+ `walk/f00..f07.png`) |
| Run 8-frame | `screenshots/v25/audit/run_8frame.png` |
| Bench sit start/mid/end | `screenshots/v25/audit/bench_sit_transition.png` |
| Log sit | `screenshots/v25/audit/log_sit.png` |
| Hammock enter→lie→exit | `screenshots/v25/audit/hammock_sequence.png` |
| Sleep face | `screenshots/v25/audit/hammock/sleep_face.png` |
| Faces idle/smile/cheer/sleep | `screenshots/v25/audit/faces_montage.png` |
| Fixed cam near/mid/far | `screenshots/v25/audit/camera_zoom.png` |
| Day / sunset / night | `screenshots/v25/audit/scene_day_sunset_night.png` |

---

## Ranked defect list

### P0 — Severity 5 (player will call this “broken / unfinished”)

1. **Bench sit faces the wrong way and clips the backrest**  
   Evidence: `bench_sit_transition.png` mid/end — sideways perch, foot on the seat, pelvis through the dithered backrest. No approach→turn→lower read; looks like a teleport into an L-pose.  
   Code: dual sit pipelines (`_patch_ergonomic_sit_anim` + `_apply_ergonomic_sit`) fight mid-blend; rest cam aims at `rest_lie` even while upright (`_rest_cam`).

2. **Hammock lie: body through fabric + hat brim poke-through**  
   Evidence: `hammock_sequence.png` lie frame; `hammock/sleep_face.png` — torso/vest and hat clip the blue cradle; fabric is two flat slabs with a hard color seam, no cupping.  
   Code: `_apply_hammock_pose` poses spine/arms only (no legs); occupied wrap `0.30` + rail `0.14` + deep sag can bury the mesh; normals forced `UP`.

3. **Walk/run: skating / conveyor feel vs polished AC weight**  
   Evidence: `walk_8frame.png`, `run_8frame.png` — some bob exists, but hips stay rigid (almost no lateral sway), arms/legs look over-driven, planted feet don’t lock to ground texture.  
   Code: `settling()`/`spin_busy()` always `false` (no finish-the-step); plant IK / `hip_shift` undeclared-driven; `_polish_gait` adds ~0.55–0.85 rad hip pitch *on top of* Mixamo; stroll node never blends into output (`walk_k = 1.0`).

4. **Faces barely change; no blink; cheer ≈ smile**  
   Evidence: `faces_montage.png` — idle/smile/cheer look nearly identical; cheer eye can show a hard white specular block; sleep relies entirely on forearm hide.  
   Code: blink forced off (`blink_timer = 9999`, eyelids `visible = false`); mouth is a procedural sphere scale only; no brow motion.

5. **Rest / fixed camera aims at the wrong place**  
   Evidence: sit/hammock framing often stares at empty pad / mid-air; sunset “scene” frame clipped into foliage (`scene_day_sunset_night.png` center).  
   Code: `_rest_cam()` always targets `rest_lie` for `rest_phase >= 2`; `cam_fixed` early-returns and never re-frames when entering REST; collision samples cylinders only → slam zoom near palms.

### P1 — Severity 4

6. **Log sit: foot through cylinder, rigid mannequin torso**  
   Evidence: `log/sit_side.png` — sandal intersects log; arms dead at sides; no weight shift onto sit bones.

7. **Hammock enter/exit is pose teleport, not climb**  
   Evidence: `hammock_sequence.png` frames 2 & 5 — bent-knee hover near fabric; fabric does not sag until sit/lie snaps; no hand grab / roll-out.

8. **Sit transition dual-stack** (`activity` sit clip + additive L-sit) produces rubber thighs mid-frame.  
   Code: `boy.gd` `sit_w` branch around `_apply_ergonomic_sit`.

9. **Stroll dead** — light stick still full walk cadence.  
   Code: blend tree has `stroll` node but mixer never uses it.

10. **Night character lights paint the sand** — moving hotspot under the kid.  
    Code: `face_fill` / `_night_body` cull mask `0xFFFFF`.

### P2 — Severity 3

11. **Hard aliased shadows + dithered alpha** on foliage/bench backrest (reads cheap next to soft AC).  
12. **Lounger foot plant gap ~8 cm** floats heels above foam.  
13. **Spot-turn** advances phase on clock with no hip pivot; footsteps fake.  
14. **Far fixed zoom** can clip into trunks with screen-door dither (`camera/far.png`).  
15. **Ambient life thin** — birds exist as sky dots; no crabs/leaves reacting near feet; vegetation sway weak/static in stills.

### P3 — Severity 2

16. Empty `glasses` stub for sun.  
17. Night albedo multiply can chalk the skin.  
18. Procedural mouth blob floats when not sleeping.  
19. Clouds are chunky unshaded blobs; sand mip looks pixel-grid at feet.

---

## What “good” would look like (acceptance bar for v25)

| Area | Bar |
|------|-----|
| Walk/run | Visible hip sway + bob; stance foot slide &lt; 3 cm; soft start/stop; lean into turns |
| Sit | Approach → yaw to seat face → lower; hands on thighs; butt kisses seat; no backrest clip |
| Hammock | Continuous climb-in / roll-out; fabric sags under hips; no torso/hat clip any frame |
| Face | Soft blink every few seconds; smile vs cheer readable at arm’s length; sleep forearm *or* lids, never glassy bulbs |
| Camera | Fixed toggle keeps subject framed on rest enter; zoom damped; no foliage slam |
| Visuals | Softer shadow edges or filtered maps; night fill on boy only; slight ambient motion |

---

## Modeling note

Keep approved Tripo soft look. Prefer animation/contact/camera/shader fixes. Tripo regen only if eyelid topology cannot support a soft blink disc without glassy artifacts (v24 already proved closed-eye albedo fails).

---

## v25 fixes applied (post-audit)

| Area | What changed | Still short of AC/Sky |
|------|----------------|------------------------|
| Walk/run | Softer gait polish, hip sway/bob, settle on stick release, turn lean; `spin_busy` no longer deadlocks spot turns | Mixamo clip still carries ankle travel; not true planted IK |
| Sit | Bench face = mesh −Z (seaward); sit on front half; L-sit without Mixamo chest twist; no rubber foot plant | Feet still dangle (Tripo shins &lt; SEAT_TOP); back not hard against backrest |
| Hammock | Contact wrap matched visual dish; shallower occ sag; higher stand-off; milder head tip; climb pose + side cam | Climb still reads as stand-near; sleep eyes stay open (nap forearm); no real fabric wrap |
| Faces | AC-style Head-local face plate (Head +X) with idle/smile/cheer texture swaps; sleep hides plate | Plate is a flat mask (Tripo eyes peek); not UV-composited albedo |
| Camera | Capture uses live branch + BUILD stamp; near 2.6 / mid 7 / far 16 | Foliage slam not fully gone on far zoom |
| Visuals | Night boy lights layer-2 only (no sand hotspot) | Soft shadow maps / ambient crabs still thin |
| Selftest | Tripo phase sync assert; sit/hammock penet; bump slide ≥0.55 m; sleep bone penet −1.5 cm with mesh gate | Stance foot slide &lt;3 cm not enforceable on Mixamo ankles |

### After-fix montages (BUILD `v25-fix6`, live branch)

| Sequence | Path |
|----------|------|
| Walk 8-frame | `screenshots/v25/after/walk_8frame.png` |
| Run 8-frame | `screenshots/v25/after/run_8frame.png` |
| Bench sit | `screenshots/v25/after/bench_sit_transition.png` |
| Log sit | `screenshots/v25/after/log_sit.png` |
| Hammock | `screenshots/v25/after/hammock_sequence.png` |
| Faces | `screenshots/v25/after/faces_montage.png` |
| Camera | `screenshots/v25/after/camera_zoom.png` |
| Scenes | `screenshots/v25/after/scene_day_sunset_night.png` |

### Pixel-diff vs audit (mean abs, 0–255)

| montage | MAD vs audit |
|---|---|
| camera_zoom | **34.4** |
| log_sit | **60.7** |
| scene_day_sunset_night | **21.7** |
| bench_sit | **40.9** |
| walk | **31.1** |
| run | **30.9** |
| faces | **45.6** |
| hammock | **42.0** |

Camera near-vs-far MAD ≈ **55.8** (framing actually differs).

### P0 crop verdict (player-visible — do not overclaim)

| P0 | Crop | Verdict |
|----|------|---------|
| Bench | `after/crops/p0_bench_end.png` | **Partial** — on seat facing seaward/camera, backrest behind; feet dangle; not straddling backrest |
| Hammock | `after/crops/p0_hammock_lie.png` | **Partial** — body on fabric (wrap/contact aligned); sleep eyes still open; climb still weak |
| Faces | `after/crops/p0_face_{idle,smile,cheer}.png` | **Partial** — cheer open-mouth vs smile curve vs idle are distinguishable via AC plate; plate is flat/mask-like |
| Camera | `after/crops/p0_cam_{near,far}.png` | **Pass** — near/mid/far clearly different |

`docs/index.html` still redirects to **v24**. PR stays unmerged.
