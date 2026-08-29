shader_type canvas_item;
// Swirling energy vortex. Apply to any square sprite (its texture is
// ignored — the effect is fully procedural, masked to a disc).

uniform vec4 hue_color : source_color = vec4(0.55, 0.36, 0.96, 1.0);
uniform float speed = 1.0;
uniform float arms = 3.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float a = atan(p.y, p.x);
	float swirl = a + (1.0 - r) * 4.0 - TIME * speed * 2.0;
	float band = 0.5 + 0.5 * sin(swirl * arms + r * 9.0);
	float rings = 0.5 + 0.5 * sin(r * 14.0 - TIME * speed * 3.0);
	float glow = pow(max(1.0 - r, 0.0), 1.4);
	float sparkle = step(0.985, hash(floor(UV * 24.0) + floor(TIME * 8.0)));
	vec3 col = hue_color.rgb * (band * 0.7 + rings * 0.30) + vec3(1.0) * (glow * 0.22 + sparkle * 0.6);
	float alpha = smoothstep(1.0, 0.74, r) * (0.40 + 0.34 * band) * hue_color.a;
	col *= 1.12; // just past 1.0 — enough to bloom, not enough to blow out
	COLOR = vec4(col, alpha);
}
