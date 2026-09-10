shader_type spatial;
render_mode cull_disabled, depth_draw_never;

uniform float rain_time = 0.0;
varying float seed;

void vertex() {
	seed = INSTANCE_CUSTOM.r * 12.0;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float angle = atan(p.y, p.x);
	float edge = length(p) + sin(angle * 5.0 + seed) * 0.095 + sin(angle * 9.0 - seed) * 0.035;
	float ripple = sin(p.x * 37.0 + rain_time * 3.2 + seed) * cos(p.y * 29.0 - rain_time * 2.4);
	NORMAL_MAP = vec3(0.5 + ripple * 0.024, 0.5 + sin(p.y * 33.0 + rain_time * 2.8) * 0.022, 1.0);
	NORMAL_MAP_DEPTH = 0.5;
	ALBEDO = vec3(0.1, 0.135, 0.145);
	ROUGHNESS = 0.14;
	METALLIC = 0.12;
	SPECULAR = 0.82;
	ALPHA = (1.0 - smoothstep(0.76, 1.02, edge)) * 0.66;
}
