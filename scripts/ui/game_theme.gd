extends RefCounted
class_name GameTheme
## The one style source for every screen — VISUAL_BIBLE_V2 LAW 8.
##
## ROUND 6 IS A SUBTRACTION. Every helper below kept its name and its signature;
## what changed is what they PRODUCE. A caller that asked for "glass with an
## accent halo" now gets a flat 96% panel with a hairline border, and a caller
## that asked for a sheen or a glow layer gets nothing at all. That is the whole
## design of this file: the fix for "every screen glows" is not to edit twenty
## screens, it is to make the glow helpers stop glowing. Delete a call site if
## you like; you do not have to, and nothing breaks if you don't.
##
## THE MODAL RULE (LAW 8), which `panel_box`, `glass_box`, `dream_app_panel`
## and `ship_button` all now obey:
##   BASE at 96%, 1px LINE border, corner radius 0–2,
##   shadow_size 0, no glow, no sheen, no gradient.
##   One ACCENT per screen (title + primary action). Body in TEXT.
##
## THE TEXT RULE (LAW 1), as amended by looking at the frames:
##
##   * HINTED, always. Round 6 switched the hinter off along with antialiasing,
##     on the theory that "aliased" meant "no font machinery at all". Hinting is
##     not smoothing — it is what pulls stems and crossbars onto whole pixel rows
##     — and without it the UI printed "compiled" as "complled". See `ui_font()`.
##   * Nothing below 16. SMALL was 14 and 14 does not survive this face.
##   * BODY (18) and HEADING (26) are ALIASED, via `ui_font()`, which is the
##     theme's default font. That is where the project's pixel-text character
##     lives and those sizes have the rows to carry it.
##   * SMALL (16) is ALIASED TOO, and by the same object: `small_font()` returns
##     `ui_font()`. It spent one round returning a separate antialiased face, to
##     rescue small text that the autohinter — added in the same round — had
##     already rescued. Two rasterisations of one face is two typographic
##     systems on one screen; see `small_font()`.
##
## ONE FONT, three sizes — SMALL 16 / BODY 18 / HEADING 26 — and nothing else.

# ---------------------------------------------------------------- palette ----
# LAW 2. Three hues per scene; everything else desaturates toward grey.
const VOID := Color("#05060E")
const BASE := Color("#0B0E1C")
const SURFACE := Color("#131A2E")
const RAISED := Color("#1C2440")
const LINE := Color("#2A3558")
const TEXT_DIM := Color("#7C8BB0")
const TEXT := Color("#D8DEEA")
const WHITE_HOT := Color("#F4F9FF")
const CYAN := Color("#24F0DC")
const CYAN_HOT := Color("#7DFFF0")
const MAGENTA := Color("#FF2D95")
const VIOLET := Color("#8B5CF6")
const BLUE := Color("#4D7CFF")
const ACID := Color("#A8FF3E")
const AMBER := Color("#FFB74A")
const RED := Color("#FF4757")
const GOLD := Color("#FFD34D")

## LAW 2's per-region ACCENT column, in one place so the HUD, the waypoint and
## the map cannot disagree about what colour a region is.
const REGION_ACCENT := {
	"localhost": Color("#24F0DC"),
	"dependency_district": Color("#A8FF3E"),
	"stackoverflow_ruins": Color("#E8C46B"),
	"api_bazaar": Color("#FF2D95"),
	"cloud_district": Color("#6BC7FF"),
	"open_source_wildlands": Color("#58E07C"),
	"corporate_enterprise": Color("#4D7CFF"),
	"gpu_mines": Color("#FF6B2D"),
	"production": Color("#FF4757"),
	"token_vault": Color("#FFD34D"),
}

static func region_accent(region_id: String) -> Color:
	return REGION_ACCENT.get(region_id, CYAN)

