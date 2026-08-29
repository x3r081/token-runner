shader_type canvas_item;
render_mode blend_add, unshaded;
// Emergency beacon: a slow rotating beam plus a two-blip strobe, washed over
// the whole room. Production is on fire and the light in the ceiling has been
// doing this for four hours; nobody has looked up.
//
// Deliberately gentle — the beam does most of the work and the flash is a
// short, low-amplitude blip, so the frame gets tension without becoming a
// migraine. Additive, so it can only add light (Godot's blend_add uses
// COLOR.rgb * COLOR.a, hence alpha pinned at 1.0).

uniform vec4 wash_color : source_color = vec4(1.0, 0.22, 0.26, 1.0);
uniform float period : hint_range(0.4, 12.0) = 3.1;
uniform float intensity : hint_range(0.0, 1.0) = 0.20;
uniform float sweep_speed : hint_range(0.0, 3.0) = 0.34;
uniform float beam_width : hint_range(2.0, 48.0) = 16.0;
uniform float edge_bias : hint_range(0.0, 1.0) = 0.55;
uniform vec2 beacon = vec2(0.5, 0.16);
uniform vec2 aspect = vec2(1.33, 1.0);

const float TAUC = 6.28318530718;

void fragment() {
	float t = TIME;
	float ph = fract(t / period);
	// Two blips: the flash, then the tired echo of the flash. Written as d*d —
	// pow() of a negative base is undefined in GLSL, and d is negative for the
	// whole first half of each blip.
	float d1 = (ph - 0.06) / 0.045;
	float d2 = (ph - 0.17) / 0.050;
	float flash = exp(-d1 * d1) + 0.45 * exp(-d2 * d2);

	vec2 d = (UV - beacon) * aspect;
	float ang = atan(d.y, d.x);
	float beam = pow(max(0.5 + 0.5 * cos(ang - t * sweep_speed * TAUC), 0.0), beam_width);
	// The beam thins out close to the fixture and spreads as it travels.
	float dist = clamp(length(d) * 1.05, 0.0, 1.0);
	float body = mix(1.0, dist, edge_bias);

	float a = intensity * (0.30 * flash + 0.90 * beam * (0.40 + 0.60 * flash)) * body;
	COLOR = vec4(wash_color.rgb * clamp(a, 0.0, 1.0) * wash_color.a, 1.0);
}
