shader_type canvas_item;
// Holographic projection: additive tint, scan bands, shimmer, edge fizz.

uniform vec4 tint : source_color = vec4(0.35, 0.95, 0.9, 1.0);
uniform float scan_speed = 1.2;
uniform float alpha_base : hint_range(0.0, 1.0) = 0.82;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float scan = 0.75 + 0.25 * sin(UV.y * 60.0 - TIME * scan_speed * 6.0);
	float jitterband = step(0.97, hash(vec2(floor(TIME * 9.0), floor(UV.y * 20.0))));
	vec3 col = mix(c.rgb, tint.rgb, 0.55) * scan * 1.6;
	col += tint.rgb * jitterband * 0.6;
	float alpha = c.a * alpha_base * (0.9 + 0.1 * sin(TIME * 2.1));
	COLOR = vec4(col, alpha);
}
