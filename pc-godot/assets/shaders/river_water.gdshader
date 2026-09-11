shader_type spatial;
render_mode cull_disabled;

// The arena supplies a pauseable clock; shader TIME would keep flowing in menus.
uniform float river_time = 0.0;
uniform float rainfall : hint_range(0.0, 1.0) = 0.0;
uniform float channel_center = 36.0;
uniform float channel_half_width = 12.2;
uniform vec3 deep_color : source_color = vec3(0.065, 0.16, 0.16);
uniform vec3 shallow_color : source_color = vec3(0.15, 0.26, 0.23);
varying vec3 river_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	river_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(river_position.x * 0.64 - river_time * 1.35 + river_position.z * 0.23)
		+ sin(river_position.z * 1.72 + river_position.x * 0.38 - river_time * 1.85) * 0.4;
	VERTEX.y += wave * 0.035;
}

void fragment() {
	vec2 p = river_position.xz;
	float flow = river_time * 0.75;
	float wave_x = sin(p.x * 1.8 + p.y * 1.2 - flow * 2.1) * 0.12
		+ sin(p.x * 5.6 - p.y * 2.8 - flow * 3.8) * 0.035;
	float wave_z = cos(p.y * 2.35 + p.x * 0.68 - flow * 2.8) * 0.105
		+ cos(p.y * 8.7 + p.x * 3.5 - flow * 5.3) * (0.02 + rainfall * 0.035);
	NORMAL_MAP = normalize(vec3(wave_x, wave_z, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.75;
	float bank_distance = channel_half_width - abs(p.y - channel_center);
	float shore = 1.0 - smoothstep(0.3, 3.0, bank_distance);
	float turbulence = noise(vec2(p.x * 1.5 - flow, p.y * 3.0 + flow * 0.15));
	float foam_band = (1.0 - smoothstep(0.15, 1.35, bank_distance));
	float foam = foam_band * smoothstep(0.38, 0.8, turbulence) * 0.62;
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 4.0);
	ALBEDO = mix(deep_color, shallow_color, shore * 0.8 + turbulence * 0.08);
	ALBEDO = mix(ALBEDO, vec3(0.34, 0.43, 0.43), fresnel * 0.38);
	ALBEDO = mix(ALBEDO, vec3(0.7, 0.75, 0.68), foam);
	ROUGHNESS = mix(0.19 + rainfall * 0.08, 0.64, foam);
	METALLIC = 0.05;
	SPECULAR = 0.85;
}
