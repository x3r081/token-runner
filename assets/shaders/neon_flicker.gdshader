shader_type canvas_item;
// Neon sign life: gentle hum-pulse plus occasional dropout stutter.

uniform float seed = 0.0;
uniform float base_boost = 1.6;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.35;

float hash1(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float hum = 0.94 + 0.06 * sin(TIME * 7.3 + seed * 12.9);
	float slot = floor(TIME * 16.0) + seed * 101.0;
	float drop = step(0.965, hash1(slot));
	float stutter = mix(1.0, 0.35 + 0.3 * hash1(slot * 1.7), drop * flicker_amount);
	c.rgb *= base_boost * hum * stutter;
	COLOR = c;
}
