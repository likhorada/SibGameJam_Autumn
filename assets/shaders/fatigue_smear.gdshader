shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 smear_uv = vec2(0.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float ghost_weight : hint_range(0.0, 0.3) = 0.12;

vec3 sample_screen(vec2 uv, vec2 pixel_size) {
	return textureLod(screen_texture, clamp(uv, pixel_size * 0.5, vec2(1.0) - pixel_size * 0.5), 0.0).rgb;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 original = sample_screen(uv, SCREEN_PIXEL_SIZE);
	// Directional shutter approximation, NOT static blur or temporal frame history.
	vec3 shutter = original * 0.4;
	shutter += sample_screen(uv - smear_uv, SCREEN_PIXEL_SIZE) * 0.15;
	shutter += sample_screen(uv - smear_uv * 0.5, SCREEN_PIXEL_SIZE) * 0.15;
	shutter += sample_screen(uv + smear_uv * 0.5, SCREEN_PIXEL_SIZE) * 0.15;
	shutter += sample_screen(uv + smear_uv, SCREEN_PIXEL_SIZE) * 0.15;
	vec3 ghost = sample_screen(uv - smear_uv * 1.7, SCREEN_PIXEL_SIZE);
	COLOR = vec4(mix(original, mix(shutter, ghost, ghost_weight), intensity), 1.0);
}
