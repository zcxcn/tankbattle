shader_type spatial;

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 grass_color : source_color = vec3(0.21, 0.235, 0.115);
uniform vec3 earth_color : source_color = vec3(0.33, 0.265, 0.17);
varying vec3 world_position;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	// Separate the visible grass from the coplanar road foundation by 15mm.
	// Keep the collision heightfield seamless so tracks never meet a curb.
	VERTEX.y += 0.015;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 weights = pow(abs(normalize(world_normal)), vec3(4.0));
	weights /= max(dot(weights, vec3(1.0)), 0.001);
	vec3 p = world_position * 0.16;
	vec3 stone = texture(rock_albedo, p.yz).rgb * weights.x
		+ texture(rock_albedo, p.xz).rgb * weights.y
		+ texture(rock_albedo, p.xy).rgb * weights.z;
	float broad = noise(world_position.xz * 0.075);
	float detail = noise(world_position.xz * 2.7);
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float exposed = smoothstep(0.13, 0.42, slope + broad * 0.13);
	vec2 grass_uv = world_position.xz / 15.0;
	vec3 grass = texture(grass_albedo, grass_uv).rgb;
	vec3 turf = grass * mix(vec3(0.83, 0.9, 0.75), vec3(1.05, 0.94, 0.77), smoothstep(0.43, 0.72, broad));
	turf *= mix(0.92, 1.07, detail);
	ALBEDO = mix(turf, stone * vec3(0.59, 0.57, 0.5), exposed);
	ALBEDO *= mix(1.0, 0.69, wetness);
	float snow = snow_amount * smoothstep(0.65, 0.96, world_normal.y) * (0.88 + broad * 0.12);
	ALBEDO = mix(ALBEDO, vec3(0.81, 0.86, 0.88), snow);
	vec3 grass_channels = texture(grass_arm, grass_uv).rgb;
	ROUGHNESS = mix(clamp(grass_channels.g, 0.72, 0.98), 0.58, wetness);
	ROUGHNESS = mix(ROUGHNESS, texture(rock_roughness, p.xz).r, exposed * 0.35);
	NORMAL_MAP = mix(texture(grass_normal, grass_uv).rgb, texture(rock_normal, p.xz).rgb, exposed);
	NORMAL_MAP_DEPTH = 0.22 + exposed * 0.16;
	AO = mix(grass_channels.r, 1.0, exposed * 0.8);
	SPECULAR = 0.23;
}
