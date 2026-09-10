shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, skip_vertex_transform;

uniform sampler2D roof_height : filter_nearest, repeat_disable;
uniform vec2 map_origin;
uniform vec2 map_size;
uniform vec2 field_center;
uniform float field_radius = 47.0;
uniform float rain_time = 0.0;
varying float life;
varying float visibility;

void vertex() {
	vec4 random = INSTANCE_CUSTOM;
	vec2 seed_position = (random.xy - 0.5) * field_radius * 2.0;
	vec2 world_xz = field_center + mod(seed_position - field_center + field_radius, field_radius * 2.0) - field_radius;
	life = fract(random.z + rain_time * mix(1.3, 2.4, random.w));
	float roof = texture(roof_height, (world_xz - map_origin) / map_size).r;
	float distance_to_edge = max(abs(world_xz.x - field_center.x), abs(world_xz.y - field_center.y));
	visibility = (1.0 - step(0.3, roof)) * (1.0 - smoothstep(field_radius - 8.0, field_radius, distance_to_edge));
	vec3 world_position = vec3(world_xz.x, 0.097, world_xz.y) + VERTEX;
	VERTEX = (VIEW_MATRIX * vec4(world_position, 1.0)).xyz;
}

void fragment() {
	float radius = length(UV - 0.5) * 2.0;
	float ring = 1.0 - smoothstep(0.018, 0.075, abs(radius - life * 0.9));
	float second_ring = (1.0 - smoothstep(0.015, 0.045, abs(radius - life * 0.56))) * 0.35;
	float impact = (1.0 - smoothstep(0.0, 0.16, radius)) * (1.0 - smoothstep(0.0, 0.18, life));
	ALBEDO = vec3(0.57, 0.69, 0.78);
	ALPHA = min(0.62, (ring + second_ring + impact) * pow(1.0 - life, 1.4) * visibility * 0.5);
}
