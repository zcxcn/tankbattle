shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, skip_vertex_transform, fog_disabled;

uniform sampler2D roof_height : filter_nearest, repeat_disable;
uniform vec2 map_origin;
uniform vec2 map_size;
uniform vec2 field_center;
uniform float field_radius = 47.0;
uniform float fall_height = 38.0;
uniform float fall_speed = 29.0;
uniform float rain_strength = 0.88;
uniform float rain_time = 0.0;
varying float visibility;

void vertex() {
	vec4 random = INSTANCE_CUSTOM;
	// World-wrapped X/Z positions remain anchored as the player moves; the
	// invisible far edge recycles, never dragging every drop with the tank.
	vec2 seed_position = (random.xy - 0.5) * field_radius * 2.0;
	vec2 wind = vec2(0.82, 0.25) * rain_time;
	vec2 world_xz = field_center + mod(seed_position + wind - field_center + field_radius, field_radius * 2.0) - field_radius;
	float fall = fract(random.z - rain_time * fall_speed / fall_height);
	float height = 0.075 + fall * fall_height;
	float roof = texture(roof_height, (world_xz - map_origin) / map_size).r;
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 world_position = vec3(world_xz.x, height, world_xz.y) + right * VERTEX.x + vec3(-0.04, 1.0, -0.015) * VERTEX.y;
	float distance_to_edge = max(abs(world_xz.x - field_center.x), abs(world_xz.y - field_center.y));
	visibility = smoothstep(roof + 0.06, roof + 0.65, height) * (1.0 - smoothstep(field_radius - 8.0, field_radius, distance_to_edge));
	visibility *= mix(0.55, 1.0, random.w);
	// Prevent a drop crossing the near plane from becoming a giant white bar.
	visibility *= smoothstep(1.8, 5.5, distance(world_position, INV_VIEW_MATRIX[3].xyz));
	VERTEX = (VIEW_MATRIX * vec4(world_position, 1.0)).xyz;
}

void fragment() {
	float cross_section = pow(max(0.0, 1.0 - abs(UV.x * 2.0 - 1.0)), 1.7);
	float tip = sin(UV.y * 3.14159265);
	ALBEDO = vec3(0.67, 0.78, 0.88);
	ALPHA = cross_section * tip * visibility * rain_strength;
}
