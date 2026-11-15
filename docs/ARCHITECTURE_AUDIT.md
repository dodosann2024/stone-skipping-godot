# Architecture audit — stone-skipping Godot (v36)

**Status:** read-only diagnosis. WIP sink patches on the branch are **incomplete experiments** (`f8dca24`); do not ship them as a fix. Refactor waits for product confirmation.

**Scope read:** `main.gd` (~7583 lines), `boy.gd` (~2891), `island.gd` (~2972), `boy_foot_late.gd`, `joystick.gd`, `mobile_quality.gd`, `debug_hud.gd`, `project.godot`, `export_presets.cfg`, `docs/AAA_BAR.md`, cutout/leaf shaders, and the CDP / ground-IK test pattern under `dev/`.

---

## Plain-language summary (for non-programmers)

The game has grown through **36 versions of stacked patches**. Three giant files (`main`, `boy`, `island`) each try to own “where the boy stands,” “where his feet are,” and “where the camera looks,” often **in the same frame, in different order, using different height numbers**.

That is why you see the same pattern over and over:

- The **debug number** says “grounded” (or even “floating a few cm”).
- The **picture on the phone web build** shows legs cut off at the ankles or knees.
- Fixing one symptom (camera framing, contact blobs, sole pad, foliage cone) **moves the bug** instead of ending it.

**The systemic reason (not a single magic constant):**

1. **The body root** is placed with one ground ray (good: collision from the drawn terrain).
2. **The shoes you see** come from the **animation mixer** skinned on the web (Compatibility renderer).
3. **Foot IK** writes a *different* bone channel (`bone_global_pose_override`) that the web skinning path often **does not draw**.
4. **Debug / in-editor tests** frequently measure the IK channel or “ankle − a pad,” so they can PASS while the exported picture still shows burial.
5. On top of that, **display interpolation**, **model lifts**, **pelvis drops**, and **old offsets** (`SOLE_NUDGE`, `FLOOR_OFFSET`, bilinear `mesh_h`) still compete in the same frame.

**What to do next (after you confirm):** one ordered pipeline, one ground query, one owner per concern, and tests that screenshot the **exported web build** the way a player sees it—not just print bone math in the editor.

---

## (a) Per-frame data flow (actual)

Engine: Godot **4.7.2**, renderer **`gl_compatibility`**, `physics_ticks_per_second=60`, **`physics_interpolation=false`** in `project.godot` (manual lerp instead). Web export is **single-threaded** (no SharedArrayBuffer). Boy `process_priority = 40` (runs after default `main`).

### Physics tick (`main._physics_process`)

| Step | What | Transform used |
|------|------|----------------|
| Latch | On first physics step of a render frame: `_body_pos_prev ← _body_pos` | physics state |
| Explore | `_explore_tick`: joystick → wish → accel → `_try_move` → `_surface` Y | writes **`_body_pos` / `player.global_position`** (physics) |
| Stone | Flying/sinking substeps | stone only |

Explore Y policy today: snap **up** to `_surface` immediately; ease **down** ≤ 2.9 cm/frame (AAA pelvis-step bar).

### Idle / render frame (`_process` + `process_frame`)

| Order | Who | What | Transform |
|------|-----|------|-----------|
| 1 | `main._process` (priority 0) | `_interp_body_pose()` — lerp XZ between physics samples; **re-sample Y at display XZ** via `_surface`; snap-up / ease-down | **display** `player.position` |
| 2 | `boy._process` (priority 40) | AnimationTree mixer → `_polish_gait` → `_update_foot_ik` (clears overrides, sets markers, pelvis/contact lift on **model**) | skeleton + **model.position** |
| 3 | `main._process` continued | rest/throw ticks, `_update_camera`, foliage cutout uniforms | camera + shaders |
| 4 | `SceneTree.process_frame` | `FootPlantLate`: `_reassert_foot_plants` → blob → `_upload_foot_ao` → `_export_ground_probe` | late plant + HUD |

