shader_type spatial;

// Water voxel with whole-cell X slicing.
// Oxygen view: coloured by dissolved oxygen (INSTANCE_CUSTOM.r, mg/L); unsliced, the surface shows
// the depth-averaged DO of each column from column_do (r = mean, g = 1 where wet), blended between columns.
// Nature view (global water_view = 1, ignored while slicing): clear water tinted by depth, with
// animated ripples and sparkles. INSTANCE_CUSTOM.g = column depth, .b = depth below the surface (cells).
#include "res://shaders/slice_clip.gdshaderinc"

global uniform float water_view;

uniform sampler2D gradient : source_color, repeat_disable, filter_linear;
uniform sampler2D column_do : hint_default_black, repeat_disable, filter_linear;
uniform vec2 column_origin = vec2(0.0);
uniform vec2 column_size = vec2(1.0);
uniform float max_do = 14.0;
uniform float emission_strength : hint_range(0.0, 1.0) = 0.2;
uniform vec4 shallow_color : source_color = vec4(0.30, 0.74, 0.76, 1.0);
uniform vec4 deep_color : source_color = vec4(0.05, 0.36, 0.52, 1.0);
uniform float deep_cells = 9.0;
uniform float ripple_strength = 0.35;

varying float v_do;
varying float v_column_depth;
varying float v_depth;
varying vec3 v_world;
varying vec3 v_normal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float wave(vec2 p, float t) {
	return noise2(p * 0.9 + vec2(t * 0.35, t * 0.2)) * 0.6 + noise2(p * 1.9 - vec2(t * 0.2, -t * 0.33)) * 0.4;
}

void vertex() {
	if (slice_cut(MODEL_MATRIX[3].x)) {
		VERTEX = vec3(0.0);
	}
	v_do = INSTANCE_CUSTOM.r;
	v_column_depth = INSTANCE_CUSTOM.g;
	v_depth = INSTANCE_CUSTOM.b;
	v_normal = NORMAL;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float nature = slice_enabled ? 0.0 : clamp(water_view, 0.0, 1.0);
	bool top = v_normal.y > 0.5 && v_depth < 0.5;
	float do_value = v_do;
	if (top && !slice_enabled) {
		// Dividing by the wet weight keeps dry neighbours out of the blend at the shore.
		vec2 column = texture(column_do, (v_world.xz - column_origin) / column_size).rg;
		do_value = column.g > 0.001 ? column.r / column.g : v_do;
	}
	vec3 oxygen = texture(gradient, vec2(clamp(do_value / max_do, 0.0, 1.0), 0.5)).rgb;

	float sparkle = 0.0;
	if (top) {
		vec2 p = v_world.xz;
		float e = 0.12;
		vec2 slope = vec2(wave(p + vec2(e, 0.0), TIME) - wave(p - vec2(e, 0.0), TIME),
				wave(p + vec2(0.0, e), TIME) - wave(p - vec2(0.0, e), TIME)) / (2.0 * e);
		float strength = ripple_strength * mix(0.4, 1.0, nature);
		vec3 n = normalize(vec3(-slope.x * strength, 1.0, -slope.y * strength));
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
		sparkle = smoothstep(0.8, 0.92, wave(p * 1.4 + 7.0, TIME * 1.3));
	}

	float depth = top ? v_column_depth : v_depth + 1.0;
	vec3 natural = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, 1.0, depth / deep_cells));
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	natural = mix(natural, vec3(0.80, 0.93, 1.0), fresnel * 0.35);
	natural += vec3(0.9, 1.0, 1.0) * sparkle * 0.3;

	ALBEDO = mix(oxygen, natural, nature);
	EMISSION = oxygen * emission_strength * (1.0 - nature);
	ROUGHNESS = mix(0.35, 0.06, nature);
	SPECULAR = mix(0.5, 0.75, nature);
}
