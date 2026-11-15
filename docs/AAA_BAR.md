# Standing bar — AAA production quality (v35+)

This is the **standing requirement for v35 and every later version** (v36 included). It is not optional polish. Control and visual detail must stay **细到离谱** — Steam-level smoothness on a real iPhone: **60 fps**, ~**100k prims** budget, **no VRAM-compressed textures**.

## Scope

- **No new gameplay modes.** Deepen and polish what already exists: walk/run, throw, sit/sleep/sun, day/night, camera, touch, audio, island life.
- **Replayability, control detail, and visuals** must be pushed toward genuine AAA production quality until that bar is honestly reached — not “good enough for a jam.”
- Each release must leave the experience **more replayable, more precise under the fingers, and more visually finished** than the last.

## Release blockers (must PASS before shipping)

1. **Grounding (exact collision + foot IK)** — body Y and soles from rendered-mesh collision (terrain tris + dock deck boxes). No walk fallback to analytic `ground_h` / sea floor. Real two-bone foot IK; stance sole −1.0…+1.5 cm vs skinned verts; no leg verts below surface; pelvis step ≤ 3 cm/frame over ≥ **100 m**. Prove with geometry route + CDP touch on the exported web build. Do not weaken tests (e.g. skipping double-support frames).
2. **Occluder dither** — foliage / leaf walls / barrels between camera and boy must open (screen-door dither) in the web Compatibility build; prove with on/off stills.
3. **Full island route** — ≥ **100 m** travel covering dock lip, sand, and every major grass slope; no snaps; stance within the sole bar above.

## AAA self-audit checklist (every release)

Run after blockers pass. Fix the biggest gaps in-release when cheap; otherwise list them for the next version.

| Area | Ask |
|------|-----|
| **Feel** | Stick deadzone, breakout, spot-turn, run ramp — would a player feel lag, sink, or skate? |
| **Camera** | Follow on slopes/dock — legs readable? No hillside “burial” silhouette? Orbit smooth? |
| **Grounding** | Sandals on collision tris/deck; stance −1…+1.5 cm; dock lip continuous; no analytic sea fallback |
| **Character** | Idle/walk/run/sit/sleep silhouettes; face readable under hat; no mesh spikes |
| **World** | Foliage/props don’t swallow the boy; night lamps readable; water/shore clean |
| **UI / touch** | Joy + orbit dual-finger; buttons hit targets; banners don’t block play forever |
| **Audio** | Unlock path on iOS; footsteps match surface; no silence after gesture |
| **Perf** | iPhone 390×844 mid/low: stable frame time; no hitch on first walk |
| **Replay** | Same 2 minutes of island life still interesting — lighting, path, throws, rest |

## What “done” means

The bar is reached only when a cold playthrough on the **live Pages web build** (iPhone emulation + real CDP touch) feels finished: grounded, readable, responsive, and worth coming back to — without inventing new modes to hide thin systems.
