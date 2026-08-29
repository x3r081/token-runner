shader_type canvas_item;
render_mode blend_mix, unshaded;
// Gravitational rim for a portal: a screen-reading annulus that drags the floor
// behind it inward and around, with a chromatic split at the lip. This is the
// thing that makes a portal read as a HOLE rather than a decal — the room
// visibly bends into it.
//
// Ordering contract: a BackBufferCopy must draw immediately before this sprite
// (region_portal.gd parents one at a lower z_index). Everything drawn after the
// copy — world labels at z 400+, props, NPCs — is deliberately NOT in the
// capture, so text near a portal never smears.
//
// Cost is one annulus of screen samples; the mask is computed first and the
// whole thing multiplies out to zero outside the ring.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 hue_color : source_color = vec4(0.55, 0.36, 0.96, 1.0);
uniform float strength : hint_range(0.0, 0.12) = 0.020;
uniform float swirl : hint_range(0.0, 1.0) = 0.55;
uniform float speed = 1.0;
uniform float inner : hint_range(0.05, 0.95) = 0.54;
uniform float glow : hint_range(0.0, 2.0) = 0.45;
uniform float aberration : hint_range(0.0, 4.0) = 1.0;
uniform vec2 screen_aspect = vec2(1.0, 1.77);

vec3 vivid(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	vec3 n = c / max(mx, 0.001);
	float lum = dot(n, vec3(0.299, 0.587, 0.114));
	return clamp(mix(vec3(lum), n, 1.45), vec3(0.0), vec3(1.0));
}

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float mask = smoothstep(inner - 0.14, inner + 0.08, r)
		* (1.0 - smoothstep(0.80, 1.0, r));

	vec2 dir = p / max(length(p), 0.0001);
	vec2 tang = vec2(-dir.y, dir.x);
	// Strongest right at the disc edge, easing off outward: the lens falls away
	// with distance the way a real one does.
	float pull = pow(clamp(1.0 - r, 0.0, 1.0), 1.5);
	float wob = 0.82 + 0.18 * sin(r * 24.0 - TIME * speed * 3.0);
	vec2 off = (-dir * (1.0 - swirl) + tang * swirl)
		* strength * pull * wob * mask * screen_aspect;

	vec2 ca = off * 0.18 * aberration;
	vec2 uv = SCREEN_UV + off;
	vec3 col = vec3(
		textureLod(screen_tex, uv + ca, 0.0).r,
		textureLod(screen_tex, uv, 0.0).g,
		textureLod(screen_tex, uv - ca, 0.0).b);

	// A thin hue-tinted lip so the ring itself is visible against a dark floor.
	// d*d rather than pow(d, 2.0): d goes negative inside the ring, and pow()
	// of a negative base is undefined in GLSL.
	// Round 4: the lip is roughly half its old width — a crisp line instead of
	// a band — which is the actual fix for the flat white collar seen around
	// the wildlands portal in the QA frames. The luma metering below is a
	// GUARD, not the collar fix: the capture this shader reads is taken at
	// z -4 (region_portal.gd's PortalLensCopy), so it holds only the floor
	// layers — the additive halo (z -2) and the disc draw AFTER the copy and
	// are invisible to it. Over dark floors head clamps to 1.0 and the term is
	// a no-op; it only tapers the lip over genuinely bright captured backdrops
	// (cloud_district's lighter floors, baked light pools).
	float drim = (r - inner - 0.04) / 0.055;
	float rim = exp(-drim * drim);
	vec3 rimc = vivid(hue_color.rgb) * rim * glow * mask;
	float head = clamp(1.30 - dot(col, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
	col += rimc * head;

	COLOR = vec4(col, mask);
}
