shader_type spatial;

// Water voxel coloured by dissolved oxygen (INSTANCE_CUSTOM.r, mg/L), with whole-cell X slicing.
uniform sampler2D gradient : source_color, repeat_disable, filter_linear;
uniform float max_do = 14.0;
uniform float emission_strength : hint_range(0.0, 1.0) = 0.2;

global uniform float slice_x;
global uniform bool slice_enabled;
global uniform bool slice_flip;

varying float v_do;

void vertex() {
	v_do = INSTANCE_CUSTOM.r;
	float cell_x = MODEL_MATRIX[3].x;
	bool cut = slice_enabled && (slice_flip ? cell_x < slice_x : cell_x > slice_x);
	if (cut) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	vec3 color = texture(gradient, vec2(clamp(v_do / max_do, 0.0, 1.0), 0.5)).rgb;
	ALBEDO = color;
	EMISSION = color * emission_strength;
	ROUGHNESS = 0.35;
}