**Intended story:** input → move → root on collision → animate → plant feet → camera looks at final pose → HUD.

**Actual story:** root Y is written **twice** (physics + display interp); feet are planted **twice** (`_update_foot_ik` then late reassert); `model.position` is written in polish, IK, and late plant; camera runs **before** late plant; HUD is refreshed **after** late plant—so camera and soles can be one step out of agreement on hitchy web frames.

```
Input (Joystick / touch)
  → main._explore_tick (physics): move_vel, face_yaw, _body_pos.y = collision_h
  → main._interp_body_pose (process): display player.position (Y from _surface @ display XZ)
  → boy mixer + polish + early IK (process prio 40)
  → main camera + foliage cut (still process)
  → FootPlantLate (process_frame): analytic plant + model lift + __ground HUD
  → GPU skin Compatibility mesh (mixer poses; overrides unreliable)
```

---

## (b) Writers and competing systems

### Who writes the boy’s position / Y

| Writer | File | Notes |
|--------|------|-------|
| `_explore_tick` | `main.gd` | Physics root Y from `_surface` → `collision_h` |
| `_interp_body_pose` | `main.gd` | Overwrites `player.position` every render frame |
| Rest / throw / demo paths | `main.gd` | Many direct `player.position = …` / `ground_y = …` |
| `model.position` | `boy.gd` | `model_base`, `_pelvis_drop_s`, `_contact_lift`, hip sway — **mesh height relative to root** |
| Capsule | `boy.gd` | CharacterBody3D shape; vertical resolve intentionally skipped |

### Who writes feet / bones

| System | Active in explore walk? | Mechanism |
|--------|-------------------------|-----------|
| AnimationTree mixer | **Yes** | What Compatibility **draws** |
| `TwoBoneIK3D` node | Created, then **forced off** (`active=false`, `influence=0`) | Dead weight / footgun if `force_update` re-runs modifiers |
| Analytic `_solve_two_bone` + `_plant_foot_override` | **Yes** (best-effort) | `set_bone_global_pose_override` |
| `_update_foot_ik` | Yes | Clears overrides, sets targets, model Y |
| `_reassert_foot_plants` (late) | Yes | Final overrides + `_contact_lift` |
| Sit/lie `plant_feet_on_plane` / `plant_feet_soft` | Rest only | Separate stack |

### Ground samplers (still all reachable)

| API | Role today |
|-----|------------|
| `island.collision_h` / `ray_ground` | **Authoritative walk** (terrain tris + dock boxes) via `main._surface` |
| `Island.mesh_h` | Deprecated bilinear; still in file; comments warn not to use for feet |
| `Island.ground_h` | Analytic heightfield; still used to **build** mesh, place props, and as **fallback** inside `collision_h` on miss |
| `Island.ground_err` | Diagnostic vs `mesh_h` |
| `boy.ground_fn` / `ground_ray` | Callables into main/island for feet |

Collision build (`island._build_ground_collision`) copies **rendered terrain faces** into a concave shape—correct idea—then adds many deck boxes and analytic fallbacks that can still disagree at lips / misses.

### Sole / height offsets (layered)

| Name | Intent | Reality |
|------|--------|---------|
| `FLOOR_OFFSET` | Authored alignment | Barely used; easy to confuse with live plant |
| `SOLE_NUDGE` | v34 root push (±cm) | Forced **0** for API compat; tests still print it |
| `sole_offset` | Ankle→sole (measured ~8–9 cm) | Measurement formula changed across WIP; unstable |
| `SOLE_CLEAR` | Extra pad | Tuned every complaint (4 cm → 5.5 → 0.8 cm) |
| `_contact_lift` | Model Y to fix burial when overrides don’t draw | Latest WIP; fights float readings |
| `_pelvis_drop(_s)` | Lower hips to planted feet | Capped / zeroed in WIP; still written in multiple places |

### Camera writers

