shader_type spatial;

// Terrain tile material with whole-cell slicing along X (see slice_controller.gd).
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.95;

global uniform float slice_x;
global uniform bool slice_enabled;
global uniform bool slice_flip;

void vertex() {
	// MODEL_MATRIX includes the MultiMesh instance transform, so [3].x is the cell centre.
	float cell_x = MODEL_MATRIX[3].x;
	bool cut = slice_enabled && (slice_flip ? cell_x < slice_x : cell_x > slice_x);
	if (cut) {
		// Collapse the cube to a point: no fragments, no shadow, no discard cost.
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
}