# ------------------------------------------------------------- type scale ----
## LAW 1: three sizes, no others. FONT_* aliases exist because "SMALL" alone
## reads ambiguously at a distant call site.
##
## SMALL was 14 and 14 does not survive this font. At 14px with hinting on, the
## dot of an `i` sits one pixel off the stem and the renderer has to choose
## between them; it chose the stem, and every `i` in the build became an `l`
## ("compiled on hope" printed as "complled"). 16 is the smallest size at which
## the dot, the counter of an `e` and the crossbar of a `t` each get their own
## pixel row. It is two pixels of vertical rhythm against a whole tier of text
## the player can actually read.
const SMALL := 16
const BODY := 18
const HEADING := 26
const FONT_SMALL := SMALL
const FONT_BODY := BODY
const FONT_HEADING := HEADING

# Animation timing (LAW 9: motion is small). TRANS_CUBIC everywhere.
const T_MICRO := 0.12
const T_STD := 0.25
const T_DRAMA := 0.6

const SHEEN_SHADER := "res://assets/shaders/ui_sheen.gdshader"
const STARFIELD_SHADER := "res://assets/shaders/starfield.gdshader"

# Shared resource caches — one instance per shader/params/texture/font combo.
static var _mat_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}
static var _font_cache: Dictionary = {}
static var _additive_mat: CanvasItemMaterial = null

# ------------------------------------------------------------ core colors ----
## Emissive "hot" companion of an accent.
##
## Round 6 pulls this back hard: it used to lerp 55% toward WHITE_HOT, which is
## how a palette of ten colours became a palette of twenty near-whites. At 0.18
## it is still a step up in value — enough for a hover state or a lit edge — and
## still recognisably the accent it came from.
static func hot_of(accent: Color) -> Color:
	return accent.lerp(WHITE_HOT, 0.18)

static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

# --------------------------------------------------------------- materials ----
## Shared additive material. Still here for the two transient flashes that earn
## it (damage, a spend); it is not for decoration.
static func additive_material() -> CanvasItemMaterial:
	if _additive_mat == null:
		_additive_mat = CanvasItemMaterial.new()
		_additive_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive_mat

## Cached ShaderMaterial (identical params share one instance).
static func shader_material(path: String, params: Dictionary) -> ShaderMaterial:
	if not ResourceLoader.exists(path):
		return null
	var key := path
	for k in params:
		key += "|%s=%s" % [k, params[k]]
	if not _mat_cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = load(path)
		for k in params:
			m.set_shader_parameter(k, params[k])
		_mat_cache[key] = m
	return _mat_cache[key]

# ---------------------------------------------------------------- textures ----
## 2x2 fully transparent texture.
static func clear_texture() -> ImageTexture:
	if not _tex_cache.has("clear"):
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_tex_cache["clear"] = ImageTexture.create_from_image(img)
	return _tex_cache["clear"]

## Bar fill. Flat, two tones — the accent and one darker seat row.
##
## This used to bake a horizontal accent->hot ramp AND a vertical shade AND a
## WHITE_HOT top edge into every bar in the game, which is four values and a
## gradient on a strip that is four pixels tall. A bar reports one number; it
## gets one colour.
static func bar_gradient_texture(accent: Color, hot: Color) -> ImageTexture:
	var key := "bar:%s:%s" % [accent.to_html(), hot.to_html()]
	if not _tex_cache.has(key):
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(accent.lerp(hot, 0.12))
		var seat := accent.lerp(VOID, 0.45)
		for x in 4:
			img.set_pixel(x, 3, seat)
		_tex_cache[key] = ImageTexture.create_from_image(img)
	return _tex_cache[key]

## Radial vignette. LAW 5 caps the world vignette at 0.14 with a wide plateau,
## so the ramp starts late and stays shallow: the edge tint the caller asks for
## is reached only in the last few percent of the radius.
static func vignette_texture(edge: Color) -> GradientTexture2D:
	var key := "vig:%s" % edge.to_html()
	if not _tex_cache.has(key):
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.72, 1.0])
		g.colors = PackedColorArray([with_alpha(edge, 0.0), with_alpha(edge, 0.10), edge])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, -0.1)
		t.width = 512
		t.height = 512
		_tex_cache[key] = t
	return _tex_cache[key]

