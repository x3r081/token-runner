extends RefCounted
class_name GameTheme
## "Neon Afterhours" UI token set — the single source of truth for panel glass,
## button states, bar gradients, glow layers, and micro-motion. Every UI script
## pulls from here so the whole interface reads as one premium neon product
## instead of ten panels that met once at a hackathon.

# ---------------------------------------------------------------- palette ----
# Master palette (docs/VISUAL_BIBLE.md). Do not invent colors elsewhere.
const VOID := Color("#05060E")
const BASE := Color("#0B0E1C")
const SURFACE := Color("#131A2E")
const RAISED := Color("#1C2440")
const LINE := Color("#2A3558")
const TEXT_DIM := Color("#7C8BB0")
const TEXT := Color("#C9D6F2")
const WHITE_HOT := Color("#F4F9FF")
const CYAN := Color("#24F0DC")
const CYAN_HOT := Color("#7DFFF0")
const MAGENTA := Color("#FF2D95")
const VIOLET := Color("#8B5CF6")
const BLUE := Color("#3D9BFF")
const ACID := Color("#A8FF3E")
const AMBER := Color("#FFB020")
const RED := Color("#FF4757")
const GOLD := Color("#FFD34D")

# Animation timing (bible): micro / standard / dramatic. TRANS_CUBIC everywhere.
const T_MICRO := 0.12
const T_STD := 0.25
const T_DRAMA := 0.6

const SHEEN_SHADER := "res://assets/shaders/ui_sheen.gdshader"
const STARFIELD_SHADER := "res://assets/shaders/starfield.gdshader"

# Shared resource caches — one instance per shader/params/texture combo.
static var _mat_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}
static var _font_cache: Dictionary = {}
static var _additive_mat: CanvasItemMaterial = null

# ------------------------------------------------------------ core colors ----
## Emissive "hot" companion of an accent (bar gradients, hover text).
static func hot_of(accent: Color) -> Color:
	return accent.lerp(WHITE_HOT, 0.55)

static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

# --------------------------------------------------------------- materials ----
## Shared additive material for overbright glow layers.
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
## 2x2 fully transparent texture — canvas for pure-shader overlays (sheen).
static func clear_texture() -> ImageTexture:
	if not _tex_cache.has("clear"):
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_tex_cache["clear"] = ImageTexture.create_from_image(img)
	return _tex_cache["clear"]

## Horizontal accent->hot gradient with a 1px WHITE_HOT top edge, for bar fills.
static func bar_gradient_texture(accent: Color, hot: Color) -> ImageTexture:
	var key := "bar:%s:%s" % [accent.to_html(), hot.to_html()]
	if not _tex_cache.has(key):
		var w := 64
		var h := 12
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for x in w:
			var c := accent.lerp(hot, float(x) / float(w - 1))
			for y in h:
				img.set_pixel(x, y, c)
		for x in w:
			img.set_pixel(x, 0, WHITE_HOT)
		_tex_cache[key] = ImageTexture.create_from_image(img)
	return _tex_cache[key]

## Radial vignette (transparent center, tinted edges) for full-bleed screens.
static func vignette_texture(edge: Color) -> GradientTexture2D:
	var key := "vig:%s" % edge.to_html()
	if not _tex_cache.has(key):
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([with_alpha(edge, 0.0), with_alpha(edge, 0.25), edge])
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
## Letter-spaced variation of the default font, for headings/titles.
static func spaced_font(spacing: int = 3) -> FontVariation:
	var key := "sp:%d" % spacing
	if not _font_cache.has(key):
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		fv.set_spacing(TextServer.SPACING_GLYPH, spacing)
		_font_cache[key] = fv
	return _font_cache[key]

