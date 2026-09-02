shader_type canvas_item;
// The void outside the world. VISUAL_BIBLE_V2: the starfield is the quietest
// surface in the game — it is the thing the room is cut out of, not a feature.
// Bind "scroll" to camera position * 0.05.
//
// Round 6: star density down to ~35% of round 5 (the cell thresholds moved
// from 0.982/0.986/0.990 to 0.9935/0.9945/0.9962), the accent-coloured layer
// removed entirely so the void is never a second region hue, the nebula wash
// cut from 0.16 to 0.05, and the twinkle slowed to the point where a still
// frame and a moving one look the same. Two star layers, both near-white.

uniform vec4 base_color : source_color = vec4(0.02, 0.024, 0.055, 1.0);
uniform vec4 accent_color : source_color = vec4(0.35, 0.5, 0.95, 1.0);
uniform vec2 scroll = vec2(0.0, 0.0);
uniform float density = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
			mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float star_layer(vec2 uv, float scale, float thresh, float tw_speed) {
	vec2 g = uv * scale;
	vec2 id = floor(g);
	float h = hash(id);
	if (h < thresh) { return 0.0; }
	vec2 center = fract(g) - 0.5;
	float d = length(center - (vec2(hash(id * 1.3), hash(id * 2.1)) - 0.5) * 0.6);
	float tw = 0.78 + 0.22 * sin(TIME * tw_speed + h * 40.0);
	return smoothstep(0.10, 0.0, d) * tw;
}

void fragment() {
	vec2 uv = UV + scroll * 0.001;
	vec3 col = base_color.rgb;
	// A trace of nebula so the void is not a flat fill. 5% is the ceiling: any
	// more and the region's accent is painted across the whole background.
	float n = noise(uv * 3.0 + scroll * 0.0004);
	n = pow(n, 3.2);
	col += accent_color.rgb * n * 0.05;
	// Two parallax layers, both near-white. Stars are not coloured here — the
	// three saturated hues on screen belong to the room, not to the backdrop.
	col += vec3(0.86, 0.90, 1.0) * star_layer(uv + scroll * 0.0016, 60.0 * density, 0.9935, 0.9) * 0.62;
	col += vec3(0.72, 0.78, 0.92) * star_layer(uv + scroll * 0.0009, 34.0 * density, 0.9945, 0.6) * 0.40;
	COLOR = vec4(col, 1.0);
}
