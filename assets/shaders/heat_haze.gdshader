shader_type canvas_item;
// Screen-space heat distortion. Apply to a ColorRect covering the hot area.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 0.02) = 0.0035;
uniform float speed = 2.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float w1 = sin(uv.y * 90.0 + TIME * speed * 3.1) * sin(uv.y * 23.0 - TIME * speed);
	float w2 = sin(uv.x * 70.0 - TIME * speed * 2.3);
	uv.x += w1 * strength;
	uv.y += w2 * strength * 0.4;
	COLOR = vec4(textureLod(screen_tex, uv, 0.0).rgb, 1.0);
}
