shader_type canvas_item;
render_mode blend_add, unshaded;
// Volumetric light shafts. Apply to a ColorRect covering the region; the shafts
// tilt by `angle`, march by `speed`, and fade out along their own length so the
// far end of the room stays dark.
//
// Purely additive and self-lit: it never darkens the frame, so it can be laid
// over an already-dim region without hazing it (VISUAL_BIBLE: light carves the
// dark, it does not wash it).
//
// Additive contract: Godot's blend_add uses COLOR.rgb * COLOR.a, so the final
// contribution is written straight into rgb with alpha pinned at 1.0. That
// keeps "how bright" in one place instead of two.

uniform vec4 ray_color : source_color = vec4(0.72, 0.86, 1.0, 1.0);
uniform float angle : hint_range(-1.5, 1.5) = 0.35;
uniform float density : hint_range(1.0, 40.0) = 8.0;
uniform float speed : hint_range(0.0, 3.0) = 0.16;
uniform float intensity : hint_range(0.0, 2.0) = 0.30;
uniform float reach : hint_range(0.15, 3.0) = 0.85;
uniform float sharpness : hint_range(1.0, 24.0) = 7.0;
uniform float bottom_fade : hint_range(0.1, 1.0) = 0.72;
uniform vec2 aspect = vec2(1.33, 1.0);

const float TAUC = 6.28318530718;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = (UV - vec2(0.5, 0.0)) * aspect;
	float c = cos(angle);
	float s = sin(angle);
	// q.x runs ACROSS the shafts, q.y runs ALONG them (0 at the ceiling).
	vec2 q = vec2(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
	float across = q.x;
	float along = max(q.y, 0.0);
	float t = TIME * speed;

	// Three beat frequencies so the shafts never read as a repeating comb.
	// max(x, 0.0) on every base: hardware sin() is allowed to return marginally
	// less than -1.0, and pow() of a negative base is NaN in GLSL — one stray
	// ULP would put a black speck in the middle of a light shaft.
	float shafts = pow(max(0.5 + 0.5 * sin(across * density * TAUC + t * 1.7), 0.0), sharpness);
	shafts += 0.62 * pow(max(0.5 + 0.5 * sin(across * density * 0.53 * TAUC - t * 1.1 + 1.7), 0.0), sharpness + 3.0);
	shafts += 0.34 * pow(max(0.5 + 0.5 * sin(across * density * 1.90 * TAUC + t * 0.6 + 4.2), 0.0), sharpness + 6.0);
	shafts *= 0.55 + 0.60 * vnoise(vec2(across * 6.0, t * 0.5));

	float falloff = exp(-along / reach);
	// min() so bottom_fade can never equal the upper edge: smoothstep with two
	// identical edges is undefined, and hint_range lets it reach 1.0.
	float bf = min(bottom_fade, 0.97);
	float edge = smoothstep(0.0, 0.09, UV.x)
		* (1.0 - smoothstep(0.91, 1.0, UV.x))
		* smoothstep(0.0, 0.05, UV.y)
		* (1.0 - smoothstep(bf, 1.0, UV.y));

	float a = clamp(shafts, 0.0, 3.0) * falloff * edge * intensity * ray_color.a;
	COLOR = vec4(ray_color.rgb * clamp(a, 0.0, 1.2), 1.0);
}
