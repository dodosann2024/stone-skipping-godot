# 海岛打水漂 · v44

`docs/index.html` stays on v35. This version exports to `docs/game_v44/`. No new gameplay. The play camera stays inside 30–40° down. Textures stay uncompressed. Prims stay at or under 110k, aimed near 93k. The grounding core is frozen.

「耐玩度要达到3A制作水准，操作细节和画面要细到离谱。新的版本做完要把这个要求放到下一个版本的要求中。直到达到这个水准。」

## Audit

Read as one loop: stick value, root speed, clip, camera, then the seated and throw states that borrow the same root.

### Walk, run, start, stop

- Root cause: crossing the run latch (`RUN_ON` 0.90) replaces a walk target of about 0.67 m/s with 2.30 m/s in one frame. `ACCEL_S` (0.70 s) then smears that jump, so the body and the clip do not agree.
- Root cause: `set_speed` calls `anim.play` with no blend, and the clip flips at 1.35 m/s and again at 0.08 m/s. Walk, run, and idle cut.
- Root cause: `speed_scale` is clamped to at least 0.85, so the first steps cycle at walk speed while the root is still near zero.
- Root cause: `STOP_S` is unused. Release uses `BRAKE_S` (0.16 s) and then hard-zeroes under 0.04 m/s, and the same release pulls the camera from 6.4 m out to 8.8 m. Stop reads as a zoom.
- Root cause: target speed is not reduced while `face_yaw` is still catching the stick, so a reverse keeps full speed and slides through the turn.

### Joystick

- Root cause: a press applies the stick origin, so the finger does nothing until the first drag.
- Root cause: the dead zone lives only in the mover. The knob travels inside a zone the body ignores.
- Root cause: release writes `value = 0` the same frame. The knob pops home, and that step is the whole re-center.
- Root cause: a second finger correctly misses the stick and becomes orbit, but the follow yaw keeps writing `yaw` while that drag is active, so look and follow fight.
- The response curve was `pow(m, 0.85)`, which makes small deflections hotter than a walk.

### Camera

- Root cause: follow yaw uses a fixed rate of 1.6, so a turn leaves the camera behind, and any speed above 0.3 m/s overwrites an orbit drag in the same frame.
- Root cause: letting the stick go selects `CAM_DIST_WIDE` (8.8 m). Start and stop zoom.
- Root cause: a close collision raises pitch toward 55°, outside the 30–40° decision, and then eases it back.
- Root cause: 观景 assigns 50° and the rig immediately eases pitch back to 35°. 固定视角 is an empty handler, so the lock does nothing.

### Sit and stand

- Root cause: `_glide` moves the root for 0.45 s while the idle clip is playing and FootIK is still planting. The body slides, the soles stay, and the sit clip blends in afterwards. Stand-up calls `clear_hold` first, then glides in idle, so getting up slides the same way.

### Throw

- Root cause: the live stone is a shaded 5.5 cm sphere with no trail, so it disappears against the sea. The splash is one small torus.
- The release itself is the side-arm signal at the low point of the whip. The old `_throw_release` lob is not called.

### Scene and the cyan spot

- Root cause: the sea mesh is 16×16 on a 90 m plane, and the shader adds a `pow(48)` glint on those facets. In the face view that facet is a small cyan disc by the hat.
- The hut, boats, barrels, ropes, and palm cards are real meshes, but the barrels are bare cylinders, the boat has no oar or gunwale, and the palm line is thinner than the v40 shore. `_distant_palms` is not called. That multimesh was the old sky blob, and it stays uncalled.

## Fixes

- Continuous stick-to-speed curve, a softer stop, a slower target while turning, and a blend on clip changes.
- Press uses the finger, the dead zone matches the knob, release eases back, and an orbit drag pauses follow.
- Camera distance stays put. Pitch stays inside 30–40°. 固定视角 toggles follow. 观景 holds 40°.
- Sit and stand play the walk clip for the glide, with FootIK paused for that glide only. The solver is unchanged.
- A larger flat stone, a short trail, and a second splash ring.
- A finer sea mesh and a weaker glint. More palms on the existing card LOD, hooped barrels, a finished boat, porch step, and another mooring rope.
