shader_type canvas_item;
render_mode blend_mix, unshaded;
// A doorway, not a light source. VISUAL_BIBLE_V2 LAW 4: a portal should be
// FINDABLE, not dominant — 48px of art at 2x, a soft slow swirl in the
// destination ACCENT, light energy 0.5, no halo.
//
// Round 6 removed, deliberately and in this order, everything that made the
// old vortex the brightest object in all ten QA frames:
//   * the WHITE CORE / horizon lip burn. There is no white in here at all now;
//     the brightest pixel is the accent itself, barely above 1.0.
//   * the accretion RING and its streaking. A ring is a lamp with a hole.
//   * the infalling mote grid and the noise grain — sparkle at rest.
//   * three parallaxing shells down a 1/r tunnel, replaced by TWO slow bands.
//   * the old soft_clip()'s headroom: peak_luma is 1.05 now, not 1.85, so the
//     brightest filament only just crosses the engine's HDR threshold of 1.0
//     and therefore only just blooms.
//
// Two tones, both derived from one hue: `deep` (the dark the swirl turns in)
// and `lit` (the accent). That is the whole palette.

uniform vec4 hue_color : source_color = vec4(0.55, 0.36, 0.96, 1.0);
uniform float speed = 0.6;
uniform float arms = 2.0;
// Kept for the CPU-side near-approach response: it lifts the swirl a little as
// the player closes, which is the only thing about the portal that reacts.
uniform float core_heat : hint_range(0.0, 2.0) = 1.0;
uniform float depth_scale : hint_range(0.2, 3.0) = 1.0;
uniform float horizon : hint_range(0.05, 0.5) = 0.26;
uniform float peak_luma : hint_range(0.5, 4.0) = 1.05;
// Extra rotation accumulated on the CPU. ADDED to the clock rather than
// scaling it, because scaling TIME mid-animation snaps the phase by however
// many seconds the game has been open.
uniform float phase = 0.0;
uniform float seed = 0.0;

const float TAUC = 6.28318530718;

// Full value, same hue. Near-white inputs degrade gracefully. The bible's
// muted accents (stackoverflow gold #E8C46B, cloud sky #6BC7FF) would
// otherwise read as sludge against a near-black floor.
vec3 vivid(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	vec3 n = c / max(mx, 0.001);
	float lum = dot(n, vec3(0.299, 0.587, 0.114));
	return clamp(mix(vec3(lum), n, 1.30), vec3(0.0), vec3(1.0));
}

// Hue-preserving ceiling: every channel scales by the same factor, so the
// brightest pixel in the portal lands exactly on `peak` and the hue survives.
// At peak 1.05 the swirl sits one hair over the engine's HDR threshold of
// 1.0 — it picks up a whisper of bloom and nothing more.
vec3 ceiling(vec3 c, float peak) {
	float m = max(c.r, max(c.g, c.b));
	if (m <= peak || m < 0.0001) {
		return c;
	}
	return c * (peak / m);
}

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;                       // 1.0 at the inscribed disc
	float u = fract(atan(p.y, p.x) / TAUC + 1.0);    // 0..1 around the disc
	float t = TIME * speed + phase;
	float depth = depth_scale * 0.55 / max(r, 0.12);
	float f = max(1.0, floor(arms + 0.5));           // integer harmonics only

	// Two soft bands, half a turn apart, marching inward at slightly different
	// rates. sin() straight through with no pow(): a soft band is the point.
	float b1 = 0.5 + 0.5 * sin(u * f * TAUC + depth * 2.6 - t * 1.6 + seed);
	float b2 = 0.5 + 0.5 * sin(u * f * TAUC + depth * 3.9 - t * 1.1 + seed + 3.1);
	float body = b1 * 0.62 + b2 * 0.38;
	body = smoothstep(0.30, 0.95, body);

	// The swirl lives in an annulus and fades out well before the rim, so the
	// portal has a soft edge instead of the cut-out look of a sticker.
	float mask = smoothstep(horizon - 0.06, horizon + 0.30, r)
		* (1.0 - smoothstep(0.62, 0.94, r));

	vec3 lit = vivid(hue_color.rgb);
	vec3 deep = lit * 0.10;                          // the dark it turns in

	vec3 col = mix(deep, lit * 1.20, body * mask);
	// The near-approach response: the whole swirl lifts a little, no hot spot.
	col *= mix(0.90, 1.04, clamp(core_heat, 0.0, 2.0) * 0.5);
	col *= 1.0 - 0.22 * smoothstep(0.86, 1.02, r);   // limb darkening: a disc
	col = ceiling(col, peak_luma);

	// LAW 4: alpha <= 0.85, so the floor is always faintly visible through the
	// doorway. A portal you cannot see the room through is a hole in the frame.
	float alpha = (1.0 - smoothstep(0.84, 1.0, r))
		* clamp(0.34 + 0.52 * body, 0.0, 0.85) * hue_color.a;
	COLOR = vec4(col, alpha);
}
