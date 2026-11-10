// water.gdshader's planar reflection (reflection.gd) renders from the main camera mirrored under the sea,
// the only camera that is ever below the surface: in that pass whatever is under the water is dropped
// (and the camera cut-out, which only makes sense for the real camera, is skipped).
bool refl_pass(vec3 cam) {
	return cam.y < -0.2;
}
