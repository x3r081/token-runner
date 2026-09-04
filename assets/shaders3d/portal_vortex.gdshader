shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;
// The doorway between regions: a rotating emissive swirl on a disc with a hot
// alpha rim. Meant to sit inside a `mini-dungeon/gate` frame (3D_BIBLE §7) with
// an OmniLight and a particle wisp in front of it.
//
// Ported in SPIRIT from assets/shaders/portal_swirl.gdshader — same two-tone,
// quantised-band swirl so 2D and 3D read as one art direction — but the 2D
// version's whole job was to obey the pixel grid (LAW 1), and there is no pixel
// grid here. The cell quantiser is gone; the BAND quantiser stays, because
// that is what makes the swirl look drawn rather than rendered.
//
// UNSHADED means EMISSION is ignored by the renderer (the fragment output is
// ALBEDO), so all brightness lives in ALBEDO — that is what `energy` is for.
//
// VISUAL_BIBLE_V2 LAW 4: a portal must be FINDABLE, NOT DOMINANT. The v1
// defaults (energy 2.6, rim_alpha 0.88, six hard bands, chroma pushed to 1.30)
// put the whole disc over the bloom threshold, and a doorway that blooms across
// its own frame is the loudest object in a region it is only supposed to be an
// exit from. So: `energy` is hard-clamped to 1.5 IN CODE — a hint_range only
// constrains the inspector, and portal3d.gd builds its own material from this
// shader's defaults rather than from Fx3D.portal_material — the swirl body sits
// under 1.0, and the only thing allowed near the top of the range is the thin
// RIM at the mouth of the gate. The rim is what the eye finds; the body is what
// tells you it is a portal once you have found it.

uniform vec4 hue_color : source_color = vec4(0.55, 0.36, 0.96, 1.0);
uniform float speed = 0.65;
uniform float arms = 2.0;
// Extra rotation accumulated on the CPU. ADDED to the clock rather than
// scaling it, because scaling TIME mid-animation snaps the phase by however
// many seconds the game has been open.
uniform float phase = 0.0;
uniform float seed = 0.0;
// The near-approach response: lifts the whole swirl a few percent as the
// player closes. The only thing about a portal that reacts.
uniform float core_heat : hint_range(0.0, 2.0) = 1.0;
// Radius inside which the swirl reads as the deep tone — a dark eye, not a
// hole. The disc itself is unbroken.
uniform float horizon : hint_range(0.02, 0.5) = 0.28;
uniform float energy : hint_range(0.2, 1.5) = 1.1;
uniform float rim_alpha : hint_range(0.0, 1.0) = 0.55;
uniform float levels : hint_range(2.0, 16.0) = 8.0;
// The v2 ceilings, applied in code because hint_range does not clamp at runtime
// and portal3d.gd sets uniforms on a material it builds itself.
const float ENERGY_MAX = 1.5;
const float OUTPUT_MAX = 1.5;

// TAU is a built-in shader constant in Godot 4; the 2D twin still names its own
// to be certain, and a portal that fails to compile is an invisible exit.
const float TAUC = 6.28318530718;

// Full value, same hue. The bible's muted accents (stackoverflow gold #E8C46B,
// cloud sky #6BC7FF) would otherwise read as sludge in a near-black room.
//
// Chroma 1.05, not 1.30: LAW 2 allows the region ACCENT on one or two emissive
// surfaces, and this is one of them — at its own hue, not at a boosted one. The
// value normalisation is what rescues a muted accent; the extra chroma on top
// was pushing every portal toward the same electric primary regardless of which
// region it stood in, which is three hues becoming one.
vec3 vivid(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	vec3 n = c / max(mx, 0.001);
	float lum = dot(n, vec3(0.299, 0.587, 0.114));
	return clamp(mix(vec3(lum), n, 1.05), vec3(0.0), vec3(1.0));
}

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;          // 1.0 at the quad's inscribed disc
	if (r > 1.0) {
		discard;                        // a disc, not a square
	}
	float u = fract(atan(p.y, p.x) / TAUC + 1.0);
	float t = TIME * speed + phase;
	float depth = 0.55 / max(r, 0.12);  // inward parallax
	float f = max(1.0, floor(arms + 0.5));

	// Two bands half a turn apart, marching inward at slightly different rates.
	float b1 = 0.5 + 0.5 * sin(u * f * TAUC + depth * 2.6 - t * 1.6 + seed);
	float b2 = 0.5 + 0.5 * sin(u * f * TAUC + depth * 3.9 - t * 1.1 + seed + 3.1);
	float body = b1 * 0.62 + b2 * 0.38;

	float shade = clamp((body - 0.30) / 0.65, 0.0, 1.0);
	float lv = max(2.0, floor(levels));
	float steps = min(floor(shade * lv), lv - 1.0) / (lv - 1.0);
	// SOFT swirl (LAW 4). The pure quantiser drew hard-edged rings that read as
	// concentric neon stripes; blending the steps back toward the continuous
	// shade keeps the "drawn, not rendered" look of the 2D twin while letting
	// each band fall off into the next instead of terminating in a bright edge.
	float band = mix(shade, steps, 0.55);
	band *= smoothstep(horizon * 0.6, horizon, r);   // the dark eye

	// The lip of the doorway: a thin hot ring just inside the cut, which is
	// what makes a flat disc read as an opening with depth behind it. This is
	// the ONE part of the portal allowed to approach the brightness ceiling —
	// it is a thin line, it is what makes the gate findable across a room, and
	// LAW 4 asks for exactly that and no halo.
	float rim = smoothstep(0.84, 0.99, r) * (1.0 - smoothstep(0.985, 1.0, r));

	vec3 lit = vivid(hue_color.rgb);
	// A deeper eye than v1's 0.45: the centre of the disc is a hole, and the
	// contrast between that dark and the rim is what sells depth. Brightening
	// the whole disc to sell it was what made it dominate.
	vec3 deep = lit * 0.26;
	vec3 col = mix(deep, lit * 0.80, band);
	col += lit * rim * 0.45;
	col *= min(energy, ENERGY_MAX) * mix(0.92, 1.08, clamp(core_heat, 0.0, 2.0) * 0.5);
	// Hard ceiling on the OUTPUT, not just on the input. The swirl body lands
	// under 1.0 and only the rim is allowed to cross it, so a portal reads as a
	// lit doorway and never as a bloom source, whatever a caller seeds.
	col = min(col, vec3(OUTPUT_MAX));

	float alpha = clamp(0.16 + 0.34 * band + 0.42 * rim, 0.0, rim_alpha);
	alpha *= hue_color.a * (1.0 - smoothstep(0.97, 1.0, r));

	ALBEDO = col;
	ALPHA = alpha;
}
