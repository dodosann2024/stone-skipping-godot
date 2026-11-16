# v44 feel and scene

Branch `cursor/v44-feel-scene-d4ce`, cut from `main` at `0c03889`. `docs/index.html` still points at v35. Trial build: `docs/game_v44/game_v44.html`. Not merged.

The spec, including the audit and the standing sentence, is `docs/V44_SPEC.md`:

> 耐玩度要达到3A制作水准，操作细节和画面要细到离谱。新的版本做完要把这个要求放到下一个版本的要求中。直到达到这个水准。

Stills are Chrome screenshots of that page at 390×844 after the export in this commit. Textures are uncompressed (`vram_texture_compression` off). The grounding files were not edited.

## Follow-up on the stills

The first eight throw frames did not show a stone, and a rail rope crossed that camera. The stone in those frames is now a dark flat disc pushed out of the fist toward the camera. `skip_0`–`skip_3` place the same disc on the water with splash rings. The rail ropes start inland of the tee.

`loc_3`–`loc_5` were an empty grass sheet because that camera looks up the dock and the props sat off to the side. A garden of palms, bushes, barrels, a rope fence and flowers now flanks the dock and the path inland. Planks pick up a wear term. The sea adds a shore lip and broad light/dark wave bands, and the lace is kept at the shoreline instead of covering the water beside the dock.

Sit and stand strips: `bench_s0`–`bench_s3` and `ham_s0`–`ham_s3`. The overview is still the v40 spawn offset, `spawn.png`.

## What changed

- Walk and run share one speed curve. The outer ring of the stick eases into the run instead of jumping from about 0.67 m/s to 2.30 m/s. Clip changes blend. A large facing error slows the root so a reverse does not slide at full speed. Release uses `STOP_S`.
- The stick uses the finger on the press, hides the knob inside the same dead zone the body uses, and eases home on release. An orbit drag pauses follow. 固定视角 toggles follow. 观景 holds 40°. Pitch stays inside 30–40°, and letting go of the stick no longer zooms out to 8.8 m.
- Sitting and standing play the walk clip across the glide, with FootIK paused for that glide only.
- The pose stone is a dark flat disc held out of the fist. Skip frames put it on the water with rings.
- The sea mesh is 40×40 and the facet glint is weaker. More palms use the existing card LOD. Barrels have hoops, the boat has a gunwale and an oar, the hut has a porch step, and there is another mooring rope.

## Gates

| Gate | Result | Evidence |
|---|---|---|
| Route, 110 m | **Pass.** 3966 stance samples, **100%** inside ±1 cm. Skate max **0.00 cm**, walk skate **0.00 cm**, `shin_min=1.00`. | `screenshots/v44/m6/route.log` |
| Prims | **Under 93k on the frames read.** Throw **66,257**. Run off the dock **74,001**. Orbit **66,863**. A skip over open water **18,181**. | `throw_s2.png`, `loc_4.png`, `orbit_2.png`, `skip_2.png` |
| Walk / run | Six frames. The later frames show the dock, barrels, bushes and flowers, then the grass path. | `loc_strip.jpg`, `loc_0.png` … `loc_5.png` |
| Throw and skip | Eight pose frames with a dark stone, then four frames of the stone on the water with rings. The close throw no longer has a rope across the body. | `throw_strip.jpg`, `skip_strip.jpg` |
| Sit / stand | Bench: stand, sit, lie, stand. Hammock: stand, sleep, sleep, stand. | `bench_strip.jpg`, `ham_strip.jpg` |
| Overview | v40 spawn offset `(-5.5, 5.2, -7.5)`. | `spawn.png` |

## Pebble, ripples, grass, bench

The grip is a 5–6 cm flat grey pebble on `mixamorig_RightHand`, fingers bent around it, clearcoat on the rim. It stays in the fist until the low sidearm release. Flight frames add a short trail. Skips write expanding bands into the sea shader (gone by about 1.4 s) plus a spray of droplets; the sink adds a second band. Inland grass is olive, the path is dirt, and tufts sit beside it. The bench lie is framed from the side of the slats. Water beside the pier deepens as it leaves the posts.

This export reads throw **66,257**, release **62,871**, inland run **74,209**, orbit **66,871**. Route: 3966 samples, 100% within 1 cm, shin 1.00.

## Still not at the bar

- SwiftShader is still about **125–145 ms**. Not 60 fps, and not an iPhone.
- `throw_s0` still hides the pebble inside the closed fist. It shows in the loaded crouch (`throw_s2`) and just off the hand (`throw_s4`). The trail is a few dots.
- In `skip_2` the spray reads more clearly than the shader ring. There is no sheet of foam.
- `loc_4` is a dirt path with tufts, flowers and bushes. It is not v40's palm canopy. `orbit_2` is a deeper blue than the old cyan field; the patch beside the dock is still a fairly even surface.
- The bench lie is on the slats in the side frame. A small gap under the back can remain from the lie clip.
