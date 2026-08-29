shader_type canvas_item;
// Menu-only backdrop (menu_* namespace): a fully procedural three-layer
// parallax neon skyline — lit windows, roofline rims, antenna masts and
// slow-pulsing rooftop beacons — drifting at a few pixels per second.
// Sky pixels stay transparent so the starfield behind keeps showing.
// All motion is slow TIME drift and sub-1Hz pulses; nothing strobes.

uniform float rect_width = 1280.0; // set from code on ready/resize (px)
uniform float horizon : hint_range(0.0, 1.0) = 0.62; // far-layer roof baseline
uniform float drift_speed = 1.0; // global parallax drift multiplier (px/sec)
uniform float window_glow = 1.0; // lit-window brightness multiplier
uniform vec2 scroll = vec2(0.0, 0.0); // extra parallax offset (tweenable)
uniform vec4 haze_color : source_color = vec4(0.55, 0.36, 0.96, 1.0);
uniform vec4 cool_color : source_color = vec4(0.14, 0.94, 0.86, 1.0);
uniform vec4 warm_color : source_color = vec4(1.0, 0.69, 0.13, 1.0);
uniform vec4 beacon_color : source_color = vec4(1.0, 0.28, 0.34, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// One building layer. Vertical measures are UV fractions, horizontal ones are
// screen pixels (rect_width keeps tower widths constant across resolutions).
vec4 layer(vec2 uv, float t, float col_w, float base_line, float h_min, float h_max,
		float gap_chance, float lit_frac, float cell_w, float cell_h,
		float par, float seed_k, vec3 base_col, float glow_mult, float beacons) {
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
	if (uv.y < top) {
		// thin antenna mast over ~40% of roofs
		float in_mast = mast * step(abs(lx - col_w * 0.5), 1.2) * step(top - mast_h, uv.y);
		if (in_mast > 0.5) {
			return vec4(base_col * 1.4, 1.0);
		}
		// slow-pulsing aviation beacon on some mast tips (~0.2Hz — no strobe)
		if (beacons > 0.5 && hash(vec2(col, seed_k + 5.5)) > 0.8) {
			float by = top - mast_h * mast;
			float d = length(vec2(lx - col_w * 0.5, (uv.y - by) * rect_width * 0.5625));
			if (d < 3.0) {
				float pulse = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 1.3 + col * 2.1));
				return vec4(beacon_color.rgb * (0.8 + pulse), pulse * smoothstep(3.0, 0.5, d));
			}
		}
		return vec4(0.0);
	}
	// dark seams keep adjacent towers reading as separate silhouettes
	if (lx < 3.0 || lx > col_w - 3.0) {
		return vec4(base_col * 0.55, 1.0);
	}
	vec3 c = base_col;
	// roofline rim light (silhouette law: the shape reads without a label)
	c += base_col * 2.0 * (1.0 - smoothstep(0.0, 0.006, uv.y - top));
	// window grid: a few lit at 3AM, gently twinkling well below 1Hz
	float wxf = (lx - 3.0) / cell_w;
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
		c = base_col * 0.7; // unlit window: subtle facade texture
	}
	return vec4(c, 1.0);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	// city-glow haze bleeding over the horizon into the sky
	float hz = smoothstep(horizon - 0.14, horizon, uv.y)
			* (1.0 - smoothstep(horizon, horizon + 0.25, uv.y));
	vec3 col = haze_color.rgb * hz * 0.10;
	float a = hz * 0.30;
	// far wall (no gaps — nothing but city below the horizon), mid, near
	vec4 L = layer(uv, t, 56.0, horizon, 0.04, 0.13, 0.0, 0.30, 7.0, 0.020,
			0.35, 1.0, vec3(0.075, 0.09, 0.175), 0.55, 0.0);
	if (L.a > 0.0) { col = mix(col, L.rgb, L.a); a = max(a, L.a); }
	L = layer(uv, t, 96.0, horizon + 0.055, 0.06, 0.20, 0.16, 0.22, 11.0, 0.026,
			0.6, 2.0, vec3(0.048, 0.058, 0.115), 0.85, 0.0);
	if (L.a > 0.0) { col = mix(col, L.rgb, L.a); a = max(a, L.a); }
	L = layer(uv, t, 150.0, horizon + 0.13, 0.08, 0.28, 0.22, 0.12, 15.0, 0.034,
			1.0, 3.0, vec3(0.024, 0.03, 0.062), 1.5, 1.0);
	if (L.a > 0.0) { col = mix(col, L.rgb, L.a); a = max(a, L.a); }
	COLOR = vec4(col, a);
}
