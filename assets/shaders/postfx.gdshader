shader_type canvas_item;
// Full-screen post-processing: vignette + chromatic aberration + film grain
// + subtle scanlines + neon color grade. Apply to a screen-covering ColorRect
// in a CanvasLayer BETWEEN the world and the HUD.
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
uniform float stress : hint_range(0.0, 1.0) = 0.0;
uniform vec3 stress_tint = vec3(1.0, 0.55, 0.50);
uniform vec4 wash_color : source_color = vec4(1.0, 0.28, 0.32, 1.0);
uniform float wash_amount : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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

	// Grade: lift shadows toward indigo, warm the gamma, boost saturation.
	col = pow(max(col + grade_lift * intensity, vec3(0.0)), 1.0 / grade_gamma);
	// S-curve on the 0..1 range only, so HDR values above 1.0 (neon cores,
	// portals, emissive pixels) pass through untouched and still bloom.
	vec3 lowc = clamp(col, vec3(0.0), vec3(1.0));
	col += (lowc * lowc * (3.0 - 2.0 * lowc) - lowc) * contrast * intensity;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	float sat = saturation * mix(1.0, 0.76, st);
	col = mix(vec3(luma), col, mix(1.0, sat, intensity));
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
