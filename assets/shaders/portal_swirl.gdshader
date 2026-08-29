shader_type canvas_item;
// Swirling energy vortex. Apply to any square sprite (its texture is
// ignored — the effect is fully procedural, masked to a disc).
//
// Readability contract (VISUAL_BIBLE): a portal must read as SATURATED
// destination energy from across the room. Two rules make that work on the
// near-black floors this game uses:
//   1. chroma is normalised up front, so muted hues (stackoverflow gold,
//      cloud sky) come out as vivid as magenta instead of brown sludge;
//   2. the disc is opaque in the middle and its hot core is a hue-TINTED
//      white, so it crosses the glow threshold without becoming a grey blob.

uniform vec4 hue_color : source_color = vec4(0.55, 0.36, 0.96, 1.0);
uniform float speed = 1.0;
uniform float arms = 3.0;
uniform float core_heat : hint_range(0.0, 2.0) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Full value + boosted chroma, same hue. Near-white inputs degrade gracefully.
vec3 vivid(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	vec3 n = c / max(mx, 0.001);
	float lum = dot(n, vec3(0.299, 0.587, 0.114));
	return clamp(mix(vec3(lum), n, 1.45), vec3(0.0), vec3(1.0));
}

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float a = atan(p.y, p.x);
	float swirl = a + (1.0 - r) * 4.0 - TIME * speed * 2.0;
	float band = 0.5 + 0.5 * sin(swirl * arms + r * 9.0);
	band = pow(band, 1.35);                          // crisper arms, darker gaps
	float rings = 0.5 + 0.5 * sin(r * 14.0 - TIME * speed * 3.0);
	float core = pow(max(1.0 - r, 0.0), 2.2);
	// event horizon: a bright lip just inside the outer edge
	float lip = smoothstep(0.52, 0.86, r) * smoothstep(1.0, 0.86, r);
	float sparkle = step(0.987, hash(floor(UV * 24.0) + floor(TIME * 8.0)));

	vec3 base = vivid(hue_color.rgb);
	vec3 hot = mix(base, vec3(1.0), 0.38);           // tinted white, never pure

	vec3 col = base * (0.26 + 0.74 * band + 0.22 * rings);
	col += base * lip * 0.30;
	col = mix(col, hot * (1.28 * core_heat), core * core);
	col += hot * sparkle * 0.5;
	col *= 1.0 - 0.40 * smoothstep(0.74, 1.0, r);    // limb darkening: a real disc

	// Opaque through the middle so the dark floor behind can never mud it out.
	float alpha = smoothstep(1.0, 0.72, r)
		* clamp(0.60 + 0.40 * band + core, 0.0, 1.0) * hue_color.a;
	COLOR = vec4(col, alpha);
}
