# v44 feel and scene

Branch `cursor/v44-feel-scene-d4ce`, cut from `main` at `0c03889`. `docs/index.html` still points at v35. Trial build: `docs/game_v44/game_v44.html`. Not merged.

The spec, including the audit and the standing sentence, is `docs/V44_SPEC.md`:

> 耐玩度要达到3A制作水准，操作细节和画面要细到离谱。新的版本做完要把这个要求放到下一个版本的要求中。直到达到这个水准。

Stills are Chrome screenshots of that page at 390×844 after the export in this commit. Textures are uncompressed (`vram_texture_compression` off). The grounding files were not edited.

## What changed

- Walk and run share one speed curve. The outer ring of the stick eases into the run instead of jumping from about 0.67 m/s to 2.30 m/s. Clip changes blend. A large facing error slows the root so a reverse does not slide at full speed. Release uses `STOP_S`.
- The stick uses the finger on the press, hides the knob inside the same dead zone the body uses, and eases home on release. An orbit drag pauses follow. 固定视角 toggles follow. 观景 holds 40°. Pitch stays inside 30–40°, and letting go of the stick no longer zooms out to 8.8 m.
- Sitting and standing play the walk clip across the glide, with FootIK paused for that glide only.
- The thrown stone is a larger flat light disc with a short trail and a second splash ring.
- The sea mesh is 40×40 and the facet glint is weaker. More palms use the existing card LOD. Barrels have hoops, the boat has a gunwale and an oar, the hut has a porch step, and there is another mooring rope.

## Gates

| Gate | Result | Evidence |
|---|---|---|
| Route, 110 m | **Pass.** 3903 stance samples, **100%** inside ±1 cm. Skate max **0.49 cm**, walk skate **0.00 cm**, `shin_min=1.00`. | `screenshots/v44/m6/route.log` |
| Prims | **Under 93k in the shots that were read.** Face **61,843**. Idle on the dock **65,405**. Walk **66,179**. Run **61,405**. Stop **68,593**. | `screenshots/v44/web/face.png`, `loc_0.png`, `loc_1.png`, `loc_4.png`, `loc_5.png` |
| Walk / run strip | Six frames from idle, first steps, walk, into the run, run, and stop. The run leaves the dock onto the grass. Both the dock and the grass show a body shadow. | `screenshots/v44/web/loc_strip.jpg`, `loc_0.png` … `loc_5.png` |
| Throw | Eight frames, 3/4 side. Crouch, low arm, follow-through, sandals on the planks. | `screenshots/v44/web/throw_strip.jpg`, `throw_s0.png` … `throw_s7.png` |
| Orbit | Four yaw steps at the 35° pitch. | `screenshots/v44/web/orbit_0.png` … `orbit_3.png`, `orbit_strip.jpg` |
| Overview | Same offset the v40 spawn shot used: `(-5.5, 5.2, -7.5)`. | `screenshots/v44/web/spawn.png` |

## Still not at the bar

- Frame time on this machine is SwiftShader, about **125–144 ms** (the walk p95 line on `loc_1` is **143.6 ms**). That is not 60 fps, and it is not an iPhone. Nothing here proves the phone budget.
- Sit and stand were not shot. The glide now plays a walk clip; that is unshown.
- The pier rope still crosses the throw. The stone is a flat unshaded disc, easier to see than the old grey sphere, and still not a textured rock.
- The extra palms, hoops, gunwale, oar and porch step are generated meshes. The shore is denser than v43 and it is not the old scanned prop set.
