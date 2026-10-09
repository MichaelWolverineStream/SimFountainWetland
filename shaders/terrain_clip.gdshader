shader_type spatial;

// Terrain tile: procedural pixel-art pattern per tile type, grassy side band, soft cell bevel and
// whole-cell slicing along X. Fine detail fades out with distance to avoid shimmering.
#include "res://shaders/slice_clip.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 albedo2 : source_color = vec4(1.0); // pattern accent
uniform vec4 side_color : source_color = vec4(0.5, 0.33, 0.21, 1.0);
uniform float top_band : hint_range(0.0, 1.0) = 0.0; // grass band down the sides, 0 = none
// 0 plain, 1 grass, 2 meadow, 3 field, 4 soil, 5 gravel, 6 asphalt, 7 pond, 8 leaves
uniform int pattern = 0;
uniform float roughness : hint_range(0.0, 1.0) = 0.95;
uniform float jitter : hint_range(0.0, 0.3) = 0.05;
uniform float bevel : hint_range(0.0, 1.0) = 0.16;

const float PIXELS = 8.0; // pattern pixels per cell

varying vec3 v_local;
varying vec3 v_normal;
varying vec3 v_world;
varying vec3 v_cell;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec3 flower(float h) {
	if (h < 0.4) return vec3(1.0, 0.86, 0.30);
	if (h < 0.7) return vec3(0.98, 0.97, 0.94);
	return vec3(1.0, 0.62, 0.78);
}

vec3 surface_pattern(vec2 p, float detail, float time) {
	vec2 px = floor(p * PIXELS);
	float r = hash12(px);
	float n = noise2(p * 0.18);
	vec3 base = albedo.rgb * (0.93 + 0.14 * n);
	vec3 accent = albedo2.rgb * (0.93 + 0.14 * n);
	vec3 color = base;
	if (pattern == 1 || pattern == 2) {
		color = mix(base, accent, step(0.7, r) * detail);
		color = mix(color, base * 1.12, step(0.94, r) * detail);
		if (pattern == 2 && r > 0.955) {
			color = mix(color, flower(hash12(px + 17.0)), detail);
		}
	} else if (pattern == 3) {
		float row = step(0.5, fract(p.x * 2.0));
		color = mix(base, accent, row);
		color = mix(color, color * 0.85, step(0.85, r) * detail);
	} else if (pattern == 4) {
		color = mix(base, accent, step(0.75, r) * detail);
		color = mix(color, base * 1.25, step(0.97, r) * detail);
	} else if (pattern == 5) {
		color = base * mix(1.0, 0.86 + 0.28 * r, detail);
		color = mix(color, accent, step(0.88, hash12(px + 5.0)) * detail);
	} else if (pattern == 6) {
		color = base * mix(1.0, 0.94 + 0.12 * r, detail);
		color = mix(color, base * 1.35, step(0.985, r) * detail);
	} else if (pattern == 7) {
		float w = noise2(p * 1.6 + vec2(time * 0.25, time * 0.17));
		color = mix(base, accent, smoothstep(0.68, 0.8, w) * detail);
	}
	return color;
}

void vertex() {
	if (slice_cut(MODEL_MATRIX[3].x)) {
		VERTEX = vec3(0.0);
	}
	v_local = VERTEX;
	v_normal = NORMAL;
	v_cell = MODEL_MATRIX[3].xyz;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float footprint = length(fwidth(v_world)) * PIXELS;
	float detail = 1.0 - smoothstep(0.5, 1.4, footprint);
	float cell_shade = 1.0 + (hash13(floor(v_cell) + 0.37) - 0.5) * 2.0 * jitter;
	vec3 color;

	if (pattern == 8) {
		// Leafy bush: clumps of two greens, darker underneath.
		float r = hash13(floor(v_world * 6.0));
		color = mix(albedo.rgb, albedo2.rgb, step(0.55, r) * mix(0.5, 1.0, detail));
		color *= mix(0.72, 1.06, clamp(v_local.y + 0.5, 0.0, 1.0));
	} else if (v_normal.y > 0.5) {
		color = surface_pattern(v_world.xz, detail, TIME);
	} else {
		vec2 sp = abs(v_normal.x) > 0.5 ? v_world.zy : v_world.xy;
		if (top_band > 0.0) {
			// Ragged grass edge hanging over the soil.
			float ragged = (hash12(vec2(floor(sp.x * PIXELS), 3.0)) - 0.5) * 0.14;
			if (v_local.y > 0.5 - top_band + ragged) {
				color = albedo.rgb * 0.88;
			} else {
				float r = hash12(floor(sp * PIXELS));
				color = side_color.rgb * mix(1.0, 0.86 + 0.24 * r, detail);
			}
		} else {
			color = surface_pattern(sp, detail, TIME) * 0.9;
		}
	}

	if (pattern != 8) {
		// Soft bevel: darken towards the face edges (the axis along the normal is excluded).
		vec3 e = 0.5 - abs(v_local) + step(0.5, abs(v_normal));
		float edge = min(e.x, min(e.y, e.z));
		color *= mix(1.0, mix(1.0 - bevel, 1.0, smoothstep(0.0, 0.07, edge)), detail);
	}

	ALBEDO = color * cell_shade;
	ROUGHNESS = roughness;
	SPECULAR = pattern == 7 ? 0.6 : 0.25;
}
