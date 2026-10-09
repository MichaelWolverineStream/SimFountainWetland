shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Particle sprite for spray drops, splash rings and fireflies. Alpha comes from the particle
// colour (colour ramp); energy > 1 feeds the glow. Slices along X like everything else.
#include "res://shaders/slice_clip.gdshaderinc"

global uniform float water_view;

uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 1.0;
uniform bool billboard = true;
uniform bool soft_dot = true; // round soft sprite from the quad UV
uniform float blink = 0.0; // per-particle flicker amount
uniform bool clip_pixels = false; // slice per fragment (large meshes like the pump-zone ring)
uniform vec4 clip_rect = vec4(-1.0e6, -1.0e6, 1.0e6, 1.0e6); // xz min, xz max (clip_pixels only)
uniform bool nature_only = false; // shown only in the Nature water view and when not slicing

varying float v_blink;
varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float shown = nature_only ? (slice_enabled ? 0.0 : clamp(water_view, 0.0, 1.0)) : 1.0;
	if ((!clip_pixels && slice_cut(MODEL_MATRIX[3].x)) || shown < 0.01) {
		VERTEX = vec3(0.0);
	}
	if (billboard) {
		mat4 face = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		face = face * mat4(
				vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
				vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
				vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
				vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * face;
	}
	v_blink = mix(1.0, 0.5 + 0.5 * sin(TIME * 3.0 + float(INSTANCE_ID) * 2.39), blink) * shown;
}

void fragment() {
	if (clip_pixels && (slice_cut(v_world.x) || any(lessThan(v_world.xz, clip_rect.xy))
			|| any(greaterThan(v_world.xz, clip_rect.zw)))) {
		discard;
	}
	float alpha = COLOR.a * v_blink * color.a;
	if (soft_dot) {
		alpha *= 1.0 - smoothstep(0.3, 1.0, length(UV - vec2(0.5)) * 2.0);
	}
	ALBEDO = color.rgb * COLOR.rgb * energy;
	ALPHA = alpha;
}
