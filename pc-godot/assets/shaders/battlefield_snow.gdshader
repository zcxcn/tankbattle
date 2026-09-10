shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, skip_vertex_transform;

uniform sampler2D roof_height : filter_nearest, repeat_disable;
uniform vec2 map_origin;
uniform vec2 map_size;
uniform vec2 field_center;
uniform float field_radius = 47.0;
uniform float fall_height = 38.0;
uniform float fall_speed = 1.55;
uniform float rain_time = 0.0;
varying float visibility;
varying float flake_seed;

void vertex() {
	vec4 random = INSTANCE_CUSTOM;
	vec2 seed_position = (random.xy - 0.5) * field_radius * 2.0;
	float phase = random.w * 6.2831853;
	// Variable terminal speed, crosswind and a gentle falling leaf oscillation.
	vec2 drift = vec2(0.32, 0.16) * rain_time;
	drift += vec2(sin(rain_time * 0.64 + phase), cos(rain_time * 0.45 + phase)) * 0.65;
	vec2 world_xz = field_center + mod(seed_position + drift - field_center + field_radius, field_radius * 2.0) - field_radius;
	float fall = fract(random.z - rain_time * fall_speed * mix(0.72, 1.18, random.w) / fall_height);
	float height = 0.075 + fall * fall_height;
	float roof = texture(roof_height, (world_xz - map_origin) / map_size).r;
	float spin = rain_time * mix(-0.5, 0.6, random.z) + phase;
	vec2 rotated = mat2(vec2(cos(spin), sin(spin)), vec2(-sin(spin), cos(spin))) * VERTEX.xy;
	float size = mix(0.45, 1.2, random.w);
	vec3 world_position = vec3(world_xz.x, height, world_xz.y);
	world_position += (INV_VIEW_MATRIX[0].xyz * rotated.x + INV_VIEW_MATRIX[1].xyz * rotated.y) * size;
	float distance_to_edge = max(abs(world_xz.x - field_center.x), abs(world_xz.y - field_center.y));
	visibility = smoothstep(roof + 0.03, roof + 0.45, height) * (1.0 - smoothstep(field_radius - 8.0, field_radius, distance_to_edge));
	visibility *= smoothstep(0.7, 2.2, distance(world_position, INV_VIEW_MATRIX[3].xyz));
	flake_seed = phase;
	VERTEX = (VIEW_MATRIX * vec4(world_position, 1.0)).xyz;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float radius = length(p);
	float edge = 0.64 + sin(atan(p.y, p.x) * 5.0 + flake_seed) * 0.09;
	float flake = 1.0 - smoothstep(edge * 0.4, edge, radius);
	ALBEDO = vec3(0.84, 0.89, 0.94);
	ALPHA = flake * visibility * 0.83;
}
