shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled, shadows_disabled;

// Puffy clouds drifting around the diorama. Parts of a cloud that sit between the camera and the
// level are screen-door faded so they never hide the pond. Not sliced.

uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 box_min = vec3(0.0);
uniform vec3 box_max = vec3(1.0);
uniform float fade_depth = 10.0; // ray length through the level box for full fade
uniform float max_fade : hint_range(0.0, 1.0) = 0.9;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 eye = CAMERA_POSITION_WORLD;
	vec3 dir = normalize(v_world - eye);
	vec3 inv = 1.0 / dir;
	vec3 t0 = (box_min - eye) * inv;
	vec3 t1 = (box_max - eye) * inv;
	vec3 lo = min(t0, t1);
	vec3 hi = max(t0, t1);
	float enter = max(max(lo.x, lo.y), lo.z);
	float leave = min(min(hi.x, hi.y), hi.z);
	float fade = 0.0;
	if (leave > max(enter, 0.0) && length(v_world - eye) < enter) {
		fade = clamp((leave - enter) / fade_depth, 0.0, 1.0) * max_fade;
	}
	float noise = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (noise < fade) {
		discard;
	}
	vec3 color = tint.rgb * COLOR.rgb;
	ALBEDO = color;
	ROUGHNESS = 1.0;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	EMISSION = color * (0.22 + fresnel * 0.3);
}
