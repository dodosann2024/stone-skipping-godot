# Standing bar — AAA production quality (v35+)

This is the **standing requirement for v35 and every later version**. It is not optional polish.

## Scope

- **No new gameplay modes.** Deepen and polish what already exists: walk/run, throw, sit/sleep/sun, day/night, camera, touch, audio, island life.
- **Replayability, control detail, and visuals** must be pushed toward genuine AAA production quality until that bar is honestly reached — not “good enough for a jam.”
- Each release must leave the experience **more replayable, more precise under the fingers, and more visually finished** than the last.

## Release blockers (must PASS before shipping)

1. **Grounding on slopes** — stick/drag from idle on forest grass must not bury the boy to shorts. Bone/mesh checks + CDP touch against the exported web build.
2. **Occluder dither** — foliage / leaf walls / barrels between camera and boy must open (screen-door dither) in the web Compatibility build; prove with on/off stills.
3. **Full island route** — ≥ **70 m** travel covering dock, sand, and every major grass slope; no snaps, ground error ≤ 2 cm.

## AAA self-audit checklist (every release)

Run after blockers pass. Fix the biggest gaps in-release when cheap; otherwise list them for the next version.

| Area | Ask |
|------|-----|
| **Feel** | Stick deadzone, breakout, spot-turn, run ramp — would a player feel lag, sink, or skate? |
| **Camera** | Follow on slopes/dock — legs readable? No hillside “burial” silhouette? Orbit smooth? |
| **Grounding** | Sandals on mesh_h; no mid-calf burial; dock lip continuous |
| **Character** | Idle/walk/run/sit/sleep silhouettes; face readable under hat; no mesh spikes |
| **World** | Foliage/props don’t swallow the boy; night lamps readable; water/shore clean |
| **UI / touch** | Joy + orbit dual-finger; buttons hit targets; banners don’t block play forever |
| **Audio** | Unlock path on iOS; footsteps match surface; no silence after gesture |
| **Perf** | iPhone 390×844 mid/low: stable frame time; no hitch on first walk |
| **Replay** | Same 2 minutes of island life still interesting — lighting, path, throws, rest |

## What “done” means

The bar is reached only when a cold playthrough on the **live Pages web build** (iPhone emulation + real CDP touch) feels finished: grounded, readable, responsive, and worth coming back to — without inventing new modes to hide thin systems.
