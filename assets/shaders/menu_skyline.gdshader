shader_type canvas_item;
// Menu-only backdrop (menu_* namespace): a fully procedural neon night.
// A graded sky, two drifting cloud decks underlit by the city, a hazed moon,
// distant aircraft beacons, and FOUR parallax building layers — far wall, mid,
// near, and sparse foreground spires that break the skyline high into the
// upper frame so the first thing a judge sees is a place, not a void.
//
// Depth is carried by VALUE, not by brightness. The far wall is washed toward
// the sky (atmospheric perspective: light, low contrast, soft edges); every
// nearer layer is darker, more strongly shaded, and only the nearest roofs
// catch a cool rim light. That ordering is what makes the parallax read.
//
// Sky pixels stay partly transparent so the starfield behind keeps showing —
// most at the top of the frame, least at the horizon where the city glow
// washes the stars out. All motion is slow TIME drift and sub-1Hz pulses;
// nothing strobes.

uniform float rect_width = 1280.0; // set from code on ready/resize (px)
uniform float horizon : hint_range(0.0, 1.0) = 0.54; // far-layer roof baseline
uniform float drift_speed = 1.0; // global parallax drift multiplier (px/sec)
uniform float window_glow = 1.0; // lit-window brightness multiplier
uniform vec2 scroll = vec2(0.0, 0.0); // extra parallax offset (tweenable)
uniform vec4 haze_color : source_color = vec4(0.55, 0.36, 0.96, 1.0);
uniform vec4 cool_color : source_color = vec4(0.14, 0.94, 0.86, 1.0);
uniform vec4 warm_color : source_color = vec4(1.0, 0.69, 0.13, 1.0);
uniform vec4 beacon_color : source_color = vec4(1.0, 0.28, 0.34, 1.0);

// --- added in the composition pass; every one has a safe default -------------
uniform float rect_aspect = 0.5625; // viewport height/width, for round dots
uniform vec4 sky_color : source_color = vec4(0.055, 0.072, 0.19, 1.0);
uniform float sky_amount : hint_range(0.0, 2.0) = 1.0; // sky gradient opacity
uniform float cloud_amount : hint_range(0.0, 2.0) = 1.0; // cloud deck coverage
uniform float cloud_speed = 1.0; // cloud drift multiplier
uniform vec2 moon_uv = vec2(0.815, 0.135); // moon centre, UV
uniform float moon_size : hint_range(0.0, 0.3) = 0.042; // radius, width-fraction
uniform vec4 moon_color : source_color = vec4(0.80, 0.93, 1.0, 1.0);
uniform float aircraft_amount : hint_range(0.0, 2.0) = 1.0; // distant plane lights
uniform float spire_amount : hint_range(0.0, 1.0) = 1.0; // foreground tower layer

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smoothed value noise + 3-octave fbm — only ever evaluated in the sky band.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * vnoise(p);
		p *= 2.07;
		amp *= 0.5;
	}
	return v;
}

// Source-over composite onto the running straight-alpha colour/coverage pair.
// Straight (not premultiplied) because COLOR is handed to Godot's normal blend
// as vec4(col, a) — a naive mix() would darken every element drawn over a
// mostly-transparent sky.
void over(inout vec3 col, inout float a, vec3 ec, float ea) {
	float e = clamp(ea, 0.0, 1.0);
	float na = e + a * (1.0 - e);
	if (na <= 0.0001) {
		a = 0.0;
		return;
	}
	col = (ec * e + col * a * (1.0 - e)) / na;
	a = na;
}

