shader_type canvas_item;
render_mode blend_mix, unshaded;
// A collapsing accretion disc, not a coloured blob. Apply to any square sprite
// (the texture is ignored — everything is procedural, masked to a disc).
//
// Why it looked like a blob before, and what fixes it:
//   * `unshaded`. Every portal sits inside two or three PointLight2Ds, and 2D
//     lights ADD themselves on top of the sprite. The swirl was being lit into
//     a flat pastel disc before bloom ever touched it. It is emissive; it must
//     not receive light.
//   * DEPTH. Three spiral shells are advected down a 1/r tunnel at three
//     different rates, so they parallax against each other and the middle
//     genuinely recedes instead of being a bright spot.
//   * A DARK event horizon. The light lives in the horizon lip and the
//     accretion ring around it. A hole reads as a hole; a white core reads as
//     a lamp.
//   * soft_clip(). An exponential ceiling that keeps hue and can never reach
//     white however hot core_heat gets, while still leaving values above 1.0
//     for the HDR glow pass to find (VISUAL_BIBLE).
//
// Chroma is normalised first (vivid), so the bible's muted accents —
// stackoverflow gold #E8C46B, cloud sky #6BC7FF — read as saturated destination
// energy instead of brown sludge on a near-black floor.

uniform vec4 hue_color : source_color = vec4(0.55, 0.36, 0.96, 1.0);
uniform float speed = 1.0;
uniform float arms = 3.0;
uniform float core_heat : hint_range(0.0, 2.0) = 1.0;
uniform float depth_scale : hint_range(0.2, 3.0) = 1.0;
uniform float horizon : hint_range(0.05, 0.5) = 0.26;
uniform float peak_luma : hint_range(0.5, 4.0) = 2.30;
// Extra rotation, accumulated on the CPU (region_portal.gd spins the vortex up
// as the player approaches). It is ADDED to the clock rather than scaling it,
// because scaling TIME mid-animation snaps the phase by however many seconds
// the game has been running. `seed` stays constant for the life of the portal —
// it only decorrelates the static noise between portals.
uniform float phase = 0.0;
uniform float seed = 0.0;

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

// Full value + boosted chroma, same hue. Near-white inputs degrade gracefully.
vec3 vivid(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	vec3 n = c / max(mx, 0.001);
	float lum = dot(n, vec3(0.299, 0.587, 0.114));
	return clamp(mix(vec3(lum), n, 1.45), vec3(0.0), vec3(1.0));
}

// Exponential ceiling. All three channels are scaled by the same factor, so the
// hue survives; `peak` is a hard asymptote the result can approach but never
// reach, which is exactly the "bright but never clipping to white" contract.
vec3 soft_clip(vec3 c, float peak) {
	float m = max(c.r, max(c.g, c.b));
	if (m < 0.0001) {
		return c;
	}
	return c * (peak * (1.0 - exp(-m / peak)) / m);
}

// One spiral shell. `rate` is how fast this shell's filaments march inward, so
// three shells at three rates parallax against each other. Angular frequency is
// always an integer harmonic, which is what keeps the u = 0 seam invisible.
float shell(float u, float depth, float rate, float f, float t, float ph) {
	// max(): hardware sin() may return marginally below -1.0, and pow() of a
	// negative base is NaN in GLSL.
	float band = max(0.5 + 0.5 * sin(u * f * TAUC + depth * rate - t * 2.0 + ph), 0.0);
	return pow(band, 3.0);
}

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;                       // 1.0 at the inscribed disc
	float u = fract(atan(p.y, p.x) / TAUC + 1.0);    // 0..1 around the disc
	float t = TIME * speed + phase;
	float depth = depth_scale * 0.62 / max(r, 0.10); // tunnel: large at the core
	float f = max(1.0, floor(arms + 0.5));           // integer harmonics only

	float s1 = shell(u, depth, 3.6, f, t, 0.0);
	float s2 = shell(u, depth, 5.4, f + 1.0, t * 1.24, 2.1);
	float s3 = shell(u, depth, 7.2, f * 2.0, t * 1.62, 4.3);
	float body = s1 * 0.56 + s2 * 0.30 + s3 * 0.18;
	// Radial-only grain; angular noise would tear open at the u = 0 seam.
	body *= 0.72 + 0.55 * vnoise(vec2(depth * 2.4 - t * 0.9, seed * 7.0 + 0.5));
	// Lift the arms and push the gaps to black. Without this the shells average
	// out into an evenly bright pastel disc — which is exactly what the old
	// portal looked like.
	body = clamp(body * 1.45 - 0.10, 0.0, 1.0);

	// The body stops WELL short of the rim so there is a dark moat between the
	// arms and the accretion ring. That gap is what makes the ring read as a
	// ring instead of as the edge of a sticker.
	float body_mask = smoothstep(horizon - 0.03, horizon + 0.24, r)
		* (1.0 - smoothstep(0.64, 0.80, r));

	// Infalling debris, advected down the same tunnel. mod() wraps the angular
	// cell index so the ring of cells closes cleanly across the seam.
	vec2 g = vec2(mod(u * 20.0, 20.0), depth * 4.0 - t * 1.5);
	vec2 gi = floor(g);
	vec2 gf = fract(g) - 0.5;
	float mh = hash(vec2(mod(gi.x, 20.0), gi.y) + vec2(seed, seed * 0.37));
	float mote_bright = 0.45 + 0.55 * fract(mh * 7.3);
	float mote = step(0.88, mh)
		* (1.0 - smoothstep(0.02, 0.22, length(gf * vec2(1.0, 0.28))))
		* body_mask * mote_bright;

	// Gaussians written as d*d, never pow(d, 2.0): d is negative on the inner
	// side of every one of these bands and pow() of a negative base is
	// undefined in GLSL (it is exp2(y * log2(x)) on most drivers, i.e. NaN).
	float dring = (r - 0.84) / 0.055;
	float ring = exp(-dring * dring);
	float ring_streak = 0.55 + 0.45 * sin(u * f * 4.0 * TAUC - t * 3.0);
	float dlip = (r - horizon - 0.03) / 0.062;
	float lip = exp(-dlip * dlip);
	float well = 1.0 - smoothstep(horizon - 0.09, horizon + 0.05, r);

	vec3 base = vivid(hue_color.rgb);
	vec3 hot = mix(base, vec3(1.0), 0.22);           // tinted white, never pure

	vec3 col = base * 0.06;                          // the well is not black
	col += base * body * 1.55 * body_mask;
	col += hot * pow(clamp(body, 0.0, 1.0), 3.0) * 0.55 * body_mask;
	col += base * ring * ring_streak * 2.10;         // accretion ring
	col += hot * ring * 0.55;
	col += hot * lip * 1.85 * core_heat;             // the horizon burns
	col += mix(base, hot, 0.5) * mote * 0.85;
	col *= mix(1.0, 0.14, well);                     // event horizon
	col *= 1.0 - 0.30 * smoothstep(0.90, 1.06, r);   // limb darkening: a disc
	col = soft_clip(col, peak_luma);

	// Opaque through the middle so the dark floor behind can never mud it out.
	float alpha = (1.0 - smoothstep(0.88, 1.0, r))
		* clamp(0.50 + 0.65 * body + ring + lip + well, 0.0, 1.0) * hue_color.a;
	COLOR = vec4(col, alpha);
}
