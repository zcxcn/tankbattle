shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_disabled;

// CC0 Houdini simulation frames, blended in linear color. Animation uses the
// particle's own simulation age, so pausing freezes both motion and texture.
uniform sampler2D flipbook : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec2 grid = vec2(5.0);
uniform float first_frame = 0.0;
uniform float last_frame = 24.0;
uniform float heat = 3.0;
uniform float matter_brightness = 1.35;
uniform float soft_distance = 0.65;
uniform bool flame_only = false;
varying float animation_frame;
varying float mirror;

void vertex() {
	// INSTANCE_CUSTOM.z is ParticleProcessMaterial's animation phase. It is
	// independent of TIME, which would keep moving while combat is paused.
	animation_frame = mix(first_frame, last_frame, clamp(INSTANCE_CUSTOM.z, 0.0, 1.0));
	mirror = step(0.5, fract(sin(float(INSTANCE_ID) * 127.1 + 19.3) * 43758.5453));
	vec3 particle_scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 facing = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * facing;
	MODELVIEW_MATRIX[0] *= particle_scale.x;
	MODELVIEW_MATRIX[1] *= particle_scale.y;
	MODELVIEW_MATRIX[2] *= particle_scale.z;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

vec2 atlas_uv(vec2 uv, float frame) {
	// The source atlas uses fractional 1024 / 5 frame edges. Half a texel
	// inset avoids adjacent-frame bleed, including when mipmaps are sampled.
	vec2 inset = 0.5 / vec2(textureSize(flipbook, 0)) * grid;
	uv = mix(inset, vec2(1.0) - inset, uv);
	return (uv + vec2(mod(frame, grid.x), floor(frame / grid.x))) / grid;
}

void fragment() {
	vec2 uv = vec2(mix(UV.x, 1.0 - UV.x, mirror), UV.y);
	float index = floor(animation_frame);
	vec4 frame_a = texture(flipbook, atlas_uv(uv, index));
	vec4 frame_b = texture(flipbook, atlas_uv(uv, min(index + 1.0, last_frame)));
	vec4 matter = mix(frame_a, frame_b, fract(animation_frame));
	float depth = texture(scene_depth, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float separation = -view.z / view.w + VERTEX.z;
	float contact_fade = smoothstep(0.0, soft_distance, separation);
	// Only orange/white hot regions emit. Charcoal remains non-additive,
	// illuminated matter and can obscure the hot core as the blast cools.
	float hot = max(smoothstep(0.10, 0.32, matter.r - matter.b), smoothstep(0.72, 0.98, min(matter.r, matter.g)));
	ALBEDO = matter.rgb * COLOR.rgb * matter_brightness;
	EMISSION = matter.rgb * hot * heat;
	ALPHA = matter.a * COLOR.a * contact_fade * (flame_only ? hot : 1.0);
	ROUGHNESS = 1.0;
}
