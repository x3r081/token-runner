shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;
// The mark a shockwave leaves ON THE FLOOR.
//
// Why this exists at all: in a 3/4 top-down view an expanding hoop in the air
// is a thin ellipse the eye reads as a line, while a ring painted on the ground
// reads instantly as force travelling outward from a point — it is the single
// cheapest thing that makes a 3D detonation legible from this camera. Fx3D
// draws it on a floor-aligned quad a few centimetres above the tiles and sweeps
// `progress` 0 -> 1 while `fade` falls to 0.
//
// One quad, one draw call, no geometry: the annulus is entirely in the radius
// term, and it THINS as it expands, which is what keeps a growing ring reading
// as a ring instead of as a growing disc.

// VISUAL_BIBLE_V2 LAW 5/6: this decal lies ON a mid-value floor that is now a
// readable MATERIAL with its own three tones, not on near-black void. At v1's
// energy 3.0 with a 0.18 band it painted a saturated disc over that material
// and erased it for half a second. It is now a THIN, DIM mark: the floor stays
// legible through it, which is the only way a ground ripple reads as force
// travelling across ground rather than as a light switching on.
uniform vec4 ring_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float thickness : hint_range(0.01, 0.6) = 0.10;
uniform float energy : hint_range(0.1, 2.0) = 0.95;
uniform float fade : hint_range(0.0, 1.0) = 0.6;
// Ceilings applied IN CODE — hint_range constrains the inspector, not a
// set_shader_parameter() call from a script that has not read this file.
const float ENERGY_MAX = 1.6;
const float ALPHA_MAX = 0.60;
// Radial spokes (0 = a clean ring). An integer count > 0 breaks the ring into
// petals — used for boss-phase waves so they cannot be mistaken for a hit.
uniform float spokes = 0.0;
// Dim wash left inside the wavefront, so the ground looks scorched rather than
// merely outlined.
uniform float inner_wash : hint_range(0.0, 0.25) = 0.05;

const float TAUC = 6.28318530718;

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	if (r > 1.0) {
		discard;
	}
	float th = max(thickness * (1.0 - progress * 0.55), 0.012);
	float band = 1.0 - smoothstep(0.0, th, abs(r - progress));

	float sp = 1.0;
	if (spokes > 0.5) {
		float u = atan(p.y, p.x) / TAUC;
		sp = 0.55 + 0.45 * sin(u * TAUC * max(1.0, floor(spokes)));
	}

	float wash = inner_wash * (1.0 - smoothstep(progress - th, progress, r));
	// Soft cut at the quad's inscribed circle so the decal never shows a corner.
	float edge = 1.0 - smoothstep(0.92, 1.0, r);

	// Almost all the brightness now lives in the BAND rather than in a floor
	// term: the wavefront is the effect, and the area behind it is a hint.
	ALBEDO = ring_color.rgb * min(energy, ENERGY_MAX) * (0.22 + 0.78 * band);
	ALPHA = clamp(band * sp + wash, 0.0, ALPHA_MAX) * fade * edge * ring_color.a;
}