# ------------------------------------------------------------- styleboxes ----
## Standard neon panel: BASE 92%, 1px LINE border, radius 6, accent outer glow.
static func panel_box(accent: Color = CYAN, margin: float = 16.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = with_alpha(BASE, 0.92)
	s.border_color = LINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(margin)
	s.shadow_color = with_alpha(accent, 0.14)
	s.shadow_size = 14
	return s

## HUD "glass" group panel: darker, quieter glow, tighter margins.
static func glass_box(accent: Color = CYAN, margin: float = 10.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = with_alpha(BASE, 0.78)
	s.border_color = with_alpha(LINE, 0.9)
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(margin)
	s.shadow_color = with_alpha(accent, 0.10)
	s.shadow_size = 8
	return s

## Invisible stylebox (turns a PanelContainer into a pure layout node).
static func empty_box() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()

## Small accent chip (speaker names, key hints, tags).
static func chip_box(accent: Color = CYAN) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = with_alpha(accent, 0.14)
	s.border_color = with_alpha(accent, 0.7)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 10.0
	s.content_margin_right = 10.0
	s.content_margin_top = 2.0
	s.content_margin_bottom = 2.0
	return s

## Button state boxes per bible: transparent base / 4% hover / 12% pressed.
static func button_boxes(accent: Color = CYAN) -> Dictionary:
	var normal := StyleBoxFlat.new()
	normal.bg_color = with_alpha(accent, 0.02)
	normal.border_color = LINE
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 16.0
	normal.content_margin_right = 16.0
	normal.content_margin_top = 9.0
	normal.content_margin_bottom = 9.0
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = with_alpha(accent, 0.04)
	hover.border_color = with_alpha(accent, 0.9)
	hover.shadow_color = with_alpha(accent, 0.28)
	hover.shadow_size = 6
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = with_alpha(accent, 0.12)
	pressed.border_color = accent
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = with_alpha(accent, 0.85)
	focus.set_border_width_all(1)
	focus.set_corner_radius_all(6)
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = with_alpha(SURFACE, 0.5)
	disabled.border_color = with_alpha(LINE, 0.5)
	return {"normal": normal, "hover": hover, "pressed": pressed, "focus": focus, "disabled": disabled}

## Bar background: recessed dark slot.
static func bar_bg_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = with_alpha(VOID, 0.85)
	s.border_color = with_alpha(LINE, 0.8)
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	return s

## Bar fill: gradient accent -> hot with baked WHITE_HOT top edge.
static func bar_fill_box(accent: Color, hot: Color = Color.TRANSPARENT) -> StyleBoxTexture:
	if hot.a == 0.0:
		hot = hot_of(accent)
	var s := StyleBoxTexture.new()
	s.texture = bar_gradient_texture(accent, hot)
	return s

# ----------------------------------------------------------- apply helpers ----
## Full button treatment: state boxes, font colors, hover scale micro-motion.
static func style_button(btn: Button, accent: Color = CYAN, font_size: int = 17) -> void:
	var boxes := button_boxes(accent)
	btn.add_theme_stylebox_override("normal", boxes.normal)
	btn.add_theme_stylebox_override("hover", boxes.hover)
	btn.add_theme_stylebox_override("pressed", boxes.pressed)
	btn.add_theme_stylebox_override("focus", boxes.focus)
	btn.add_theme_stylebox_override("disabled", boxes.disabled)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", hot_of(accent))
	btn.add_theme_color_override("font_pressed_color", WHITE_HOT)
	btn.add_theme_color_override("font_focus_color", hot_of(accent))
	btn.add_theme_color_override("font_disabled_color", with_alpha(TEXT_DIM, 0.55))
	btn.add_theme_font_size_override("font_size", font_size)
	attach_hover_motion(btn)

## Scale 1.02 on hover (bible micro-motion). Pause-proof.
static func attach_hover_motion(ctrl: Control, amount: float = 1.02) -> void:
	if ctrl.has_meta("_hover_motion"):
		return
	ctrl.set_meta("_hover_motion", true)
	ctrl.pivot_offset = ctrl.size * 0.5
	ctrl.resized.connect(func() -> void:
		ctrl.pivot_offset = ctrl.size * 0.5)
	ctrl.mouse_entered.connect(func() -> void:
		_hover_scale(ctrl, Vector2.ONE * amount))
	ctrl.mouse_exited.connect(func() -> void:
		_hover_scale(ctrl, Vector2.ONE))

static func _hover_scale(ctrl: Control, target: Vector2) -> void:
	if not is_instance_valid(ctrl) or not ctrl.is_inside_tree():
		return
	var old: Variant = ctrl.get_meta("_hover_tw") if ctrl.has_meta("_hover_tw") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var t := ctrl.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(ctrl, "scale", target, T_MICRO)
	ctrl.set_meta("_hover_tw", t)

## Progress bar with gradient fill + hot top edge.
static func style_bar(bar: ProgressBar, accent: Color, hot: Color = Color.TRANSPARENT) -> void:
	bar.add_theme_stylebox_override("background", bar_bg_box())
	bar.add_theme_stylebox_override("fill", bar_fill_box(accent, hot))

## Letter-spaced accent heading.
static func style_heading(l: Label, accent: Color = CYAN, font_size: int = -1) -> void:
	l.add_theme_color_override("font_color", accent)
	l.add_theme_font_override("font", spaced_font(3))
	if font_size > 0:
		l.add_theme_font_size_override("font_size", font_size)

## Duplicated overbright glow layer behind a label (HDR bloom picks it up).
## Call AFTER the label's text/size are final; returns the glow layer.
static func add_glow_layer(label: Label, strength: float = 2.2) -> Label:
	var glow := label.duplicate() as Label
	glow.name = "GlowLayer"
	glow.material = additive_material()
	glow.modulate = Color(strength, strength, strength, 0.5)
	glow.show_behind_parent = true
	label.add_child(glow)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return glow

## Slow breathing pulse on a glow layer. Pause-proof, loops forever.
static func pulse(node: CanvasItem, lo: float = 1.5, hi: float = 2.4, period: float = 2.4) -> void:
	var t := node.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(node, "modulate", Color(lo, lo, lo, 0.42), period * 0.5)
	t.tween_property(node, "modulate", Color(hi, hi, hi, 0.58), period * 0.5)

## Moving diagonal sheen overlay on a panel (ui_sheen.gdshader, guarded).
static func add_sheen(host: Control, color: Color = Color(1, 1, 1, 0.05), period: float = 7.0) -> void:
	var mat := shader_material(SHEEN_SHADER, {"sheen_color": color, "period": period})
	if mat == null:
		return
	var tr := TextureRect.new()
	tr.name = "Sheen"
	tr.texture = clear_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.material = mat
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(tr)

## Full-bleed vignette layer (death/victory/menu backdrops).
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
## Panel entrance: fade + scale-up, 0.25s TRANS_CUBIC. Pause-proof.
static func open_panel(ctrl: Control) -> void:
	ctrl.pivot_offset = ctrl.size * 0.5
	# Containers may not have a size yet on the _ready frame; keep the pivot
	# centered once the layout settles so the scale-in doesn't hinge on a corner.
	if not ctrl.has_meta("_pivot_hook"):
		ctrl.set_meta("_pivot_hook", true)
		ctrl.resized.connect(func() -> void:
			ctrl.pivot_offset = ctrl.size * 0.5)
	ctrl.modulate.a = 0.0
	ctrl.scale = Vector2.ONE * 0.96
	var t := ctrl.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(ctrl, "modulate:a", 1.0, T_STD)
	t.tween_property(ctrl, "scale", Vector2.ONE, T_STD)

## Rows fade in one after another (0.06s apart). Modulate only — containers
## own their children's positions, so we don't fight the layout.
static func stagger_rows(container: Node, step: float = 0.06, base_delay: float = 0.05) -> void:
	var i := 0
	for c in container.get_children():
		if not (c is Control) or not (c as Control).visible:
			continue
		var ctrl := c as Control
		ctrl.modulate.a = 0.0
		var t := ctrl.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		t.tween_interval(base_delay + step * i)
		t.tween_property(ctrl, "modulate:a", 1.0, T_STD)
		i += 1

# ------------------------------------------------------------------- theme ----
static func create(accent: Color = CYAN) -> Theme:
	var theme := Theme.new()
	var hot := hot_of(accent)

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
	theme.set_color("font_disabled_color", "Button", with_alpha(TEXT_DIM, 0.55))
	theme.set_font_size("font_size", "Button", 17)

	theme.set_stylebox("background", "ProgressBar", bar_bg_box())
	theme.set_stylebox("fill", "ProgressBar", bar_fill_box(accent, hot))

	theme.set_color("font_color", "Label", TEXT)
	theme.set_font_size("font_size", "Label", 16)
	theme.set_color("default_color", "RichTextLabel", TEXT)

	# Sliders (settings): thin LINE groove, accent progress, WHITE_HOT grabber.
	var groove := StyleBoxFlat.new()
	groove.bg_color = with_alpha(LINE, 0.7)
	groove.set_corner_radius_all(2)
	groove.content_margin_top = 2.0
	groove.content_margin_bottom = 2.0
	var grabber_area := StyleBoxFlat.new()
	grabber_area.bg_color = with_alpha(accent, 0.85)
	grabber_area.set_corner_radius_all(2)
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
	s.set_corner_radius_all(4)
	return s

static func focus_bar_fill() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = CYAN
	s.set_corner_radius_all(4)
	return s

static func dream_app_panel() -> StyleBoxFlat:
	var panel := panel_box(CYAN, 18.0)
	panel.bg_color = with_alpha(BASE, 0.985)
	panel.border_color = with_alpha(CYAN, 0.55)
	panel.set_corner_radius_all(8)
	panel.shadow_color = with_alpha(CYAN, 0.22)
	panel.shadow_size = 18
	return panel

static func accent_cyan() -> Color:
	return CYAN

static func accent_muted() -> Color:
	return with_alpha(CYAN, 0.65)

static func ship_button() -> StyleBoxFlat:
	var btn := StyleBoxFlat.new()
	btn.bg_color = with_alpha(CYAN, 0.10)
	btn.border_color = with_alpha(CYAN, 0.9)
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(6)
	btn.set_content_margin_all(10)
	btn.shadow_color = with_alpha(CYAN, 0.30)
	btn.shadow_size = 8
	return btn
