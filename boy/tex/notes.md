# Boy expression textures (v25)

Source: `/workspace/tripo_v25/boy_flateyes_rigged.glb` (1 mesh, 47,194 tris, 1 material, UV set `UVMap`).
All maps are 4096x4096 RGB PNG (lossless decode of the embedded JPEGs; same UVs, same size as the originals).

## Files (all in /workspace/tripo_v25/expr/)
| file | what |
|---|---|
| `albedo_idle.png` | original baseColor, decoded losslessly from the GLB JPEG (pixel-identical to the JPEG decode) |
| `albedo_smile.png` | eyes untouched; old mouth removed; wider, clearly upturned closed smile (corner curls) + pink blush |
| `albedo_cheer.png` | eyes removed -> `^^` arcs; big open mouth (dark red interior, pink tongue, dark brown outline); stronger blush |
| `albedo_sleep.png` | eyes removed -> relaxed closed lids (downward arcs, no lashes); small relaxed "o" mouth; light blush |
| `normal_{idle,smile,cheer,sleep}.png`, `mr_{idle,smile,cheer,sleep}.png` | **companion maps, REQUIRED for cheer/sleep** (see below) |
| `expr_front.png`, `expr_34.png` | 4 expressions side by side (idle/smile/cheer/sleep), each 1000x1000 -> 4000x1000. Cycles render, sun + sky light, bind pose, camera at 0 deg and 35 deg |
| `diff_{smile,cheer,sleep}.png` | changed-texel masks vs. original (1024 px preview) |
| `tools/` | the scripts used (Blender 5.0.1 headless for mesh export/renders; numpy/scipy/PIL for the rest) |

## IMPORTANT: the albedo alone is not enough
The Tripo normal map and metallic-roughness map ALSO contain the painted eyes: embossed iris/pupil/lid rings in the normal map
and a mirror-smooth (roughness ~0) red blob in the MR map. With only the albedo swapped, closed eyes show ghost iris rings and
glossy "eyeball" patches in 3D (I rendered this; it looks wrong). So I made companion maps with the same fill applied:
- idle  : original normal + MR
- smile : `normal_smile`/`mr_smile` (mouth flattened; eyes kept as original)
- cheer, sleep : `normal_cheer`/`mr_cheer` (identical to sleep) = eyes AND mouth flattened to the surrounding skin
In Godot: swap albedo + normal + roughness/metallic texture together per expression (3 textures per expression; 2 distinct normal/MR sets for
smile vs cheer/sleep, plus the originals for idle). If you want only one texture swap, you can use `normal_cheer`/`mr_cheer` for
smile too (the original eyes then lose their gloss/rim but the albedo eyes still read fine) - not tested visually.

## UV regions edited
Eyes and mouth are split over several UV islands in the 4096 atlas (texel coordinates, row,col):
- eye A: main island rows ~3190-3340, cols ~3770-3980 plus pieces at rows ~1010-1100/cols ~2850-2940 and rows ~60-160/cols ~2220-2370
- eye B: main island rows ~3950-4090, cols ~1600-1770, plus pieces at rows ~3995-4080/cols ~115-260 and rows ~3880-3930/cols ~480-570 and rows ~1240-1370/cols ~810-860
- mouth + nose strip island: rows ~1160-1350, cols ~2890-3030 (a rotated strip; ~5.5 canvas px per texel, i.e. the mouth is only a few texels thick)
- cheeks: blush is additive, multi-island, only on skin texels
Rather than hand-picking islands the edit is done by 3D position (below) so every island that is visible from the front/3-4 is handled consistently.
Hat, hair, brows, ears, neck, clothes are untouched: `verify.py` found 0 changed texels whose original colour was non-skin outside the eye/mouth zones, and 0 changed texels outside
the eye/mouth/cheek boxes (+ their feather ring). Changed 3D extent: x -0.084..0.093 m, z 0.645..0.758 m (face only), all on the front (y<-0.077).

## Method
1. Blender (bind pose) -> exported evaluated mesh (V, tris, per-loop UV).
2. **Position map**: rasterised every head triangle in UV space (4096^2) storing the 3D position per texel.
3. **Front canvas**: orthographic front rasteriser (6000 px/m, x -0.10..0.10 m, z 0.58..0.82 m) with z-buffer -> per canvas pixel: UV, triangle, depth.
   This is the "planning" space: strokes are designed on the front view in canvas px, in an eye-line-aligned frame (face tilt 2.4 deg).
4. **Lift**: each texel gets canvas coords (x,z) from its 3D position; visible = |depth - zbuffer|<5 mm. Padding texels (<=3 texels from visible) are extrapolated with the local gradient so strokes
   continue into island padding (no seam gaps under bilinear/mipmapped sampling).
5. **Removal**: eye/mouth masks found in canvas (non-skin colour within bbox, closed, dilated), lifted to texels (+34 canvas px around eyes, +24 around mouth because the original has a
   lighter halo ~25 px around the eyes), then **harmonic (Laplace) inpainting in canvas space** from skin pixels >=52 px outside the mask -> one smooth skin field that is identical across all islands.
   Each masked texel is replaced by that field sampled at its 3D position, with a 4-5 texel feather onto skin-like texels only (hair/brow never touched).
   Same fill applied to the normal and MR maps.
6. **Drawing**: strokes/shapes are analytic SDFs in canvas space (tapered Bezier strokes, polygon fills, ellipse tongue clipped to mouth, gaussian blush), evaluated per texel with 4x4 supersampling
   using the local texel footprint (so lines are anti-aliased in texture space but shaped in screen space). Line colour (70,34,16) for eyes (original outline is darker (26,7,0) but thinner at the lid; chosen
   slightly softer for the closed-eye style), mouth line (150,72,48) ~11 canvas px thick vs original ~7 px; blush (240,106,112) peak alpha 0.40 smile / 0.50 cheer / 0.28 sleep.
7. Rendered with the final maps in Blender Cycles for the montages and inspected at 1:1 front and 35 deg.

## Honest remaining issues
- **The mesh has real recessed eye sockets with a raised rim** (the idle eyes sit in them). With closed eyes you still see the oval socket edge/rim catching light: it reads as puffy closed eyelids (kind of cute, esp. sleep),
  but it is geometry and cannot be removed by textures. If you want it cleaner: flatten the socket in the mesh, or add a tiny eyelid mesh in Godot.
- The original skin has fine grain; inpainted regions are perfectly smooth (invisible at normal viewing, visible only with 5x contrast).
- Texel density at the mouth is low (~5 canvas px per texel): mouth lines are ~2 texels thick, a bit soft up close; the 4096 atlas is the limit.
- The cheer open mouth is flat painted (no teeth/inner geometry); at grazing angles (>60 deg) it foreshortens like any decal.
- Lashes were skipped for sleep. Eyebrows are unchanged in all expressions (not raised for cheer).
- The renders use the bind pose with the sun lighting I set up in Cycles, not the Godot GL-compat renderer; colours will differ slightly in game.
- Blender was not installed on the box any more; I downloaded 5.0.1 to `/workspace/blender_dl/blender-5.0.1-linux-x64/blender`.
