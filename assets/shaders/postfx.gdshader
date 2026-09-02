shader_type canvas_item;
// Full-screen post-processing. VISUAL_BIBLE_V2 LAW 5: post-processing is
// INVISIBLE. A viewer must not be able to name a single effect on this pass.
//
// Round 6 deleted the entire film-stock chain that used to live here —
// chromatic aberration, scanlines, a second bloom pass over the engine's own
// glow, clarity/unsharp, the black-point toe, split-toning, the filmic
// shoulder, and the "stress" grade that smeared the frame as technical debt
// climbed. Stacked, they were the single biggest reason every glyph in the QA
// frames had a red/cyan fringe standing on a bed of grain.
//
// What is left, and why each survives:
//   grade_lift/saturation  neutral by default (0 / 1.0). They exist so a future
//                          region can be nudged, not so ten regions can each be
//                          a different colour filter — region mood comes from
//                          the ambient CanvasModulate and the lights.
//   vignette               0.14, wide plateau. Corners only; the frame never
//                          pays a value tax for being off-centre.
//   grain                  <= 0.012. Present only to break up flat gradients.
//   wash                   one short coloured flash on an incident. An EVENT,
//                          not a filter: it is 0 except for half a second.
//
// Bloom is the engine's, once: world.gd::_setup_glow() runs a WorldEnvironment
// at HDR threshold 1.0 with two glow levels. Two bloom passes over the same
// emissive pixel is how everything ended up white.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float vignette_strength : hint_range(0.0, 0.4) = 0.14;
uniform float grain_amount : hint_range(0.0, 0.03) = 0.010;
uniform vec3 grade_lift = vec3(0.0, 0.0, 0.0);
uniform float saturation : hint_range(0.5, 1.5) = 1.0;
uniform vec4 wash_color : source_color = vec4(1.0, 0.28, 0.32, 1.0);
uniform float wash_amount : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float dist = length(uv - 0.5);

	// One tap. No per-channel offset, which is what "aberration 0" means in
	// practice: the three channels are sampled at the SAME place, so text has
	// no colour fringe at any distance from centre.
	vec3 col = texture(screen_tex, uv).rgb;

	// Neutral grade. Both terms are identities at their defaults.
	col = max(col + grade_lift * intensity, vec3(0.0));
	if (abs(saturation - 1.0) > 0.001) {
		float luma = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(luma), col, mix(1.0, saturation, intensity));
	}

	// Grain, animated, barely there.
	float gr = hash(uv * vec2(1920.0, 1080.0) + fract(TIME) * 61.7) - 0.5;
	col += gr * grain_amount * intensity;

	// Vignette: a wide clean plateau that only starts closing past 0.62 of the
	// frame radius, so it reads as a lens and never as a mood.
	float vig = smoothstep(0.98, 0.62, dist);
	col *= mix(1.0, vig, clamp(vignette_strength, 0.0, 1.0) * intensity);

	// Incident flash.
	col += wash_color.rgb * wash_color.a * wash_amount;

	COLOR = vec4(col, 1.0);
}
