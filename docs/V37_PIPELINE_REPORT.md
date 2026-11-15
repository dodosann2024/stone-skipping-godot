# v37 pipeline refactor — acceptance report

## Line counts (before → after)

| File | `main` (pre-refactor) | v37 |
|------|----------------------|-----|
| `main.gd` | 6873 | 7601 |
| `boy.gd` | 2265 | 2494 |
| **New modules** | — | `ground.gd` 51, `foot_ik.gd` 287, `player_controller.gd` 30, `follow_camera.gd` 30, `locomotion_anim.gd` 24, `input_joystick.gd` 4, `boy_foot_late.gd` 83 |

Net: owners extracted; `boy.gd` still holds Tripo/sit/face/throw glue but **one plant path** (`FootIK` drawable `set_bone_global_pose`). `main.gd` grew slightly from probe/HUD wiring + camera defer; walk Y goes through `PlayerController`/`Ground` only.

## Pipeline order (per frame)

`input → move (physics) → ground Y once → mixer/anim → FootIK drawable bake → camera/cutout (process_frame) → HUD/__ground from same sole verts`

## CDP (exported `docs/game_v37`, not `docs/index.html`)

- **Sink:** `CDP_SINK PASS` — samples=51 fails=0 gap_min=0.80 gap_max=0.80 cm
- **Frame:** `CDP_FRAME PASS` — samples=48 fails=0 margin_min=0.107 (central 60%)
- **Editor GIK:** `GROUND_IK PASS` travel=236.09 m max_pelvis_step=2.9 cm
- **Dock stills:** sole 0.80 cm (`cdp_dock_idle.png`, `cdp_dock_side.png`)
- **Stills:** 42 under `screenshots/v37/` (spawn/walk/run/stop/idle, sand/grass/slope/dock, side close-ups, 8-dir, slope up/dn)

## Scripts

- `dev/cdp_sink_v37.mjs` — real CDP touch pattern
- `dev/cdp_frame_v37.mjs` — framing gate

## Unchanged

- `docs/index.html` still points at **v35**
- `docs/AAA_BAR.md` kept (−1…+1.5 cm soles, ≤2.9 cm pelvis/frame, ~100k prims, no VRAM-compressed textures)
