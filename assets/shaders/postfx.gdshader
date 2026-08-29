shader_type canvas_item;
// Full-screen post-processing: the whole camera-and-film-stock chain in one
// pass. Apply to a screen-covering ColorRect in a CanvasLayer BETWEEN the world
// and the HUD. Order inside fragment(), which is the order a real camera would
// do it in:
//
//   lens    chromatic aberration, stress glitch slip
//   optics  bloom extraction from the screen mip chain, clarity (local contrast)
//   film    black point -> lift -> gamma -> S-curve -> saturation/bleach ->
//           highlight gain (split-tone) -> filmic shoulder
//   print   bloom add, scanlines, grain, vignette, incident wash
//
// STRESS is the comedy channel. As technical debt climbs, the frame itself
// starts to lose its composure: saturation drains except in the reds, the
// corners heat up and breathe, the grain and fringing thicken, and past the
// halfway mark the odd scanline slips sideways as though the compositor had
// also stopped caring. At stress = 0 every one of those terms multiplies out to
// nothing, so a clean run gets the clean grade.
//
// wash_amount/wash_color is a one-shot flash for incidents — seeded to 0 and
// pulsed by postfx_layer.pulse().
//
// ROUND 5 — the QA frames said the same thing in ten different hues: every
// region was ONE colour from corner to corner (gpu_mines red soup, wildlands
// green soup, api_bazaar magenta soup) and the mid-values were hazy. Three new
// tools fix that, and every one of them defaults to OFF so any consumer that
// only sets the round-4 uniforms renders exactly what it rendered before:
//
//   black_point      a soft toe that re-anchors true black BEFORE the shadow
//                    lift, so the lift reads as colour in the shadows instead
//                    of as milk.
//   grade_gain       luma-weighted highlight tint. With grade_lift tinting the
//                    shadows the other way, that is split-toning — the single
//                    biggest reason a frame stops being monochrome.
//   highlight_desat  bleaches the top end toward white. Film does this; it is
//                    why a hot ember reads as HEAT and not as "more orange".
//   bloom_*          a selective bloom off the screen mip chain, thresholded
//                    per mip so only genuinely bright things glow and
//                    mid-values stay crisp. NOTE: this is SUPPLEMENTARY, not
//                    the project's only glow — world.gd::_setup_glow() adds a
//                    WorldEnvironment with glow_enabled and an HDR threshold of
//                    1.0, so everything the artists pushed overbright already
//                    blooms in the engine. What this adds is the near-white
//                    band UNDER that threshold plus a tintable halo, which is
//                    why the per-region intensities are deliberately low: two
//                    bloom passes over the same emissive pixel blow it out.
//   clarity          unsharp against mip 3: mid-frequency local contrast, the
//                    direct antidote to "hazy".

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.28;
uniform float aberration : hint_range(0.0, 4.0) = 1.1;
uniform float grain_amount : hint_range(0.0, 0.2) = 0.028;
uniform float scanline_amount : hint_range(0.0, 0.3) = 0.04;
uniform float scanline_count = 540.0;
uniform vec3 grade_lift = vec3(0.012, 0.008, 0.03);
uniform vec3 grade_gamma = vec3(1.0, 0.99, 0.94);
uniform float saturation : hint_range(0.0, 2.0) = 1.16;
// Gentle S-curve applied after the lift. The lift is what stops shadows going
// dead black; without a counter-curve it also turns the whole frame into haze.
uniform float contrast : hint_range(0.0, 0.6) = 0.12;
// Filmic response on the displayable range: rolled toe, slight mid lift, soft
// shoulder. Anything above 1.0 (neon cores, portal lips) bypasses it entirely,
// so bloom sources keep blooming while the mid-values between the focal glow
// and the frame edge stop greying into the wash. 0 restores the old linear
// response.
uniform float filmic : hint_range(0.0, 1.0) = 0.30;
// --- round 5 additions, all inert at their defaults -------------------------
// Black re-anchor, applied BEFORE the lift so the two are not fighting: the
// lift then colours the shadows it rebuilds instead of flattening them. It is a
// soft TOE, not a subtract — see the note at the use site.
uniform float black_point : hint_range(0.0, 0.24) = 0.0;
// Highlight tint, weighted by luma. Pair with a complementary grade_lift for
// split-toning (cold shadows under hot highlights, or the reverse).
uniform vec3 grade_gain = vec3(1.0, 1.0, 1.0);
// How hard the top end bleaches toward white. 0 keeps the old behaviour.
uniform float highlight_desat : hint_range(0.0, 1.0) = 0.0;
// Local contrast against a blurred copy of the frame. Small numbers only —
// past ~0.35 it starts drawing dark rings around bright props.
uniform float clarity : hint_range(0.0, 0.6) = 0.0;
// Selective bloom. bloom_intensity 0 skips the mip taps entirely.
uniform float bloom_intensity : hint_range(0.0, 2.0) = 0.0;
uniform float bloom_threshold : hint_range(0.2, 2.0) = 0.86;
uniform float bloom_knee : hint_range(0.0, 1.0) = 0.35;
uniform vec3 bloom_tint = vec3(1.0, 1.0, 1.0);
uniform float stress : hint_range(0.0, 1.0) = 0.0;
uniform vec3 stress_tint = vec3(1.0, 0.55, 0.50);
uniform vec4 wash_color : source_color = vec4(1.0, 0.28, 0.32, 1.0);
uniform float wash_amount : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Soft-knee bright pass. Below `thr` nothing survives; through the knee the
// response is quadratic, so a light that crosses the threshold fades IN rather
// than popping on as the player walks toward it.
vec3 bright_pass(vec3 c, float thr, float knee) {
	float l = max(max(c.r, c.g), c.b);
	float k = max(knee * thr, 0.0001);
	float soft = clamp(l - thr + k, 0.0, 2.0 * k);
	soft = soft * soft / (4.0 * k);
	float w = max(l - thr, soft) / max(l, 0.0001);
	return c * max(w, 0.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 center = uv - 0.5;
	float dist = length(center);
	float st = clamp(stress, 0.0, 1.0);
	float breathe = 0.62 + 0.38 * sin(TIME * 2.3);

	// Past the halfway mark, the occasional scanline slips sideways. Quadratic
	// in stress so a moderately indebted run never sees it at all.
	float slice = floor(uv.y * 44.0);
	float tick = floor(TIME * 11.0);
	float glitch = step(0.988, hash(vec2(slice, tick))) * st * st;
	uv.x += (hash(vec2(slice, tick + 3.0)) - 0.5) * 0.014 * glitch;

	// Chromatic aberration, stronger at edges — and stronger under stress.
	float aberr = aberration * (1.0 + st * 0.9);
	vec2 ca = center * dist * aberr * 0.004 * intensity;
	float r = textureLod(screen_tex, uv + ca, 0.0).r;
	float g = textureLod(screen_tex, uv, 0.0).g;
	float b = textureLod(screen_tex, uv - ca, 0.0).b;
	vec3 col = vec3(r, g, b);

	// Clarity: unsharp mask against mip 3. Runs on the RAW frame, before any
	// grading, so it sharpens what the artists drew and not what the grade did
	// to it. max() keeps the dark side of an edge from going negative.
	if (clarity > 0.001) {
		vec3 soft_ref = textureLod(screen_tex, uv, 3.0).rgb;
		col = max(col + (col - soft_ref) * clarity * intensity, vec3(0.0));
	}

	// Bloom, also off the raw frame: the grade must not be able to invent a
	// light source that was never in the scene. Low mips carry small hot
	// details (a neon glyph, a projectile), high mips carry the wide halo of
	// genuinely large emitters — and their thresholds ease down with mip level
	// because box-averaging has already dimmed whatever was in them.
	vec3 bloom = vec3(0.0);
	if (bloom_intensity > 0.001) {
		bloom = bright_pass(textureLod(screen_tex, uv, 2.0).rgb, bloom_threshold, bloom_knee) * 0.40;
		bloom += bright_pass(textureLod(screen_tex, uv, 3.5).rgb, bloom_threshold * 0.92, bloom_knee) * 0.30;
		bloom += bright_pass(textureLod(screen_tex, uv, 5.0).rgb, bloom_threshold * 0.84, bloom_knee) * 0.20;
		bloom += bright_pass(textureLod(screen_tex, uv, 6.5).rgb, bloom_threshold * 0.76, bloom_knee) * 0.10;
		bloom *= bloom_tint * bloom_intensity * intensity;
	}

	// Re-anchor black BEFORE the lift, then lift toward indigo and warm the
	// gamma. Without the anchor the lift alone is what made the round-4 frames
	// read as fog with a colour in it.
	//
	// A straight `col - bp` is what a colourist does to footage that lives in
	// the top two thirds of the range. This frame does not: the world is drawn
	// under a CanvasModulate at 0.6-0.8 and the QA captures sit at a median
	// luma of 0.05-0.13, so a hard subtract clips the entire FLOOR to one flat
	// black and takes the round-4 readability pass down with it (measured: raw
	// 0.05 -> 0.020 in gpu_mines, against 0.054 in round 4). A soft toe removes
	// the same haze at the values where haze actually lives and only COMPRESSES
	// what is below it, so the deep shadows keep their gradation instead of
	// banding. f(0) = 0, f(1) = 1, and f(x) -> x - bp once x >> bp, which is
	// where the haze is; at bp = 0 it is the identity, so the uniform stays
	// inert at its default.
	float bp = clamp(black_point, 0.0, 0.24) * intensity;
	col = col * col * (1.0 + bp) / max(col + bp, vec3(0.0001));
	col = pow(max(col + grade_lift * intensity, vec3(0.0)), 1.0 / grade_gamma);
	// S-curve on the 0..1 range only, so HDR values above 1.0 (neon cores,
	// portals, emissive pixels) pass through untouched and still bloom.
	vec3 lowc = clamp(col, vec3(0.0), vec3(1.0));
	col += (lowc * lowc * (3.0 - 2.0 * lowc) - lowc) * contrast * intensity;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	float sat = saturation * mix(1.0, 0.76, st);
	col = mix(vec3(luma), col, mix(1.0, sat, intensity));
	// Split-tone: the gain only reaches the upper half of the range, so it
	// tints highlights while grade_lift owns the shadows. It runs BEFORE the
	// bleach, or the bleach's white top end would just be re-tinted back to the
	// region's one colour and we would be exactly where we started.
	col *= mix(vec3(1.0), grade_gain, smoothstep(0.12, 0.80, luma) * intensity);
	// Bleach the top end toward white rather than toward grey — a hot thing
	// gets HOTTER, it does not get duller, and the frame stops being one hue.
	if (highlight_desat > 0.001) {
		float maxc = max(max(col.r, col.g), col.b);
		float hot = smoothstep(0.55, 1.05, maxc);
		col = mix(col, vec3(maxc), hot * highlight_desat * intensity);
	}
	// Colour drains toward the tint rather than toward grey: the frame goes
	// feverish, not dead.
	col = mix(col, col * stress_tint, st * 0.30);

	// Filmic tone response (see the uniform note). The HDR excess is split off
	// first and added back untouched — the curve only shapes what a monitor can
	// actually show.
	vec3 ldr = clamp(col, vec3(0.0), vec3(1.0));
	vec3 excess = col - ldr;
	vec3 shaped = (ldr * (2.51 * ldr + 0.03)) / (ldr * (2.43 * ldr + 0.59) + 0.14);
	col = mix(ldr, clamp(shaped, vec3(0.0), vec3(1.0)), filmic * intensity) + excess;

	// Bloom goes on AFTER the grade and BEFORE the vignette: light added by the
	// lens is not subject to the film's curve, but it is subject to the lens's
	// own corner falloff.
	col += bloom;

	// Scanlines — extremely subtle.
	float scan = sin(uv.y * scanline_count * 3.14159);
	col *= 1.0 - scanline_amount * intensity * (0.5 + 0.5 * scan);

	// Film grain (animated).
	float gr = hash(uv * vec2(1920.0, 1080.0) + fract(TIME) * 61.7) - 0.5;
	col += gr * grain_amount * (1.0 + st * 0.9) * intensity;

	// Vignette, plus a slow hot pulse in the corners once debt is real.
	// Round 4: the old single smoothstep started darkening at dist 0.25, so
	// half the frame paid a value tax and the mid-ground sank into the wash
	// (see the gpu_mines / wildlands QA frames). The plateau now holds clean
	// to ~0.42, and a separate corner term buys the darkness back at the very
	// edge — darker corners, wider clean center.
	float vig = smoothstep(0.78, 0.42, dist);
	float vamt = clamp(vignette_strength + st * 0.10 * breathe, 0.0, 1.0);
	col *= mix(1.0, vig, vamt * intensity);
	float corner = smoothstep(0.55, 0.85, dist);
	col *= 1.0 - corner * corner * vamt * 0.6 * intensity;
	col += stress_tint * (1.0 - vig) * st * 0.09 * breathe;

	// Incident flash.
	col += wash_color.rgb * wash_color.a * wash_amount;

	COLOR = vec4(col, 1.0);
}
