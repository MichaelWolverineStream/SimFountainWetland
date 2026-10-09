shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Twinkling star sprites on a dome far around the level. Brightness follows the night; not sliced.

uniform vec4 color : source_color = vec4(1.0);
uniform float visibility : hint_range(0.0, 1.0) = 0.0;

varying float v_twinkle;
varying vec3 v_tint;

void vertex() {
	mat4 face = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	face = face * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * face;
	float id = float(INSTANCE_ID);
	v_twinkle = 0.65 + 0.35 * sin(TIME * (1.2 + fract(id * 0.37) * 2.5) + id * 2.39);
	v_tint = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float glow = (1.0 - smoothstep(0.0, 1.0, d)) * 0.5 + (1.0 - smoothstep(0.0, 0.35, d));
	ALBEDO = color.rgb * v_tint * glow * v_twinkle * visibility;
	ALPHA = 1.0;
}
