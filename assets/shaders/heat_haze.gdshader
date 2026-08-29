shader_type canvas_item;
// Screen-space heat distortion. Apply to a ColorRect covering the hot area.
//
// Two changes over the flat sine version: the wobble now rises (the vertical
// phase scrolls upward, so the air convects instead of just vibrating), and
// three incommensurate frequencies stop it reading as a single ripple. A small
// warm tint can be added on top for the "you can see the heat" look; leave
// tint_amount at 0 for pure distortion.
//
// Screen-reading: whatever draws AFTER this and also reads the screen needs a
// BackBufferCopy in between, or it will sample the pre-distortion frame
// (postfx_layer.gd owns that ordering).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 0.02) = 0.0035;
uniform float speed = 2.0;
uniform vec4 tint : source_color = vec4(1.0, 0.55, 0.28, 1.0);
uniform float tint_amount : hint_range(0.0, 0.4) = 0.0;
uniform float rise : hint_range(0.0, 4.0) = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME * speed;
	float climb = uv.y * 90.0 - t * 2.0 * rise;
	float w1 = sin(climb) * sin(uv.y * 23.0 - t);
	float w2 = sin(uv.x * 70.0 - t * 2.3);
	float w3 = sin(uv.x * 31.0 + uv.y * 17.0 + t * 1.4);
	uv.x += (w1 * 0.72 + w3 * 0.38) * strength;
	uv.y += (w2 * 0.4 + w1 * 0.2) * strength;
	vec3 col = textureLod(screen_tex, uv, 0.0).rgb;
	if (tint_amount > 0.0005) {
		float shimmer = 0.5 + 0.5 * w1;
		col += tint.rgb * shimmer * tint_amount;
	}
	COLOR = vec4(col, 1.0);
}
