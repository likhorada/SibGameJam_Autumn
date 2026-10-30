shader_type canvas_item;
render_mode unshaded;

uniform bool monochrome = false;
uniform float interference : hint_range(0.0, 1.0) = 0.0;

float noise(vec2 point) {
	return fract(sin(dot(point, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float line = floor(uv.y * 270.0);
	uv.x += sin(line * 0.37 + TIME * 31.0) * interference * 0.008;
	vec4 image = texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0)));
	float gray = dot(image.rgb, vec3(0.299, 0.587, 0.114));
	vec3 color = monochrome ? vec3(gray) : mix(vec3(gray), image.rgb, 0.85);
	float grain = noise(vec2(floor(UV.x * 480.0), line) + floor(TIME * 18.0));
	color += (grain - 0.5) * (0.045 + interference * 0.28);
	color *= 0.97 + 0.03 * sin(UV.y * 270.0 * 3.14159);
	COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), 1.0);
}