Explore follow (critically damped + stick hard-lock), fixed orbit, rest framing, throw/stone cams, view mode, demo tracks, crest LOS lift in `_apply_camera`, `__frame` UV gate. Stick-lock was added so framing tests pass; foliage and grounding were patched separately.

### Contact visuals

Hip blob (often forced off), per-foot discs (hidden while locomoting), terrain foot-AO UVs from late plant—another “looks grounded” channel that can lie if soles are wrong.

---

## (c) Why in-engine tests say grounded while the web export shows sunk legs

**Systemic reason (evidence-backed, not a one-line guess):**

1. **Different pose channels**  
   - **Drawn on web Compatibility:** AnimationTree / mixer skinning (see `dev/v24_shots.gd`: *“Compatibility skinning only follows the mixer”*).  
   - **Written by foot IK:** `bone_global_pose_override` + optional `force_update` (which also risks re-running `TwoBoneIK3D`).  
   - **Measured by many probes / HUD history:** override ankles, or `body.y − surface`, or CPU skinning that disagrees with GPU.

2. **Different clocks**  
   Physics places the capsule; display interp moves him again; boy animates; late plant runs after camera. Editor headless often advances frames in a tidy order; Chromium + SwiftShader + variable `phys/f` (often 2) exposes the seams.

3. **Different “ground” meanings**  
   Body on `collision_h` ⇒ `body_gnd_cm = 0` while shoes (mixer mesh) are still underground ⇒ classic **`gnd 0.0cm` with knee-deep stilts**. Later HUD switched toward soles, but sole math oscillated (bind inverse vs rest inverse vs ankle−offset) and could read **float** while the picture was buried, or the reverse.

4. **Tests that never see the export**  
   Route / ground_ik scripts in the editor can PASS the AAA sole bar on bone math. The user’s independent CDP script on `docs/game_v36` is the ground truth—and it still showed burial after framing was fixed.

So: **the product is not one wrong constant; it is split ownership of “contact” across root Y, model Y, override bones, mixer bones, and HUD.**

---

## (d) Root causes behind *all* user complaints (together)

| Complaint | Shared root | Contributing machinery |
|-----------|-------------|------------------------|
| **Sinking / floating** | No single “final posed soles vs collision” owner that the **renderer** obeys | Mixer vs overrides; `_contact_lift` / pelvis / SOLE_*; display Y vs physics Y; sole measure drift |
| **Stutter** | Hitch amplification across stacked smoothers | Manual physics interp + multi physics steps/frame; quality scale; cutout every frame; heavy island |
| **Delayed drag response** | Move intent gated by spot-turn / settle / accel curves | Spot-turn hysteresis (partially fixed); settle stroll after release; run ease-in |
| **Teleport on run** | Pose state jumps when prev/display/physics disagree | `_body_new_frame` latch helps; wall-slide lateral cap; mode switches still snap |
| **Camera loses him / bad switch** | Camera not locked to **post-plant** pose; modes fight | Follow vs fixed vs rest; crest LOS; stick hard-lock; camera before late plant |
| **Foliage hides him** | Occlusion treated as a shader knob, not part of pose pipeline | cutout cone + `near_fade`; MID/LOW tiers raise near-fade (more leaves vanish, walls remain); bush at boy depth |

These are not six separate bugs. They are symptoms of **no single ordered pipeline** and **no single source of truth for the posed character**.

---

## (e) Dead code and hacks to delete (refactor targets)

- **`TwoBoneIK3D` node** while analytic IK is the real plant (keep one).
- **`SOLE_NUDGE` / unused `FLOOR_OFFSET` live paths**; keep a single `sole_offset` measured once.
- **Deprecated `mesh_h` / `ground_err` gameplay call sites**; keep analytic `ground_h` only for mesh authoring / prop placement, not walk.
- **Double plant:** `_update_foot_ik` vs `_reassert_foot_plants` doing overlapping work.
- **Pelvis drop + contact lift + SOLE_CLEAR** as three knobs for one problem.
- **Blob / disc systems** that re-encode contact already owned by shadows / AO (or one clear contact decal).
- **Version archaeology comments as control flow** (“do not force_update”, “Compatibility only follows mixer”) without a single documented contract.
- **`main.gd` / `boy.gd` god-objects** (7.5k / 2.9k lines) mixing input, modes, camera, throw sim, rest, probes, and IK.

