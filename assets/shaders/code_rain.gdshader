shader_type canvas_item;
// Stylized matrix-style data rain: falling blocky glyph columns.
// Apply to a transparent ColorRect overlay sized to the area.

uniform vec4 tint : source_color = vec4(0.15, 1.0, 0.55, 1.0);
uniform float columns = 48.0;
uniform float speed = 1.0;
uniform float alpha_max : hint_range(0.0, 1.0) = 0.30;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float col_i = floor(UV.x * columns);
	float col_speed = 0.35 + hash(vec2(col_i, 1.0)) * 0.9;
	float offset = hash(vec2(col_i, 7.0));
	float y = fract(UV.y + TIME * speed * col_speed * 0.22 + offset);
	// head is bright, trail fades
	float trail = pow(1.0 - y, 3.0);
	// blocky glyph cells flickering
	vec2 cell = vec2(col_i, floor(UV.y * columns * 1.6));
	float glyph = step(0.35, hash(cell + floor(TIME * (2.0 + col_speed * 6.0))));
	vec3 col = tint.rgb * (trail * 1.8) * glyph;
	col += vec3(0.9, 1.0, 0.95) * step(0.985, trail) * glyph; // white-hot head
	float alpha = clamp(trail * glyph, 0.0, 1.0) * alpha_max;
	COLOR = vec4(col, alpha);
}
