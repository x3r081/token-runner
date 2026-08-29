shader_type canvas_item;
// For in-world monitor/terminal screen sprites: scanlines, flicker,
// a slow rolling band, and an overbright boost so screens bloom.

uniform float scan_density = 46.0;
uniform float flicker_speed = 11.0;
uniform float glow_boost = 1.45;
uniform float roll_speed = 0.08;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float scan = 0.86 + 0.14 * sin(UV.y * scan_density * 6.2831 + TIME * 1.5);
	float fl = 0.955 + 0.045 * sin(TIME * flicker_speed) * sin(TIME * 3.7 + 1.3);
	float band = 0.92 + 0.08 * smoothstep(0.0, 0.3, abs(fract(UV.y - TIME * roll_speed) - 0.5));
	c.rgb *= scan * fl * band * glow_boost;
	COLOR = c;
}