// One drifting cloud deck: soft fbm bands, cold on top, washed by the city
// glow underneath. Returns rgb in .xyz and coverage in .w.
vec4 cloud_deck(vec2 uv, float t, float band_y, float band_h, float sc,
		float spd, float thresh, float bright) {
	float band = 1.0 - smoothstep(0.0, band_h, abs(uv.y - band_y));
	if (band <= 0.001) {
		return vec4(0.0);
	}
	vec2 p = vec2(uv.x * sc + t * spd * cloud_speed * 0.004 + scroll.x * 0.0004,
			uv.y * sc * 3.2 + spd * 4.0);
	float n = fbm(p);
	float cov = smoothstep(thresh, thresh + 0.24, n) * band * band;
	// belly-lit: the neon underneath bounces off the underside of the deck
	float lit = clamp((uv.y - band_y + band_h) / (band_h * 2.0), 0.0, 1.0);
	vec3 c = mix(sky_color.rgb * 1.35, haze_color.rgb * 0.50, 0.40 + 0.35 * lit);
	c += cool_color.rgb * 0.05 * lit * lit;
	return vec4(c * bright, cov);
}

// One building layer. Vertical measures are UV fractions, horizontal ones are
// screen pixels (rect_width keeps tower widths constant across resolutions).
// haze_mix washes the layer toward the sky (distance); facade drives how hard
// the tower is shaded top-to-bottom and how crisp its window grid reads; fill
// is the fraction of the column the tower body occupies (1.0 = solid wall,
// low values = slender spires with sky between them).
vec4 layer(vec2 uv, float t, float col_w, float base_line, float h_min, float h_max,
		float gap_chance, float lit_frac, float cell_w, float cell_h,
		float par, float seed_k, vec3 base_col, float glow_mult, float beacons,
		float haze_mix, float facade, float fill) {
	float x = uv.x * rect_width + (t * drift_speed + scroll.x) * par;
	float col = floor(x / col_w);
	float lx = x - col * col_w;
	if (hash(vec2(col, seed_k)) < gap_chance) {
		return vec4(0.0); // gap between towers — the layer behind shows
	}
	float h = mix(h_min, h_max, hash(vec2(col, seed_k + 3.7)));
	float top = base_line - h;
	float mast = step(0.6, hash(vec2(col, seed_k + 8.1)));
	float mast_h = mix(0.015, 0.045, hash(vec2(col, seed_k + 9.3)));
	// The colour distance washes a layer toward. Deliberately DARKER than the
	// sky at the horizon: a far wall that matches the sky stops silhouetting.
	vec3 far_tint = mix(sky_color.rgb, haze_color.rgb, 0.35) * 0.42;
	if (uv.y < top) {
		// thin antenna mast over ~40% of roofs
		float in_mast = mast * step(abs(lx - col_w * 0.5), 1.2) * step(top - mast_h, uv.y);
		if (in_mast > 0.5) {
			return vec4(mix(base_col * 1.6, far_tint, haze_mix), 1.0);
		}
		// slow-pulsing aviation beacon on some mast tips (~0.2Hz — no strobe)
		if (beacons > 0.5 && hash(vec2(col, seed_k + 5.5)) > 0.8) {
			float by = top - mast_h * mast;
			float d = length(vec2(lx - col_w * 0.5, (uv.y - by) * rect_width * rect_aspect));
			if (d < 3.0) {
				float pulse = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 1.3 + col * 2.1));
				return vec4(beacon_color.rgb * (0.8 + pulse), pulse * smoothstep(3.0, 0.5, d));
			}
		}
		return vec4(0.0);
	}
	// Slender layers leave sky between their towers; a wall layer (fill 1.0)
	// keeps the original behaviour exactly.
	float half_w = col_w * 0.5 * fill;
	float ilx = lx - (col_w * 0.5 - half_w);
	float iw = half_w * 2.0;
	if (ilx < 0.0 || ilx > iw) {
		return vec4(0.0);
	}
	// Facade shading (silhouette law): brighter at the roof, sinking into the
	// city floor below, with the light from the top-left as everywhere else.
	float span = max(base_line + 0.30 - top, 0.001);
	float depth = clamp((uv.y - top) / span, 0.0, 1.0);
	float grad = mix(1.0 + 0.52 * facade, 1.0 - 0.46 * facade, depth);
	float side = mix(1.12, 0.84, clamp(ilx / iw, 0.0, 1.0));
	vec3 c = base_col * grad * side;
	// dark seams keep adjacent towers reading as separate silhouettes
	bool seam = ilx < 3.0 || ilx > iw - 3.0;
	if (seam) {
		c = base_col * 0.45 * grad;
	} else {
		// window grid: a few lit at 3AM, gently twinkling well below 1Hz
		float wxf = (ilx - 3.0) / cell_w;
		float wyf = (uv.y - top) / cell_h;
		float wx = floor(wxf);
		float wy = floor(wyf);
		float wh = hash(vec2(col * 31.0 + wx, wy * 7.0 + seed_k));
		float lit = step(1.0 - lit_frac, wh);
		float pane = step(0.18, fract(wxf)) * step(fract(wxf), 0.72)
				* step(0.25, fract(wyf)) * step(fract(wyf), 0.7) * step(0.75, wyf);
		if (lit * pane > 0.5) {
			vec3 wc = mix(cool_color.rgb, warm_color.rgb, step(0.5, hash(vec2(wx + col, wy * 3.1))));
			float tw = 0.8 + 0.2 * sin(t * (0.2 + 0.4 * wh) + wh * 6.28);
			c = wc * window_glow * glow_mult * tw;
		} else if (pane > 0.5) {
			// unlit window: the nearer the tower, the harder its grid reads
			c *= mix(0.74, 0.52, facade);
		}
	}
	// Roofline rim, drawn over seams and panes alike so the edge stays whole.
	// Near layers catch the city's own cyan; far ones only lift their own tone.
	// Distance then kills the rim outright. Without rim_fall the far wall's
	// roofline composites BRIGHTER than the sky it is supposed to melt into and
	// matches the near layer's rim value exactly — the haze builds the ladder
	// and the rim flattens it back out at every roofline, which is the one
	// place the eye actually reads depth.
	vec3 rim_col = mix(base_col * 2.6, cool_color.rgb * 0.34, 0.42 * (1.0 - haze_mix));
	float rim_fall = clamp(1.0 - haze_mix * 1.6, 0.0, 1.0);
	c += rim_col * (1.0 - smoothstep(0.0, 0.006, uv.y - top)) * (0.6 + 0.8 * facade) * rim_fall;
	// atmospheric perspective — distance washes the layer toward the sky
	c = mix(c, far_tint, haze_mix);
	return vec4(c, 1.0);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	vec3 col = vec3(0.0);
	float a = 0.0;

	// ---------------------------------------------------------------- sky ---
	// Coherent branch: everything above the roofline only. The building layers
	// below never pay for the noise.
	if (uv.y < horizon + 0.08) {
		float sky_t = clamp(uv.y / max(horizon, 0.001), 0.0, 1.0);
		col = mix(sky_color.rgb * 0.55, mix(sky_color.rgb, haze_color.rgb, 0.32),
				pow(sky_t, 1.7));
		a = mix(0.16, 0.56, pow(sky_t, 1.9)) * sky_amount;

		// Moon — the anchor for the upper frame, high enough that the spires
		// never eat it. Soft halo, faint maria, a cold terminator on the
		// lower-right so it reads as a sphere and not a sticker.
		if (moon_size > 0.0) {
			vec2 md = vec2(uv.x - moon_uv.x, (uv.y - moon_uv.y) * rect_aspect);
			float d = length(md);
			float halo = pow(clamp(1.0 - d / (moon_size * 7.0), 0.0, 1.0), 2.6);
			over(col, a, mix(moon_color.rgb, haze_color.rgb, 0.45) * 0.5, halo * 0.30);
			float disc = smoothstep(moon_size, moon_size * 0.90, d);
			if (disc > 0.0) {
				float maria = 0.86 + 0.14 * vnoise(md / moon_size * 2.3 + 11.0);
				float term = 0.62 + 0.38 * clamp(1.0 - dot(normalize(md + 0.00001),
						normalize(vec2(0.7, 0.7))) * 0.55, 0.0, 1.0);
				over(col, a, moon_color.rgb * 0.66 * maria * term, disc * 0.94);
			}
		}

		// Two cloud decks, drifting at different rates: the high thin one
		// veils the moon, the low thick one sits on the city glow.
		if (cloud_amount > 0.0) {
			vec4 hi = cloud_deck(uv, t, 0.160, 0.20, 2.6, 0.9, 0.52, 0.90);
			over(col, a, hi.rgb, hi.a * 0.44 * cloud_amount);
			vec4 lo = cloud_deck(uv, t, max(horizon - 0.11, 0.0), 0.15, 4.3, 1.7, 0.46, 1.20);
			over(col, a, lo.rgb, lo.a * 0.58 * cloud_amount);
		}

		// Three aircraft crossing the high sky, blinking at ~0.3Hz. Tiny, dim,
		// and slow — a sign the city is awake, not a light show.
		if (aircraft_amount > 0.0) {
			for (int i = 0; i < 3; i++) {
				float fi = float(i);
				float ax = fract(hash(vec2(fi, 4.2)) + t * (0.0055 + 0.0022 * fi));
				float ay = 0.055 + 0.16 * hash(vec2(fi, 9.1));
				float ad = length(vec2(uv.x - ax, (uv.y - ay) * rect_aspect));
				float blink = 0.18 + 0.82 * pow(0.5 + 0.5 * sin(t * 1.9 + fi * 2.4), 8.0);
				vec3 ac = mix(beacon_color.rgb, moon_color.rgb, hash(vec2(fi, 2.7)));
				over(col, a, ac, smoothstep(0.0055, 0.0006, ad) * blink * 0.55 * aircraft_amount);
			}
		}
	}

	// ------------------------------------------------------- city-glow haze --
	float hz = smoothstep(horizon - 0.16, horizon, uv.y)
			* (1.0 - smoothstep(horizon, horizon + 0.26, uv.y));
	over(col, a, haze_color.rgb * 0.34 + cool_color.rgb * 0.06, hz * 0.42);

	// ------------------------------------------------------------- skyline --
	// far wall (no gaps — nothing but city below the horizon), mid, near, spires
	vec4 L = layer(uv, t, 56.0, horizon, 0.04, 0.13, 0.0, 0.28, 7.0, 0.020,
			0.35, 1.0, vec3(0.075, 0.09, 0.175), 0.50, 0.0, 0.32, 0.25, 1.0);
	if (L.a > 0.0) { col = mix(col, L.rgb, L.a); a = max(a, L.a); }
	L = layer(uv, t, 96.0, horizon + 0.055, 0.06, 0.20, 0.16, 0.20, 11.0, 0.026,
			0.6, 2.0, vec3(0.048, 0.058, 0.115), 0.80, 0.0, 0.16, 0.55, 1.0);
	if (L.a > 0.0) { col = mix(col, L.rgb, L.a); a = max(a, L.a); }
	L = layer(uv, t, 150.0, horizon + 0.13, 0.08, 0.30, 0.22, 0.13, 15.0, 0.034,
			1.0, 3.0, vec3(0.024, 0.03, 0.062), 1.40, 1.0, 0.04, 0.85, 1.0);
	if (L.a > 0.0) { col = mix(col, L.rgb, L.a); a = max(a, L.a); }
	// Foreground spires: slender, sparse, the darkest value in the frame. They
	// break the roofline high into the empty upper third and give the parallax
	// an unambiguous nearest term to read against.
	if (spire_amount > 0.0) {
		L = layer(uv, t, 224.0, horizon + 0.32, 0.40, 0.66, 0.60, 0.10, 13.0, 0.038,
				1.45, 4.0, vec3(0.013, 0.016, 0.038), 1.10, 1.0, 0.0, 1.0, 0.44);
		if (L.a > 0.0) { col = mix(col, L.rgb, L.a * spire_amount); a = max(a, L.a * spire_amount); }
	}
	COLOR = vec4(col, a);
}
