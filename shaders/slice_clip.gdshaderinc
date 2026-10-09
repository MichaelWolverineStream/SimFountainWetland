// Whole-cell slicing along X, driven by slice_controller.gd.
// MODEL_MATRIX includes MultiMesh and particle instance transforms, so MODEL_MATRIX[3].x is the
// instance origin. Cut instances collapse to a point: no fragments, no shadow, no discard cost.
global uniform float slice_x;
global uniform bool slice_enabled;
global uniform bool slice_flip;

bool slice_cut(float origin_x) {
	return slice_enabled && (slice_flip ? origin_x < slice_x : origin_x > slice_x);
}
