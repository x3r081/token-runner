shader_type canvas_item;
render_mode blend_mix, unshaded;
// A doorway, not a light source, and PIXEL ART rather than a gradient.
//
// VISUAL_BIBLE_V2 LAW 4: a portal should be FINDABLE, not dominant — 48px of
// art at 2x, a soft slow swirl in one accent, light energy 0.5, no halo.
// VISUAL_BIBLE_V2 LAW 1: every world-space pixel is 2x2 screen pixels. A shader
// sampling continuous UV obeys neither, which is why the round-6 frames read as
// "smooth-gradient swirl blobs" sitting on top of a pixel-art game.
//
// ROUND 7, in the order a viewer notices it:
//
//   THE CELL GRID. Everything below is computed from the CENTRE of one of 24x24
//     cells, so the disc is built from chunky square pixels at any zoom. Cell
//     centres and not floor(UV*24)/24 on purpose: 12/24 is exactly 0.5, so
//     corner sampling puts the disc half a cell off its own centre and the
//     circle comes out lopsided.
//   FOUR LEVELS. The swirl is quantised to four flat steps between two tones.
//     There is no ramp left anywhere in the output.
//   TWO TONES. `lit` (the accent) and `deep` (the accent darkened 45%). That is
//     the entire palette. No white, no third colour, no sparkle.
//   A FULL CIRCLE. The mask was an ANNULUS (a hole at r < horizon, fading out
//     from 0.62) multiplied by an angular band, and the two together printed the
//     half-rendered crescent in region_corporate_enterprise.png. The mask is now
//     a hard circular cut on the cell grid; only the swirl varies with angle.
//
// Already gone from earlier rounds and staying gone: the white core / horizon
// lip burn, the accretion ring, the infalling mote grid, the noise grain, the
// three parallaxing shells.

uniform vec4 hue_color : source_color = vec4(0.55, 0.36, 0.96, 1.0);
uniform float speed = 0.6;
uniform float arms = 2.0;
// Kept for the CPU-side near-approach response: it lifts the swirl a little as
// the player closes, which is the only thing about the portal that reacts.
uniform float core_heat : hint_range(0.0, 2.0) = 1.0;
uniform float depth_scale : hint_range(0.2, 3.0) = 1.0;
// Radius inside which the swirl reads as the deep tone — a dark eye, not a
// hole: the disc itself is unbroken.
uniform float horizon : hint_range(0.05, 0.5) = 0.26;
uniform float peak_luma : hint_range(0.5, 4.0) = 1.05;
// Extra rotation accumulated on the CPU. ADDED to the clock rather than
// scaling it, because scaling TIME mid-animation snaps the phase by however
// many seconds the game has been open.
uniform float phase = 0.0;
uniform float seed = 0.0;

const float TAUC = 6.28318530718;
// Cells across the quad, and flat shading steps between the two tones.
const float CELLS = 24.0;
const float LEVELS = 4.0;
// Where the disc ends, in cell-quantised radius. Inside the quad's inscribed
// circle so the cut never clips against the sprite's own corner.
const float RIM = 0.94;

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
	// LAW 1. One sample per cell, taken at the cell's centre.
	vec2 cell = (floor(UV * CELLS) + 0.5) / CELLS;
	vec2 p = cell - 0.5;
	float r = length(p) * 2.0;                       // 1.0 at the inscribed disc
	float u = fract(atan(p.y, p.x) / TAUC + 1.0);    // 0..1 around the disc
	float t = TIME * speed + phase;
	float depth = depth_scale * 0.55 / max(r, 0.12);
	float f = max(1.0, floor(arms + 0.5));           // integer harmonics only

	// Two bands, half a turn apart, marching inward at slightly different
	// rates. The quantiser below is what turns them into a swirl you could have
	// drawn by hand.
	float b1 = 0.5 + 0.5 * sin(u * f * TAUC + depth * 2.6 - t * 1.6 + seed);
	float b2 = 0.5 + 0.5 * sin(u * f * TAUC + depth * 3.9 - t * 1.1 + seed + 3.1);
	float body = b1 * 0.62 + b2 * 0.38;

	// FOUR flat steps, 0 .. 1. No smoothstep, no gradient, nothing in between.
	float shade = clamp((body - 0.30) / 0.65, 0.0, 1.0);
	shade *= step(horizon, r);                       // the dark eye
	float band = min(floor(shade * LEVELS), LEVELS - 1.0) / (LEVELS - 1.0);

	// The disc: a hard circular cut, chunky because `r` came off the cell grid.
	float disc = 1.0 - step(RIM, r);

	vec3 lit = vivid(hue_color.rgb);
	vec3 deep = lit * 0.55;                          // the accent, darkened 45%
	vec3 col = mix(deep, lit, band);
	// The near-approach response: the whole swirl lifts a couple of percent.
	// Capped well under LAW 3's "only genuinely overbright pixels bloom".
	col *= mix(0.94, 1.02, clamp(core_heat, 0.0, 2.0) * 0.5);
	col = ceiling(col, peak_luma);

	// LAW 4: alpha <= 0.85, so the floor is always faintly visible through the
	// doorway. A portal you cannot see the room through is a hole in the frame.
	float alpha = disc * clamp(0.34 + 0.48 * band, 0.0, 0.85) * hue_color.a;
	COLOR = vec4(col, alpha);
}
