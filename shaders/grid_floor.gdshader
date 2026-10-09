shader_type spatial;
render_mode cull_disabled;

// Soft blueprint-style floor under the diorama: grid lines that fade with distance.

uniform vec3 base_color : source_color = vec3(0.06, 0.10, 0.20);
uniform vec3 line_color : source_color = vec3(0.25, 0.42, 0.65);
uniform float spacing = 16.0;
uniform float line_width = 1.2; // pixels
uniform vec3 center = vec3(48.0, 0.0, 32.0);
uniform float fade_distance = 320.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 p, float step_size) {
	vec2 g = p / step_size;
	vec2 w = fwidth(g);
	vec2 d = abs(fract(g - 0.5) - 0.5) / max(w, vec2(1e-4));
	return 1.0 - clamp(min(d.x, d.y) / line_width, 0.0, 1.0);
}

void fragment() {
	vec2 p = v_world.xz;
	float fade = 1.0 - smoothstep(fade_distance * 0.25, fade_distance, distance(p, center.xz));
	float lines = max(grid_line(p, spacing) * 0.55, grid_line(p, spacing * 4.0)) * fade;
	ALBEDO = mix(base_color, line_color, lines * 0.8);
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
