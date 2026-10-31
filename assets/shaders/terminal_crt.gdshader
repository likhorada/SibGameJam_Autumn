shader_type canvas_item;
render_mode unshaded, blend_mul;

uniform float strength : hint_range(0.0, 1.0) = 0.55;
// Physical-pixel spacing avoids the half-resolution cosine cancelling out at
// pixel centers (360 cycles on 720 rows produced an almost flat tint).
uniform float scanline_period : hint_range(3.0, 8.0) = 3.0;
uniform float sweep_seconds = 7.0;

void fragment() {
	float lines = step(scanline_period - 1.0, mod(floor(FRAGCOORD.y), scanline_period));
	float phase = fract(UV.y - TIME / sweep_seconds);
	float band = 1.0 - smoothstep(0.0, 0.08, abs(phase - 0.5));
	float brightness = 1.0 - strength * (lines * 0.29 + band * 0.17);
	COLOR = vec4(vec3(brightness), 1.0);
}
