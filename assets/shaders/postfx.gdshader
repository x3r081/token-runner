shader_type canvas_item;
// Full-screen post-processing: vignette + chromatic aberration + film grain
// + subtle scanlines + neon color grade. Apply to a screen-covering ColorRect
// in a CanvasLayer BETWEEN the world and the HUD.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.34;
uniform float aberration : hint_range(0.0, 4.0) = 1.1;
uniform float grain_amount : hint_range(0.0, 0.2) = 0.035;
uniform float scanline_amount : hint_range(0.0, 0.3) = 0.05;
uniform float scanline_count = 540.0;
uniform vec3 grade_lift = vec3(0.012, 0.008, 0.03);
uniform vec3 grade_gamma = vec3(1.0, 0.99, 0.94);
uniform float saturation : hint_range(0.0, 2.0) = 1.12;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 center = uv - 0.5;
	float dist = length(center);

	// Chromatic aberration, stronger at edges.
	vec2 ca = center * dist * aberration * 0.004 * intensity;
	float r = textureLod(screen_tex, uv + ca, 0.0).r;
	float g = textureLod(screen_tex, uv, 0.0).g;
	float b = textureLod(screen_tex, uv - ca, 0.0).b;
	vec3 col = vec3(r, g, b);

	// Grade: lift shadows toward indigo, warm the gamma, boost saturation.
	col = pow(max(col + grade_lift * intensity, vec3(0.0)), 1.0 / grade_gamma);
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, mix(1.0, saturation, intensity));

	// Scanlines — extremely subtle.
	float scan = sin(uv.y * scanline_count * 3.14159);
	col *= 1.0 - scanline_amount * intensity * (0.5 + 0.5 * scan);

	// Film grain (animated).
	float gr = hash(uv * vec2(1920.0, 1080.0) + fract(TIME) * 61.7) - 0.5;
	col += gr * grain_amount * intensity;

	// Vignette.
	float vig = smoothstep(0.85, 0.25, dist);
	col *= mix(1.0, vig, vignette_strength * intensity);

	COLOR = vec4(col, 1.0);
}