# -------------------------------------------------------------------- fonts ----
## The project font, aliased AND hinted (LAW 1, corrected by the frames).
##
## Smooth vector text laid over 2x pixel art is the loudest "generated" signal a
## frame can carry, so antialiasing stays off and subpixel positioning stays off:
## every glyph lands on an integer pixel and every pixel it lights is fully on.
##
## HINTING is the part round 6 got wrong. It switched the hinter off along with
## everything else, on the theory that "aliased" meant "no font machinery at
## all" — but hinting is not smoothing. It is the instruction set that pulls a
## stem, a crossbar and a dot onto whole pixel rows BEFORE the glyph is
## rasterised. With it off, an outline lands wherever the metrics put it and the
## 1-bit rasteriser rounds; at 14-16px that rounding merges the dot of an `i`
## into its stem, closes the eye of an `e`, and eats the crossbar of a `t`. The
## QA menu frame printed "compiled on hope" as "complled on hope" and "this
## portal" as "thls portal". That is not pixel purity, that is a broken font.
##
## Classic aliased UI text — the look this project is actually after — was always
## hinted; that is precisely how it stayed legible at 8 and 10 pixels with one
## bit per pixel. So: antialiasing NONE + subpixel DISABLED + HINTING_NORMAL.
## Crisp, on-grid, and readable, which the previous combination was not.
##
## `FontFile` carries all three switches, so the default font is duplicated and
## configured at the source; a `SystemFont` or an already-derived font has no
## such switches and is wrapped in a FontVariation so the rest of the theme still
## has one font object to hang sizes off.
static func ui_font() -> Font:
	if _font_cache.has("ui"):
		return _font_cache["ui"]
	var base: Font = ThemeDB.fallback_font
	var out: Font = null
	if base is FontFile:
		var f: FontFile = (base as FontFile).duplicate()
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.hinting = TextServer.HINTING_NORMAL
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		f.multichannel_signed_distance_field = false
		# The bundled face is a subset with its TrueType hinting instructions
		# stripped, so HINTING_NORMAL alone had nothing to execute and changed
		# nothing. The autohinter derives the stems and crossbars from the outline
		# instead. With it off, "Before" rasterised as "Bcforc" at 16px: the
		# crossbar of every `e` fell between two pixel rows and was dropped.
		f.force_autohinter = true
		out = f
	else:
		var fv := FontVariation.new()
		fv.base_font = base
		out = fv
	_font_cache["ui"] = out
	return out

## The SMALL tier's font. THERE IS ONLY ONE FONT: this returns `ui_font()`.
##
## It briefly returned a second, ANTI-ALIASED rasterisation of the same face,
## as a concession to legibility: the UI renders through a `canvas_items`
## stretch, so a 16px glyph lands at about 13.7px in a windowed 1920x928 frame,
## and one-bit rasterisation at that size was dropping a horizontal feature per
## word — "index" as "indcx", "self" as "sclf", every one of them an `e` whose
## crossbar fell between two pixel rows.
##
## That was the WRONG FIX for the right observation, and the same round shipped
## the right one four lines up: `force_autohinter`. The dropped crossbars were
## an unhinted outline being rounded, not a limit of 1-bit rasterisation, and
## the autohinter pulls the crossbar onto a row BEFORE the glyph is drawn. The
## captured frames settle it — the HUD's 16px legend prints "[E] interact · [T]
## model · [H] help" aliased and perfectly clean in all ten region frames, at
## the identical size and content scale at which the menu's antialiased tip line
## measured 89 grey levels against the title's 4.
##
## So the concession is withdrawn. LAW 1: text is aliased, smooth text on pixel
## art is the loudest "generated" tell a frame can carry, and a project with two
## typographic systems on one screen has neither. The function stays — a dozen
## call sites name it, and `small_text()` is still the one call that sets a
## control's font AND size together.
static func small_font() -> Font:
	return ui_font()

## Set a control to the SMALL tier — the size, and the one font, together.
##
## Now that `small_font()` IS `ui_font()`, this is equivalent to a plain size
## override on any control that inherits the theme; it stays because it also
## covers the controls that inherit no theme at all (a bare Label parented to a
## CanvasLayer), and because one call is harder to get half-right than two.
static func small_text(c: Control) -> void:
	if c == null:
		return
	c.add_theme_font_override("font", small_font())
	c.add_theme_font_size_override("font_size", SMALL)

