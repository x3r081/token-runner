shader_type canvas_item;
render_mode blend_mul, unshaded;
// Low-frequency wear laid over a tiled floor. The tile art tiles perfectly,
// which is exactly the problem: a 20x15 grid of identical 64px cells reads as
// graph paper in the wide regions. This multiplies a slow, non-repeating
// darkening across the whole floor — traffic paths, damp patches, the shadow of
// something that used to be there — at a frequency far below the tile pitch, so
// the eye stops finding the grid.
//
// Multiply-blend and never brighter than 1.0: it can only take light away, in
// patches, and it is bounded by `amount` so the floor is never crushed.
// Sits at z -90, just above the floor (-100) and below every prop, so only the
// ground is affected.

uniform float amount : hint_range(0.0, 0.8) = 0.28;
uniform float floor_scale : hint_range(0.5, 12.0) = 2.2;
uniform float detail_scale : hint_range(1.0, 30.0) = 6.5;
uniform float streak : hint_range(0.0, 1.0) = 0.35;
uniform float darkest : hint_range(0.2, 1.0) = 0.60;
uniform vec3 tint = vec3(1.0, 1.0, 1.0);
uniform vec2 aspect = vec2(1.33, 1.0);
uniform float seed = 0.0;
// The octave that actually fights the lattice. Broad blotches alone read as
// "someone spilled something"; the grid survives them because it is a much
// higher frequency. This octave runs at ROUGHLY the tile pitch but rotated off
// axis and at an incommensurate scale, so it lands a competing texture the eye
// cannot line up with the tiling. Note what it does NOT do: it cannot remove a
// seam that is baked into the tile art. It makes the lattice stop being the
// dominant structure; erasing it belongs to the floor generator.
uniform float grit : hint_range(0.0, 1.0) = 0.60;
uniform float grit_scale : hint_range(4.0, 60.0) = 26.0;
uniform float grit_rot : hint_range(0.0, 1.57) = 0.55;

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * aspect;
	float o = seed * 13.7;
	float broad = fbm(uv * floor_scale + vec2(o, o * 0.31));
	float fine = fbm(uv * detail_scale + vec2(o * 2.1, o * 0.7));
	// Stretched vertically: worn lanes where everyone walks.
	float wear = fbm(vec2(uv.x * floor_scale * 0.4, uv.y * floor_scale * 3.2) + o * 3.3);
	// Off-axis grit at roughly the tile pitch (see the `grit` note above).
	float cr = cos(grit_rot);
	float sr = sin(grit_rot);
	vec2 ruv = vec2(uv.x * cr - uv.y * sr, uv.x * sr + uv.y * cr);
	float g = vnoise(ruv * grit_scale + vec2(o * 5.5, o * 1.9));

	// Round 4: the builders now give floors real structure (paths, panel
	// grids, strata), so the mottle is demoted from "the floor" to a finish.
	// The high-frequency octaves lose most of their weight — fine + grit were
	// the color-soup in the gpu_mines / wildlands QA frames — and the broad,
	// low-frequency history keeps the lead. The 0.72 scale on `amount` caps
	// the hottest consumer preset (0.34) at ~24% effective opacity, under the
	// bible's 25% finish ceiling, without touching any caller.
	float m = clamp(broad * 0.66 + fine * 0.12 + wear * streak * 0.26
		+ (g - 0.5) * grit * 0.55, 0.0, 1.0);
	float amt = amount * 0.72;
	vec3 mul = mix(vec3(1.0), tint * mix(darkest, 1.0, m), amt);
	COLOR = vec4(clamp(mul, vec3(0.0), vec3(1.0)), 1.0);
}
