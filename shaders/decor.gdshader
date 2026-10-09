shader_type spatial;
render_mode cull_disabled;

// Props (trees, grass, flowers, reeds, rocks, lily pads, ducks, fountain parts).
// Vertex colour alpha 1 marks parts tinted by INSTANCE_CUSTOM.rgb (see scripts/mesh_kit.gd).
// Slices along X by instance origin, like the terrain.
#include "res://shaders/slice_clip.gdshaderinc"

global uniform float water_view;

uniform float sway = 0.0; // tip displacement per height^2
uniform float sway_speed = 1.6;
uniform bool nature_only = false; // shown only in the Nature water view and when not slicing
uniform float flap = 0.0; // wing flap angle (radians) for parts beyond flap_body on either side of x = 0
uniform float flap_speed = 14.0;
uniform float flap_body = 0.03;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float rim : hint_range(0.0, 1.0) = 0.12;
uniform float backlight : hint_range(0.0, 1.0) = 0.25;

varying vec3 v_tint;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float shown = nature_only ? (slice_enabled ? 0.0 : clamp(water_view, 0.0, 1.0)) : 1.0;
	if (slice_cut(origin.x) || shown < 0.01) {
		VERTEX = vec3(0.0);
	} else {
		if (flap > 0.0 && abs(VERTEX.x) > flap_body) {
			float angle = sin(TIME * flap_speed + float(INSTANCE_ID) * 1.7) * flap;
			float reach = abs(VERTEX.x) - flap_body;
			VERTEX.y += reach * sin(angle);
			VERTEX.x = sign(VERTEX.x) * (flap_body + reach * cos(angle));
		}
		float h = max(VERTEX.y, 0.0);
		float phase = TIME * sway_speed + origin.x * 0.35 + origin.z * 0.27;
		VERTEX.x += sin(phase) * sway * h * h;
		VERTEX.z += cos(phase * 0.8) * sway * 0.6 * h * h;
		VERTEX *= shown;
	}
	v_tint = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	// Blades use upward normals on both sides.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec3 color = COLOR.rgb * mix(vec3(1.0), v_tint, COLOR.a);
	ALBEDO = color;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
	BACKLIGHT = color * backlight;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = color * fresnel * rim;
}
