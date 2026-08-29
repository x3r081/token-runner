shader_type canvas_item;
// Moving diagonal highlight for UI panels/buttons. Subtle, classy.

uniform vec4 sheen_color : source_color = vec4(1.0, 1.0, 1.0, 0.06);
uniform float period = 6.0;
uniform float width : hint_range(0.01, 0.5) = 0.12;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float t = fract(TIME / period);
	float pos = mix(-0.3, 1.3, t);
	float d = abs((UV.x + UV.y * 0.5) - pos);
	float sheen = smoothstep(width, 0.0, d);
	c.rgb += sheen_color.rgb * sheen * sheen_color.a * 8.0;
	c.a = max(c.a, sheen * sheen_color.a);
	COLOR = c;
}