## Letter-spaced variation of the aliased UI font, for headings.
static func spaced_font(spacing: int = 3) -> FontVariation:
	var key := "sp:%d" % spacing
	if not _font_cache.has(key):
		var fv := FontVariation.new()
		fv.base_font = ui_font()
		fv.set_spacing(TextServer.SPACING_GLYPH, spacing)
		_font_cache[key] = fv
	return _font_cache[key]

# ------------------------------------------------------------- styleboxes ----
## THE panel. BASE 96%, 1px LINE hairline, radius 2, no shadow, no glow.
## `accent` is accepted and ignored: a panel does not carry a colour, the one
## title line inside it does.
static func panel_box(accent: Color = CYAN, margin: float = 16.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = with_alpha(BASE, 0.96)
	s.border_color = with_alpha(LINE, 0.9)
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.set_content_margin_all(margin)
	s.shadow_size = 0
	# Referenced so the signature stays honest about taking a colour it no
	# longer paints with.
	s.shadow_color = with_alpha(accent, 0.0)
	return s

## Same rule, tighter margins. There is no "glass" any more — one panel style is
## the point of LAW 8 — so this is `panel_box` with a different default margin,
## kept because a dozen call sites name it.
static func glass_box(accent: Color = CYAN, margin: float = 10.0) -> StyleBoxFlat:
	return panel_box(accent, margin)

## Invisible stylebox (turns a PanelContainer into a pure layout node).
static func empty_box() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()

## Was: a tinted, bordered, rounded chip behind speaker names and key hints.
## Now: padding. The chips were half the "boxes around boxes" count in the QA
## frames, and every one of them wrapped text that reads perfectly well on its
## own. Kept as a function so nothing has to stop calling it.
static func chip_box(accent: Color = CYAN) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = with_alpha(accent, 0.0)
	s.set_border_width_all(0)
	s.set_corner_radius_all(0)
	s.content_margin_left = 0.0
	s.content_margin_right = 10.0
	s.content_margin_top = 0.0
	s.content_margin_bottom = 0.0
	return s

## Button states: a hairline box that fills faintly on hover and press. No
## shadow, no halo, no scale.
static func button_boxes(accent: Color = CYAN) -> Dictionary:
	var normal := StyleBoxFlat.new()
	normal.bg_color = with_alpha(VOID, 0.0)
	normal.border_color = with_alpha(LINE, 0.9)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 16.0
	normal.content_margin_right = 16.0
	normal.content_margin_top = 9.0
	normal.content_margin_bottom = 9.0
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = with_alpha(accent, 0.07)
	hover.border_color = with_alpha(accent, 0.85)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = with_alpha(accent, 0.14)
	pressed.border_color = accent
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = with_alpha(accent, 0.8)
	focus.set_border_width_all(1)
	focus.set_corner_radius_all(2)
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.border_color = with_alpha(LINE, 0.45)
	return {"normal": normal, "hover": hover, "pressed": pressed, "focus": focus, "disabled": disabled}

## Bar background: a dark slot. No border — LAW 8's bars have none.
static func bar_bg_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = with_alpha(VOID, 0.72)
	s.set_border_width_all(0)
	s.set_corner_radius_all(0)
	return s

## Bar fill: flat accent.
static func bar_fill_box(accent: Color, hot: Color = Color.TRANSPARENT) -> StyleBoxTexture:
	if hot.a == 0.0:
		hot = hot_of(accent)
	var s := StyleBoxTexture.new()
	s.texture = bar_gradient_texture(accent, hot)
	return s

# ----------------------------------------------------------- apply helpers ----
## The near-black text sits against.
const OUTLINE_COL := Color(0.02, 0.024, 0.055, 0.92)

## Readability floor for text over the world — now a 1px DROP SHADOW, not a
## 3–5px outline (LAW 4's label style: "plain aliased text, 1px #000000@80%
## drop shadow offset (1,1). No plate.").
##
## A fat outline is a black halo baked around every glyph; at the sizes this
## project uses it fused the counters into blobs and was doing the job a plate
## should never have needed doing. A one-pixel shadow separates text from any
## floor and leaves the letterform alone. `size` is accepted for compatibility
## and deliberately does not scale the shadow: one pixel, everywhere.
static func outline_text(c: Control, size: int = 3, col: Color = OUTLINE_COL) -> void:
	if c == null:
		return
	c.add_theme_constant_override("outline_size", 0)
	c.add_theme_color_override("font_outline_color", with_alpha(col, 0.0))
	c.add_theme_color_override("font_shadow_color", with_alpha(col, 0.8 if size > 0 else 0.0))
	c.add_theme_constant_override("shadow_offset_x", 1)
	c.add_theme_constant_override("shadow_offset_y", 1)
	c.add_theme_constant_override("shadow_outline_size", 0)

## Tier tokens for hierarchy (LAW 3: five things may be bright).
const TIER_LOUD := 1.0
const TIER_MID := 0.85
const TIER_QUIET := 0.6

static func tier(c: Control, level: float) -> void:
	if c == null:
		return
	c.modulate = Color(1, 1, 1, level)

## One-shot additive flash over a control. The one additive effect that stayed:
## it is an EVENT (you were hit, you spent), it lasts a third of a second, and
## it is the difference between reading a number and feeling it.
static func flash_over(host: Control, col: Color, strength: float = 0.35,
		dur: float = 0.30) -> void:
	if host == null or not host.is_inside_tree():
		return
	var fx := host.get_node_or_null("_ThemeFlash") as ColorRect
	if fx == null:
		fx = ColorRect.new()
		fx.name = "_ThemeFlash"
		fx.material = additive_material()
		fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(fx)
		fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.color = with_alpha(col, strength)
	var old: Variant = fx.get_meta("_tw") if fx.has_meta("_tw") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var t := fx.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(fx, "color:a", 0.0, dur)
	fx.set_meta("_tw", t)

## Scale punch. Still here, still pause-proof — but do not put it on TEXT:
## scaling an aliased glyph off the pixel grid is exactly the smear LAW 1 is
## about. Reserve it for boxes.
static func punch(node: Control, amount: float = 1.08, dur: float = 0.22) -> void:
	if node == null or not node.is_inside_tree():
		return
	node.pivot_offset = node.size * 0.5
	var old: Variant = node.get_meta("_punch_tw") if node.has_meta("_punch_tw") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	node.scale = Vector2.ONE * amount
	var t := node.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(node, "scale", Vector2.ONE, dur)
	node.set_meta("_punch_tw", t)

## Full button treatment: hairline states, aliased label, and no motion.
static func style_button(btn: Button, accent: Color = CYAN, font_size: int = BODY) -> void:
	var boxes := button_boxes(accent)
	btn.add_theme_stylebox_override("normal", boxes.normal)
	btn.add_theme_stylebox_override("hover", boxes.hover)
	btn.add_theme_stylebox_override("pressed", boxes.pressed)
	btn.add_theme_stylebox_override("focus", boxes.focus)
	btn.add_theme_stylebox_override("disabled", boxes.disabled)
	# One font at every size — the tier only chooses how big it is drawn.
	btn.add_theme_font_override("font", ui_font())
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", hot_of(accent))
	btn.add_theme_color_override("font_pressed_color", WHITE_HOT)
	btn.add_theme_color_override("font_focus_color", hot_of(accent))
	btn.add_theme_color_override("font_disabled_color", with_alpha(TEXT_DIM, 0.5))
	btn.add_theme_font_size_override("font_size", font_size)

## Hover scale — REMOVED, and kept as a no-op so no screen has to stop asking.
## A 1.02 scale on a button resamples its aliased text every frame of the tween;
## the hover fill in `button_boxes` says the same thing without touching a glyph.
static func attach_hover_motion(ctrl: Control, amount: float = 1.02) -> void:
	if ctrl == null or amount <= 0.0:
		return
	ctrl.set_meta("_hover_motion", true)

static func _hover_scale(ctrl: Control, target: Vector2) -> void:
	if not is_instance_valid(ctrl) or not ctrl.is_inside_tree():
		return
	ctrl.scale = target

## Progress bar: dark slot, flat accent fill.
static func style_bar(bar: ProgressBar, accent: Color, hot: Color = Color.TRANSPARENT) -> void:
	bar.add_theme_stylebox_override("background", bar_bg_box())
	bar.add_theme_stylebox_override("fill", bar_fill_box(accent, hot))

## Accent heading, aliased, at the one heading size.
static func style_heading(l: Label, accent: Color = CYAN, font_size: int = -1) -> void:
	l.add_theme_color_override("font_color", accent)
	l.add_theme_font_override("font", spaced_font(2))
	l.add_theme_font_size_override("font_size", font_size if font_size > 0 else HEADING)
	outline_text(l)

## Was: a duplicated overbright copy of a label, additive, behind the original,
## so HDR bloom made every title in the game a light source. LAW 3 allows five
## bright things per frame and a menu title is not one of them.
##
## The layer is still created and still returned — `pulse()` is tweened on it by
## five screens — it simply never draws. Nothing to un-wire, nothing to break.
static func add_glow_layer(label: Label, strength: float = 2.2) -> Label:
	var glow := label.duplicate() as Label
	glow.name = "GlowLayer"
	glow.visible = false
	glow.modulate = Color(1, 1, 1, 0.0)
	glow.show_behind_parent = true
	label.add_child(glow)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# `strength` is dead by design; referenced so the signature does not lie
	# about being read.
	glow.set_meta("_requested_strength", strength)
	return glow

## Breathing pulse. Harmless on the (invisible) glow layers that call it.
static func pulse(node: CanvasItem, lo: float = 1.5, hi: float = 2.4, period: float = 2.4) -> void:
	if node == null or not node.is_inside_tree():
		return
	var t := node.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(node, "modulate", Color(lo, lo, lo, node.modulate.a), period * 0.5)
	t.tween_property(node, "modulate", Color(hi, hi, hi, node.modulate.a), period * 0.5)

## Moving diagonal sheen — REMOVED. It was a shader crawling over six panels at
## once, and it is the reason the QA frames read as "surfaces" rather than as
## information. No-op, so no screen has to stop asking for it.
static func add_sheen(host: Control, color: Color = Color(1, 1, 1, 0.05), period: float = 7.0) -> void:
	if host == null or period <= 0.0 or color.a < 0.0:
		return

## Full-bleed vignette layer. LAW 5: wide plateau, never dark.
static func make_vignette(edge: Color) -> TextureRect:
	var tr := TextureRect.new()
	tr.name = "Vignette"
	tr.texture = vignette_texture(edge)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return tr

# ------------------------------------------------------------ micro-motion ----
## Panel entrance: a fade, and only a fade. The 0.96 scale-up it used to do
## resampled every glyph on the panel for a quarter of a second.
static func open_panel(ctrl: Control) -> void:
	if ctrl == null:
		return
	ctrl.scale = Vector2.ONE
	ctrl.modulate.a = 0.0
	var t := ctrl.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(ctrl, "modulate:a", 1.0, T_STD)

## Rows fade in one after another. Modulate only — containers own positions.
static func stagger_rows(container: Node, step: float = 0.06, base_delay: float = 0.05) -> void:
	var rows: Array[Control] = []
	for c in container.get_children():
		if c is Control and (c as Control).visible:
			rows.append(c as Control)
	if rows.is_empty():
		return
	var use_step := step
	if rows.size() > 1:
		use_step = minf(step, CASCADE_MAX / float(rows.size() - 1))
	var i := 0
	for ctrl: Control in rows:
		ctrl.modulate.a = 0.0
		var t := ctrl.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		t.tween_interval(base_delay + use_step * i)
		# .from(0.0) pins the start value so a row another tween is already
		# driving cannot inherit ITS alpha and ride the wrong curve.
		t.tween_property(ctrl, "modulate:a", 1.0, T_STD).from(0.0)
		i += 1

## Longest a staggered reveal may take, whatever the row count.
const CASCADE_MAX := 0.20

# ------------------------------------------------------------------- theme ----
static func create(accent: Color = CYAN) -> Theme:
	var theme := Theme.new()
	var hot := hot_of(accent)
	# LAW 1: the aliased font is installed as the DEFAULT, so a screen that
	# overrides nothing still gets crisp text.
	theme.default_font = ui_font()
	theme.default_font_size = BODY

	theme.set_stylebox("panel", "PanelContainer", panel_box(accent))
	theme.set_stylebox("panel", "Panel", panel_box(accent))

	var boxes := button_boxes(accent)
	theme.set_stylebox("normal", "Button", boxes.normal)
	theme.set_stylebox("hover", "Button", boxes.hover)
	theme.set_stylebox("pressed", "Button", boxes.pressed)
	theme.set_stylebox("focus", "Button", boxes.focus)
	theme.set_stylebox("disabled", "Button", boxes.disabled)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", hot)
	theme.set_color("font_pressed_color", "Button", WHITE_HOT)
	theme.set_color("font_focus_color", "Button", hot)
	theme.set_color("font_disabled_color", "Button", with_alpha(TEXT_DIM, 0.5))
	theme.set_font_size("font_size", "Button", BODY)

	theme.set_stylebox("background", "ProgressBar", bar_bg_box())
	theme.set_stylebox("fill", "ProgressBar", bar_fill_box(accent, hot))

	theme.set_color("font_color", "Label", TEXT)
	theme.set_font_size("font_size", "Label", BODY)
	# One pixel of shadow as the default, so any label anywhere survives a lit
	# floor without a plate under it (LAW 4).
	theme.set_color("font_shadow_color", "Label", with_alpha(OUTLINE_COL, 0.8))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)
	theme.set_constant("outline_size", "Label", 0)
	theme.set_color("default_color", "RichTextLabel", TEXT)
	theme.set_font_size("normal_font_size", "RichTextLabel", BODY)

	# Sliders: thin LINE groove, accent progress.
	var groove := StyleBoxFlat.new()
	groove.bg_color = with_alpha(LINE, 0.7)
	groove.content_margin_top = 2.0
	groove.content_margin_bottom = 2.0
	var grabber_area := StyleBoxFlat.new()
	grabber_area.bg_color = with_alpha(accent, 0.8)
	grabber_area.content_margin_top = 2.0
	grabber_area.content_margin_bottom = 2.0
	var grabber_hl: StyleBoxFlat = grabber_area.duplicate()
	grabber_hl.bg_color = hot
	theme.set_stylebox("slider", "HSlider", groove)
	theme.set_stylebox("grabber_area", "HSlider", grabber_area)
	theme.set_stylebox("grabber_area_highlight", "HSlider", grabber_hl)

	theme.set_color("font_color", "CheckButton", TEXT)
	theme.set_color("font_hover_color", "CheckButton", hot)

	var sep := StyleBoxLine.new()
	sep.color = with_alpha(LINE, 0.9)
	theme.set_stylebox("separator", "HSeparator", sep)
	return theme

# ----------------------------------------------- legacy API (kept working) ----
static func hp_bar_fill() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = RED
	return s

static func focus_bar_fill() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = CYAN
	return s

## The Dream App console is a modal screen; LAW 8 gives it the modal panel and
## nothing else. It used to carry a cyan border, an 8px radius and an 18px cyan
## halo — three separate ways of saying "this is a panel" over the top of a
## panel.
static func dream_app_panel() -> StyleBoxFlat:
	return panel_box(CYAN, 18.0)

static func accent_cyan() -> Color:
	return CYAN

static func accent_muted() -> Color:
	return with_alpha(CYAN, 0.65)

## The one primary action on the Dream App screen: a filled accent edge, no
## halo. One accent per screen (LAW 8) and this is where it is spent.
static func ship_button() -> StyleBoxFlat:
	var btn := StyleBoxFlat.new()
	btn.bg_color = with_alpha(CYAN, 0.12)
	btn.border_color = with_alpha(CYAN, 0.85)
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(2)
	btn.set_content_margin_all(10)
	btn.shadow_size = 0
	return btn