---

## (f) Refactor plan (after confirmation)

### Ownership model (one source of truth each)

| Concern | Owner module | Rule |
|---------|--------------|------|
| Move intent | `input_joystick` + `player_controller` | Stick → wish velocity / facing only |
| Root XZ/Y | `player_controller` + `ground` | **One** query: `collision_h` / `ray_ground` against render-mesh collision; write physics pose once |
| Display pose | `player_controller` | Optional interp of **XZ only**; Y always from ground at display XZ (or enable engine interpolation consistently—don’t mix) |
| Locomotion anim | `locomotion_anim` | Mixer only; no foot overrides here |
| Foot contact | `foot_ik` | **After** anim, **before** camera; must affect **what Compatibility draws** (local bone poses or a Compatibility-safe path—not a second ignored channel) |
| Camera | `follow_camera` | Reads **final** posed AABB / head-feet after foot_ik |
| Occlusion | foliage cutout fed by **final** boy focus | Same pose the camera uses |
| HUD / tests | measure **rendered** soles on export | Same path as CDP screenshots |

### Ordered per-frame pipeline (target)

```
physics:  input → integrate XZ → root Y = ground(xz)
process:  display XZ interp → AnimationTree
          → foot_ik (writes drawable poses) → force consistent skin update
          → camera from final pose → cutout focus
          → export __ground / __frame from same sole verts
```

No late “mystery” writer after the camera without also updating the camera. No second ground sampler for feet.

### Module split (suggested files)

- `player_controller.gd` — CharacterBody, move, modes explore glue  
- `ground.gd` — collision_h / ray only (island keeps mesh build)  
- `locomotion_anim.gd` — tree, phase, footfalls  
- `foot_ik.gd` — one plant implementation  
- `follow_camera.gd` — explore/rest/throw framing  
- `input_joystick.gd` — already mostly separate  
- `main.gd` — scene wiring, throw sim, UI (shrink aggressively)

### Tests that measure the **rendered** web result

1. Keep `dev/cdp_sink_v36.mjs` (and framing CDP) as **release blockers** on `docs/game_v36`.  
2. Assert from screenshots **and** `__ground`, but `__ground` must be defined as: skinned sole verts from the **same pose channel the GPU used that frame**.  
3. Fail the bar if shoes are missing in A/B/C stills even when numbers look fine (visual gate).  
4. Editor route tests become **smoke only**; they cannot alone greenlight grounding.  
5. Preserve `docs/AAA_BAR.md`: sole −1…+1.5 cm, pelvis ≤ 3 cm/frame, ≥100 m route, foliage dither, iPhone 60 fps, no VRAM compression, **do not switch `docs/index.html` until ready**.

### Constraints to keep

- Visual style, island content, AAA_BAR, iPhone 60 fps budget (~100k prims, quality ladder).  
- Exact terrain-tri collision as the walk surface (right idea—keep; delete competing samplers).

---

## Evidence snapshots (this branch)

- User CDP on export: burial with `gnd 0.0cm` (body-vs-surface HUD).  
- After sole HUD WIP: `gnd 0.7cm` / `8.7cm` while A still showed missing shoes; C sometimes showed a visible sandal—**numbers and picture still not one system**.  
- Framing gate (prior commit) can PASS while grounding fails—proves orthogonal patches.  
- WIP commit `f8dca24`: incomplete contact-lift / no_override experiment—**stop tuning; refactor instead**.

---

## Ask before coding the refactor

Please confirm:

1. Proceed with the module split + single pipeline above.  
2. Accept that Compatibility foot contact must be solved in the **drawable** pose path (not another override-only band-aid).  
3. CDP web stills remain the grounding source of truth for merge.
