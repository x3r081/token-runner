extends RefCounted
class_name GameTheme
## Dark tech-noir UI theme — no default Godot chrome.

static func create() -> Theme:
	var theme := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.08, 0.07, 0.12, 0.92)
	panel.border_color = Color(0.35, 0.85, 0.75, 0.55)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 4
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)

	var btn_normal := panel.duplicate()
	btn_normal.bg_color = Color(0.12, 0.11, 0.18, 0.95)
	var btn_hover := btn_normal.duplicate()
	btn_hover.bg_color = Color(0.18, 0.16, 0.28, 0.98)
	btn_hover.border_color = Color(0.45, 0.95, 0.85, 0.8)
	var btn_pressed := btn_normal.duplicate()
	btn_pressed.bg_color = Color(0.22, 0.2, 0.32, 1.0)
	theme.set_stylebox("normal", "Button", btn_normal)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_pressed)
	theme.set_stylebox("focus", "Button", btn_hover)
	theme.set_color("font_color", "Button", Color(0.92, 0.9, 0.95))
	theme.set_color("font_hover_color", "Button", Color(0.5, 1.0, 0.9))
	theme.set_font_size("font_size", "Button", 18)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.1, 0.09, 0.14, 0.9)
	bar_bg.set_corner_radius_all(4)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.35, 0.85, 0.75, 1.0)
	bar_fill.set_corner_radius_all(4)
	theme.set_stylebox("background", "ProgressBar", bar_bg)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)

	theme.set_color("font_color", "Label", Color(0.88, 0.86, 0.92))
	theme.set_font_size("font_size", "Label", 16)
	return theme

static func hp_bar_fill() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.95, 0.35, 0.4, 1.0)
	s.set_corner_radius_all(4)
	return s

static func focus_bar_fill() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.45, 0.55, 0.95, 1.0)
	s.set_corner_radius_all(4)
	return s
