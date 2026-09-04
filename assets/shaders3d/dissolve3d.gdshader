shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
// 3D death dissolve: the model burns away through a solid noise field with a
// glowing burn edge. The 2D twin (assets/shaders/dissolve.gdshader) cuts a
// screen-space pixel grid out of a sprite; in 3D the cut has to live in the
// MODEL, or the burn slides across the mesh as the camera moves.
//
// Contract with Fx3D.dissolve():
//   * every uniform is SEEDED from GDScript before anything is tweened —
//     an unset uniform does not exist on the material (HANDOVER gotcha 2);
//   * `albedo_tex`/`albedo_color` are copied off the model's own
//     StandardMaterial3D, so a dissolving Kenney character keeps its colormap
//     right up to the moment it stops existing;
//   * `progress` sweeps 0 -> 1. Everything below the cut is discarded, the
//     `edge_width` band above it is the burn line.
//
// Never writes ALPHA, so Godot keeps this material in the OPAQUE pass: the
// corpse sorts and shadows correctly while it comes apart, and `discard` does
// the transparency for free.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 1.0 when the source material painted from vertex colours (glTF sets that
// whenever the mesh carries COLOR_0). A mesh without colours reads COLOR as
// white, so this only ever multiplies in what the surface already showed.
uniform float use_vertex_color : hint_range(0.0, 1.0) = 0.0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.55, 0.2, 1.0);
// VISUAL_BIBLE_V2 LAW 3/7: a dying enemy is a dark silhouette coming apart, and
// the burn line is its ONE bright tell — a rim on the cut, not a light source.
// v1's 0.16 band at emission 5.0 made a corpse the brightest object in the
// region for six tenths of a second, in a frame that is supposed to be night.
// Narrower and far dimmer: the burn still reads as fire climbing a body, and
// the body still reads as a body while it burns.
uniform float edge_width : hint_range(0.005, 0.5) = 0.10;
uniform float noise_scale = 9.0;
// 1.15, not 1.6: Fx3D seeds `edge_color` at a 0.85 ceiling, and 0.85 * 1.15 =
// 0.98 at the cut, so the burn line sits UNDER the bloom threshold for its
// whole life. At 1.6 it peaked at 1.36 and a dying enemy bloomed — and a corpse
// is none of LAW 3's five bright things. EMISSION_MAX is a ceiling, not a
// suggestion: 3.0 was permitting three times the budget.
uniform float emission_energy : hint_range(0.0, 1.2) = 1.15;
// Applied in code — hint_range constrains the inspector, not a script.
const float EMISSION_MAX = 1.2;
// How much of the cut order is "bottom of the model burns first" rather than
// pure noise. Pure noise reads as static; pure height reads as a wipe. The
// mix is what makes it read as fire climbing a body.
uniform float bottom_up : hint_range(0.0, 1.0) = 0.45;
// Model-space vertical extent of THIS mesh (Fx3D reads it off the AABB), so
// the height term is normalised per mesh instead of assuming 1 unit.
uniform float base_y = 0.0;
uniform float height = 1.0;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.9;

varying vec3 v_local;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Trilinear value noise. Eight hashes per fragment is cheap next to the burn
// only ever running on one dying model at a time.
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float h = clamp((v_local.y - base_y) / max(height, 0.001), 0.0, 1.0);
	float n = vnoise(v_local * noise_scale);
	n = mix(n, n * 0.45 + 0.55 * h, bottom_up);

	// Push the cut past 1.0 by edge_width so the LAST fragment burns too;
	// without the bias the top of the model pops out instead of burning.
	float cut = progress * (1.0 + edge_width) - edge_width;
	if (n < cut) {
		discard;
	}

	vec4 tex = texture(albedo_tex, UV) * albedo_color;
	tex.rgb *= mix(vec3(1.0), COLOR.rgb, use_vertex_color);
	ALBEDO = tex.rgb;
	ROUGHNESS = surface_roughness;
	METALLIC = 0.0;

	if (n < cut + edge_width) {
		// Hottest right at the cut, cooling into the surviving surface.
		float k = 1.0 - clamp((n - cut) / max(edge_width, 0.001), 0.0, 1.0);
		// k*k, not k: the heat is concentrated in the last sliver at the cut
		// instead of washing back across the whole band, so the burn reads as a
		// LINE. A linear falloff over a 0.16 band was a glowing gradient down
		// the model, which is the "glow pass" LAW 7 forbids.
		ALBEDO = mix(tex.rgb, edge_color.rgb, k);
		EMISSION = edge_color.rgb * min(emission_energy, EMISSION_MAX) * k * k;
	}
}
