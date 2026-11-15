# v40 spec

Cut from `main` at `d1b1398` (v39). `docs/index.html` stays on v35 until the owner tries v39 on an iPhone. The web export is `docs/game_v40/`.

## Standing requirement

This sentence is the owner's requirement. It is copied here verbatim, and every later version's spec must carry it until the bar is actually met:

> 耐玩度要达到3A制作水准，操作细节和画面要细到离谱。新的版本做完要把这个要求放到下一个版本的要求中。直到达到这个水准。

`docs/AAA_BAR.md` is the checklist under that sentence. v40 does not claim the bar is met.

## This version

1. Walk, run, joystick, and camera on a real iPhone at a shippable feel: input response, acceleration and braking, turn smoothing, stick dead zone and curve, orbit and follow damping, no jitter or pops, 60 fps. SwiftShader is not that phone. The curves below are what the phone build runs; the phone still has to be timed by the owner.
2. 110 m grounding. Prove whether the v39 "77% float" is the probe or the drawn sole. Side views at flagged frames, measured on the skinned pose. Fix the probe if it is wrong. If the sole is really up, fix it inside the v38/v39 pipeline without failing `drag39.py`.
3. Dither on/off stills from the same camera.
4. Steep side view keeps the boy in frame (`side_run_stop` lost him off the bottom).
5. A device frame-time plan. No VRAM-compressed textures. Prims stay around 110k.
6. Audio: what the build plays, and what a phone still has to confirm.
7. Replay depth (throw, rest, day) only after the feel items, and no new mode.

## Hard gate

Every commit's export must pass `drag39.py`: full shins and both sandals in all three frames, and the wide frame 0.8 s after release. The PNGs are committed with the commit.

## Feel the build actually uses

- Stick dead zone stays 6% of the radius, so the review drag still clears it in one move.
- Above that, magnitude is `pow((mag - 0.06) / 0.94, 0.85)`. A full push is still 1. The run gate is still the raw magnitude (0.90 on, 0.82 off), so the review drag still runs.
- Speed eases toward the target with a 0.70 s smooth time while speeding up (same distance over the 2.8 s drag as the old stepped accel) and 0.16 s while braking.
- After the stick lifts, the settle is 0.28 s at 0.22 m/s, not 0.6 s at 0.40 m/s.
- Turning uses a 7.5 rad/s ease, capped by the old steer rate, so a small correction is not a snap and a sharp corner still kills speed.
- Explore follow is the v39 camera: critically damped while the stick is up, wide orbit by 0.8 s after release. `?side=1` pins the lens to the chest so a slope lift cannot drop him out of the bottom of a side still.
