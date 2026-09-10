shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

uniform sampler2D roof_height : filter_nearest, repeat_disable;
uniform vec2 map_origin;
uniform vec2 map_size;

varying vec3 world_position;
varying vec3 world_normal;

float hash21(vec2 p) {
	// Integer arithmetic gives shared cell corners identical values. A sin hash
	// produced visible seams after GPU floating-point expression optimization.
	uvec2 cell = uvec2(ivec2(p));
	uint value = cell.x * 1597334677u ^ cell.y * 3812015801u;
	value = (value ^ (value >> 16u)) * 2246822519u;
	value = (value ^ (value >> 13u)) * 3266489917u;
	return float(value ^ (value >> 16u)) / 4294967295.0;
}

float sample_snow_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), u.x), u.y);
}

void vertex() {
	// A real thin layer avoids depth quantization fighting the opaque road pass.
	VERTEX += NORMAL * 0.009;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	float broad = sample_snow_noise(world_position.xz * 0.13) * 0.65 + sample_snow_noise(world_position.xz * 0.63) * 0.35;
	float grains = sample_snow_noise(world_position.xz * 8.0);
	float exposed_top = smoothstep(0.58, 0.94, world_normal.y);
	float roof = texture(roof_height, (world_position.xz - map_origin) / map_size).r;
	exposed_top *= 1.0 - step(world_position.y + 0.4, roof);
	// A thin broken layer leaves road grain and worn routes visible underneath.
	float coverage = smoothstep(0.18, 0.76, broad + grains * 0.08);
	ALBEDO = mix(vec3(0.55, 0.63, 0.69), vec3(0.81, 0.85, 0.88), grains * 0.16 + broad * 0.84);
	ROUGHNESS = 0.96;
	SPECULAR = 0.15;
	ALPHA = exposed_top * coverage * 0.82;
}
