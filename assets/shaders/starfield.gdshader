shader_type canvas_item;
// The void outside the world: layered parallax stars + drifting nebula
// + rare shooting sparks. Bind "scroll" to camera position * 0.05.

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
	float tw = 0.55 + 0.45 * sin(TIME * tw_speed + h * 40.0);
	return smoothstep(0.12, 0.0, d) * tw;
}

void fragment() {
	vec2 uv = UV + scroll * 0.001;
	vec3 col = base_color.rgb;
	// nebula wisps
	float n = noise(uv * 3.0 + scroll * 0.0004 + vec2(TIME * 0.008, 0.0));
	n = pow(n, 2.6);
	col += accent_color.rgb * n * 0.16;
	// three star layers, different parallax
	col += vec3(0.9, 0.95, 1.0) * star_layer(uv + scroll * 0.0016, 60.0 * density, 0.982, 1.7) * 0.9;
	col += vec3(0.75, 0.85, 1.0) * star_layer(uv + scroll * 0.0009, 34.0 * density, 0.986, 1.1) * 0.6;
	col += accent_color.rgb * star_layer(uv + scroll * 0.0005, 18.0 * density, 0.990, 0.7) * 0.45;
	COLOR = vec4(col, 1.0);
}
