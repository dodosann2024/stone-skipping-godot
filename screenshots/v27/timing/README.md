# v27 timing

## Budget (day dirt path @ mobile MID, frozen)

```
metric,value
canvas_size,390x844
window_size,(390, 844)
vp_size,(390, 844)
scaling_3d_scale,0.650
msaa_3d,0
positional_shadow_atlas_size,1024
render_info_objects_visible,29
render_info_draw_calls_visible,29
render_info_primitives_visible,316289
render_info_objects_shadow,0
render_info_draw_calls_shadow,0
render_info_primitives_shadow,215501
perf_draw_calls,76
perf_objects,177
perf_primitives,747323
perf_video_mem_mb,256.85
perf_texture_mem_mb,234.30
perf_buffer_mem_mb,22.55
time_fps,9.00
time_process_ms,149.276
time_physics_ms,0.063
lights_directional,2
lights_directional_shadow,1
lights_omni,15
lights_omni_shadow,0
lights_spot,0
lights_spot_shadow,0
particle_systems,6
multimesh_instances,4428
mesh_instances,102
sun_shadow_mode,0
sun_shadow_max_distance,28.0
sun_shadow_blur,2.50
refl_enabled,true
refl_scale,0.220
refl_every,2
refl_vp_size,(86, 186)
refl_level,1
night_on,false
player_pos,-0.60,4.16,6.20

```

vs pre-fix probe: leaf MultiMesh 7251→4428; scaling_3d 1.0→0.65; shadow dist ≤28 m orthogonal; refl starts low; atlas 1024; particles cut.

## Soft-GL phone proxy (Chromium SwiftShader, 390×844 DPR3, CPU 2×)

Absolute ms are not phone-real; compare before/after ratios.

```
tag=walk_path_before n=55 note=softGL_cpu2x_60f
dt_ms median=5283.100 p95=7116.300 p99=7349.700 max=7349.700 hitches_gt33=55
tag=walk_path_after n=55 note=softGL_cpu2x_60f
dt_ms median=1633.300 p95=2349.900 p99=2383.300 max=2383.300 hitches_gt33=55
tag=run_path_after n=40 note=softGL_cpu2x_45f
dt_ms median=2099.900 p95=2699.800 p99=3066.600 max=3066.600 hitches_gt33=40
tag=orbit_path_after n=40 note=softGL_cpu2x_45f
dt_ms median=1099.900 p95=1383.300 p99=1399.900 max=1399.900 hitches_gt33=40
```

walk_path median **5283 → 1633 ms (~3.2×)**; p95 **7116 → 2350 ms (~3.0×)**.

Native Godot/llvmpipe mobile-MID CSVs also under `*_after.csv` (same soft-GL caveat).
