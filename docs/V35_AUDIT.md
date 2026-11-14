# v35 AAA self-audit

After blockers PASS (slope sink, foliage dither, ≥70 m route).

## Blockers (PASS)

| Check | Result |
|-------|--------|
| `SOLE_NUDGE` | was **+7.5 cm** in v34 (root cause of mid-calf / shorts burial); now **-1.4 cm** |
| Per-foot plant | pull-down only when floating; limited lift when buried on slopes |
| Slope follow cam | higher default pitch + ankle-line clearance lift |
| `route_walk_v32` | travel **106.35 m**, max_gnd 0, ratio 1.15 — PASS |
| `slope_drag_v35` | max_mesh_sink **0.0 cm** — PASS |
| `touch_cdp_v35` / `cdp_touch_v35.mjs` | CDP drag FEET_OK — PASS |
| `bush_cut_v35` | on/off diff **~12%** — PASS |
| `sit_stand_v34` | PASS |

## Fixed in this release (beyond blockers)

- Mute tip auto-hides in **4.5 s** (was 9 s) so it doesn’t park over the boy.
- Contact blob softened (less “cut at shorts” black plate).
- Standing AAA bar documented in `docs/AAA_BAR.md` for v35+.

## Biggest remaining gaps → v36

1. **Bush leaves that sit at the boy’s depth** (wrapping from behind) can still read solid; cutout is strong for mid-cone occluders but silhouette leaves need a dedicated near-boy open.
2. **Steep cross-slope plant** — one foot can still kiss into the rising mesh from low side cams; needs better per-foot pitch/roll IK.
3. **Grass blade cards** in the near field still look like flat green walls on mid/low tiers.
4. **Throw aim / swipe feel** on iPhone — force curve and release flick still a notch below AAA stickiness.
5. **Night path lamps** — pool falloff and boy readability under hat brim.
6. **Rest sit/sleep camera** micro-framing (face under brim, no shoulder crop).
7. **Replay hooks** without new modes: best-skip ghosts, path dust variety, wind/ambient layers.
8. **First-run chrome** — start overlay + mute tip + instruction stack still dense on 390×844.

## Explicitly out of scope

- No new gameplay modes (per standing bar).
