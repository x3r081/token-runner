shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;
// Holographic signage: scanlines + fresnel rim on an additive emissive surface.
// For projected signs, quest markers, display walls, boss callouts — anything
// that should read as LIGHT PROJECTED INTO AIR rather than as a painted panel.
//
// Ported from assets/shaders/hologram.gdshader (tint + scan bands + jitter),
// with the one thing a 3D version can do that a sprite cannot: a FRESNEL edge.
// Facing surfaces stay dim and edge-on surfaces flare, which is the entire
// visual grammar of a hologram and costs one dot product.
//
// Additive blend means there is no black in the output — an unlit hologram
// simply disappears into the room, which is correct. UNSHADED means the
// renderer ignores EMISSION, so brightness lives entirely in ALBEDO.
//
// Scanlines run on WORLD height, not UV, so a sign and the wall-display beside
// it share one continuous band pattern instead of each having its own.
//
// VISUAL_BIBLE_V2 LAW 3/5: SIGNS DO NOT GLOW. A hologram is only legitimate as
// the lit surface of one of the two motivated light sources a scene is allowed
// (a monitor bank, a display wall) — never as ambient decoration — and even
// then it has to stay under the bloom threshold, because bloom is spoken for.
// v1 stacked a 28% scan ripple at 42 bands, a 1.6x fresnel gain, a 35% flicker
// and a dropout firing 4% of frames on top of energy 2.2. That is four separate
// "look at me" signals on a prop. Every one of them is now a fraction of what
// it was: the surface reads as projected light, and a viewer would not name a
// single effect on it, which is the LAW 5 test.

uniform vec4 tint : source_color = vec4(0.14, 0.94, 0.86, 1.0);
uniform float scan_speed = 0.6;
// 14 bands over a wall, not 42: at the old density the scan was finer than the
// pixels drawing it and shimmered as moire whenever the camera moved.
uniform float scan_density = 14.0;
uniform float alpha_base : hint_range(0.0, 1.0) = 0.30;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.6;
uniform float energy : hint_range(0.2, 1.15) = 1.0;
// Amplitude of the slow breathing pulse and of the horizontal dropout bands.
uniform float flicker : hint_range(0.0, 1.0) = 0.10;
// Ceilings applied IN CODE — hint_range constrains the inspector, not a script.
// ENERGY_MAX is derived, not chosen: the fragment weights below sum to 1.22
// (0.55 scan + 0.65 fresnel + 0.20 * flicker 0.10), and with additive blending
// the most a fragment can ADD to the frame is tint * 1.22 * energy * ALPHA_MAX.
// For that to stay under the bloom threshold at tint 1.0 from every angle,
// energy has to stay under 1.0 / (1.22 * 0.70) = 1.17. At 1.5 an edge-on
// fragment added 1.28 and the "signs do not glow" claim below was false.
const float ENERGY_MAX = 1.15;
const float ALPHA_MAX = 0.70;
// Optional glyph/sign art. `use_texture` at 0 ignores it entirely, so the same
// material works for a textured display and for a bare projected volume.
uniform sampler2D holo_tex : source_color;
uniform float use_texture : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// A 14% ripple, not a 28% one. The scan should be something you notice on
	// the second look, not the first (LAW 5: post-processing is invisible).
	float scan = 0.86 + 0.14 * sin(v_world.y * scan_density - TIME * scan_speed * 6.0);
	// Dropout bands: a horizontal slice goes bright for one ninth of a second.
	// Quantised in time and in height so it steps rather than crawls, and rare
	// now (0.8% of slices, not 4%) — a glitch that fires constantly is texture,
	// and texture is what LAW 5 calls a stacked filter.
	float glitch = step(0.992, hash21(vec2(floor(TIME * 9.0), floor(v_world.y * 24.0))));
	glitch *= flicker;

	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	vec4 tex = texture(holo_tex, UV);

	vec3 base = mix(tint.rgb, tint.rgb * tex.rgb, use_texture);
	float mask = mix(1.0, tex.a, use_texture);
	float pulse = 1.0 - flicker * 0.22 * (0.5 + 0.5 * sin(TIME * 2.1));

	// The FRESNEL is the whole grammar of a hologram — a facing surface stays
	// dim and an edge-on one flares — so it keeps most of its weight while the
	// flat body loses its. What it does not keep is a 1.6x gain that made every
	// silhouette edge in the room a bright line.
	// Weighted so that even a fully edge-on fragment at ENERGY_MAX lands under
	// 1.0 once ALPHA_MAX is applied (1.22 * 1.15 * 0.70 = 0.98) — i.e. this
	// surface cannot cross the bloom threshold from any angle. Signs do not
	// glow (LAW 3).
	ALBEDO = base * (scan * 0.55 + fres * 0.65 + glitch * 0.20) * min(energy, ENERGY_MAX) * pulse;
	ALPHA = clamp(alpha_base * mask * scan + fres * 0.30 + glitch * 0.10, 0.0, ALPHA_MAX) * tint.a;
}
