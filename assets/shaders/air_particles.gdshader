shader_type canvas_item;
render_mode blend_add, unshaded;
// The air in a room: three parallax layers of drifting motes plus an optional
// drifting haze bank. One shader covers every region's weather —
//
//   dust / ash / spores / data-motes -> streak 0.0, fall_speed +/- small
//   rising embers or gold dust       -> negative fall_speed
//   rain / sprinkler drip            -> streak 1.0, large fall_speed
//   cold clean haze                  -> fog_amount > 0, low mote density
//
// Additive only, so it can never haze the frame down; `fog` is a LIFT, which is
// what "cold clean haze" actually looks like on a dark scene. Godot's blend_add
// uses COLOR.rgb * COLOR.a, so the contribution is written into rgb with alpha
// pinned at 1.0.

uniform vec4 mote_color : source_color = vec4(0.80, 0.90, 1.00, 1.0);
uniform vec4 fog_color : source_color = vec4(0.35, 0.55, 0.80, 1.0);
uniform float fog_amount : hint_range(0.0, 0.6) = 0.0;
uniform float density : hint_range(2.0, 60.0) = 16.0;
uniform float fall_speed = 0.04;
uniform float drift : hint_range(0.0, 0.3) = 0.02;
uniform float streak : hint_range(0.0, 1.0) = 0.0;
uniform float mote_size : hint_range(0.02, 0.9) = 0.22;
uniform float twinkle : hint_range(0.0, 1.0) = 0.7;
uniform float brightness : hint_range(0.0, 2.0) = 0.5;
uniform float sparsity : hint_range(0.0, 0.99) = 0.74;
uniform vec2 aspect = vec2(1.33, 1.0);
uniform float seed = 0.0;

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

// One grid of jittered motes. Cells below `sparsity` are empty, so raising
// density adds detail without adding clutter.
float mote_layer(vec2 uv, float scale, float t, float ph) {
	vec2 g = uv * scale;
	vec2 id = floor(g);
	float h = hash(id + vec2(ph, ph * 0.61));
	if (h < sparsity) {
		return 0.0;
	}
	vec2 f = fract(g);
	vec2 c = vec2(hash(id * 1.7 + ph), hash(id * 3.1 + ph));
	vec2 d = f - c;
	d.y *= mix(1.0, 0.14, streak);                   // stretch into a rain streak
	float dd = length(d) * 2.0;
	float tw = mix(1.0, 0.45 + 0.55 * sin(t * 2.7 + h * 41.0), twinkle);
	// Round 5: same energy, redistributed. The old single smoothstep gave every
	// mote a broad soft disc, and a screenful of broad soft discs is haze with
	// extra steps. A dim halo plus a small hot core reads as a PARTICLE — it
	// catches the light, it does not fog the room.
	float halo = 1.0 - smoothstep(0.0, mote_size, dd);
	float core = halo * halo;
	return (halo * 0.45 + core * core * 0.80) * max(tw, 0.0);
}

void fragment() {
	vec2 base = UV * aspect;
	float t = TIME + seed;
	float sway = sin(t * 0.37 + UV.y * 5.0) * drift;

	// Three depths: nearer layers are denser, faster and dimmer, which is what
	// sells parallax on a flat quad.
	float m = mote_layer(base + vec2(sway, -t * fall_speed), density, t, seed);
	m += 0.72 * mote_layer(base + vec2(sway * 1.6, -t * fall_speed * 1.7), density * 1.7, t, seed + 11.3);
	m += 0.46 * mote_layer(base + vec2(sway * 0.6, -t * fall_speed * 2.6), density * 2.6, t, seed + 27.9);

	float fog = 0.0;
	if (fog_amount > 0.0005) {
		float banks = vnoise(vec2(base.x * 2.6 + t * 0.030, base.y * 4.2 - t * 0.012));
		banks += 0.45 * vnoise(vec2(base.x * 6.1 - t * 0.048, base.y * 9.3 + t * 0.021));
		banks = pow(clamp(banks / 1.45, 0.0, 1.0), 2.6);
		// Round 5: the old base term was a FLAT 0.40 * fog_amount added to every
		// pixel of the region — a coloured lift over the whole frame, which is
		// exactly the milk the QA frames complained about in gpu_mines and
		// token_vault. The base is now a trace and the banks carry the effect,
		// so haze happens in PLACES: it drifts past, it does not sit on the lens.
		fog = fog_amount * (0.08 + 1.30 * banks);
	}

	vec3 add = mote_color.rgb * clamp(m, 0.0, 2.0) * brightness * mote_color.a
		+ fog_color.rgb * fog * fog_color.a;
	COLOR = vec4(add, 1.0);
}
