shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec4 sample_color = texture(TEXTURE, UV) * COLOR;
	float luminance = dot(sample_color.rgb, vec3(0.299, 0.587, 0.114));
	// Cheap analog-camera gain keeps dim corners legible in the low-res feed.
	luminance = clamp(pow(max(luminance, 0.0), 0.62) * 1.12 + 0.015, 0.0, 1.0);
	COLOR = vec4(vec3(luminance), sample_color.a);
}
