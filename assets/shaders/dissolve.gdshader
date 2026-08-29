shader_type canvas_item;
// Enemy death / despawn: pixel dissolve with a glowing burn edge.
// Tween "progress" from 0.0 to 1.0.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.55, 0.2, 1.0);
uniform float pixel_size = 3.0;
uniform float edge_width = 0.12;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 cell = floor(UV / (pixel_size * TEXTURE_PIXEL_SIZE));
	float n = hash(cell);
	float cut = progress * (1.0 + edge_width) - edge_width;
	if (n < cut) {
		c.a = 0.0;
	} else if (n < cut + edge_width) {
		c.rgb = edge_color.rgb * 2.2;
	}
	COLOR = c;
}
