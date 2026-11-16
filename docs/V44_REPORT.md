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

## Pebble, skip, bench, canopy

Same export, 390×844. The grip is still a 5–6 cm pebble on `mixamorig_RightHand`. It is a lighter stone with a rim highlight. `throw_s2` shows it in the fingers (66,267 prims, 126.7 ms). `throw_s4` shows it at the head of a thin soft trail over the water.

The skip strip is the same throw camera. `skip_2` puts a white droplet crown on the water, a small dark contact mark under it, and the trail back toward the hand (63,603 prims, 125.0 ms). `skip_3` leaves a white foam patch. `skip_4` shows the next crown further out while that foam is still there. The foam fades over about a second.

The bench lie is the standing rest pose turned onto its back. In `bench_s2` the body runs along the slats, the head and hat are at the right-hand end, the hands rest on the stomach, and the feet are on the slats (74,203 prims, 139.2 ms). `ham_s1` is the same check on the hammock: the body is in the cloth, the head is supported, the arms are crossed on the chest (77,471 prims, 119.5 ms).

`loc_4` looks up the dirt path under two palms that lean in from either side, with fronds in the upper frame. The far palms still swap to the existing card. 78,627 prims, frame 127.2 ms, walk p95 144.9 ms.

Route after those palms moved: **4338** stance samples, **100%** inside ±1 cm, skate max **0.25 cm**, walk skate **0.00 cm**, `shin_min=1.00`.

## Still not at the bar

- SwiftShader on these frames is about **120–145 ms**. That is not 60 fps, and it is not an iPhone.
- The 6 cm pebble is readable in the hand and at the head of the flight trail. At the skip, the crown and the dark contact mark read; the stone itself is still only a few pixels and is easy to lose in the splash.
- The droplet crown, the trail, and the foam patch are visible at this phone size. The shader ring is in the sea shader and only a faint brighter band around the foam. It is not a crisp leading edge.
- The bench lie is a straight rest pose on the slats, not a crumpled sit. It is not a tailored sleep clip, and the hat sits at the end of the bench rather than on a pillow.
- `loc_4` has trunks and fronds over the path. The two nearest palms lean across the portrait frame, so the crown is partly cut off at the top. It is not the v40 colonnade.
- The sea depth and the inland colours from the previous pass are unchanged. Prims on the frames above stay under 93k.
