extends PanelContainer
## Settings. Every row says what the control does; the joke moved to the tooltip,
## where it costs the layout nothing.
##
## Round 6: the labels used to read "Master Volume — <one-line joke>", which
## doubled the height of a panel with seven rows in it and pushed the whole thing
## past its own rect. Plain names now, quips on hover.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Comedy = preload("res://scripts/ui/comedy_lines.gd")
const _Modal = preload("res://scripts/ui/modal_panel.gd")

const SUBTITLES := [
	"Everything below actually works. We were as surprised as you.",
	"No telemetry, no account, no cookie banner. Revolutionary.",
	"Zero settings here are placeholders. That is the whole flex.",
	"Seven options. Shipped. Documented. A personal best.",
]

## label node -> settings key. Drives the plain name and the tooltip.
const LABEL_KEYS := {
	"MasterLabel": ["master_volume", "Master volume"],
	"MusicLabel": ["music_volume", "Music volume"],
	"SFXLabel": ["sfx_volume", "SFX volume"],
	"CameraShakeLabel": ["camera_shake", "Camera shake"],
}

func _ready() -> void:
	theme = _GameTheme.create()
	add_theme_stylebox_override("panel", _Modal.modal_box(_GameTheme.CYAN, 6.0))
	offset_left = -260.0
	offset_right = 260.0
	offset_top = -230.0
	offset_bottom = 230.0
	var title: Label = $Margin/VBox/Title
	title.add_theme_font_size_override("font_size", _Modal.HEADING)
	title.add_theme_color_override("font_color", _GameTheme.CYAN)
	_GameTheme.style_button($Margin/VBox/CloseBtn, _GameTheme.TEXT_DIM, _Modal.SMALL)
	_build_subtitle()
	for lbl: Label in [$Margin/VBox/MasterLabel, $Margin/VBox/MusicLabel,
			$Margin/VBox/SFXLabel, $Margin/VBox/CameraShakeLabel]:
		lbl.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
		lbl.add_theme_font_size_override("font_size", _Modal.SMALL)
		var pair: Array = LABEL_KEYS.get(String(lbl.name), [])
		if pair.size() == 2:
			lbl.text = String(pair[1])
			lbl.tooltip_text = SettingsManager.get_setting_label(String(pair[0]))
	# Checkbox rows say what they toggle; the opinion is in the tooltip.
	$Margin/VBox/MusicEnabledBtn.text = "Music"
	$Margin/VBox/MusicEnabledBtn.tooltip_text = "Turns the ambient track on. It is validated, gentle, and entirely optional."
	$Margin/VBox/FullscreenBtn.text = "Fullscreen"
	$Margin/VBox/FullscreenBtn.tooltip_text = SettingsManager.get_setting_label("fullscreen")
	$Margin/VBox/CameraShakeBtn.text = "Shake on hits and deaths"
	$Margin/VBox/CameraShakeBtn.tooltip_text = SettingsManager.get_setting_label("camera_shake")
	$Margin/VBox/CloseBtn.text = "Close"
	$Margin/VBox/CloseBtn.tooltip_text = "Saves automatically. Unlike some software you have shipped."
	$Margin/VBox/MasterSlider.tooltip_text = SettingsManager.get_setting_label("master_volume")
	$Margin/VBox/MusicSlider.tooltip_text = SettingsManager.get_setting_label("music_volume")
	$Margin/VBox/SFXSlider.tooltip_text = SettingsManager.get_setting_label("sfx_volume")
	$Margin/VBox/MasterSlider.value = SettingsManager.get_setting("master_volume")
	$Margin/VBox/MusicSlider.value = SettingsManager.get_setting("music_volume")
	$Margin/VBox/SFXSlider.value = SettingsManager.get_setting("sfx_volume")
	$Margin/VBox/FullscreenBtn.button_pressed = SettingsManager.get_setting("fullscreen")
	$Margin/VBox/CameraShakeBtn.button_pressed = SettingsManager.get_setting("camera_shake")
	$Margin/VBox/MusicEnabledBtn.button_pressed = SettingsManager.get_setting("music_enabled")
	$Margin/VBox/MasterSlider.value_changed.connect(func(v): SettingsManager.set_setting("master_volume", v))
	$Margin/VBox/MusicSlider.value_changed.connect(func(v): SettingsManager.set_setting("music_volume", v))
	$Margin/VBox/MusicEnabledBtn.toggled.connect(func(v): SettingsManager.set_setting("music_enabled", v))
	$Margin/VBox/SFXSlider.value_changed.connect(func(v): SettingsManager.set_setting("sfx_volume", v))
	$Margin/VBox/FullscreenBtn.toggled.connect(func(v): SettingsManager.set_setting("fullscreen", v))
	$Margin/VBox/CameraShakeBtn.toggled.connect(func(v): SettingsManager.set_setting("camera_shake", v))
	_build_quality_row()
	$Margin/VBox/CloseBtn.pressed.connect(queue_free)
	$Margin/VBox/CameraShakeLabel.tooltip_text = SettingsManager.get_setting_label("camera_shake")
	_GameTheme.open_panel(self)

## Graphics quality had a real effect and no control: at Reduced the atmosphere
## collapses to the single multiply-blend floor quad and portals skip their
## screen-reading lens. Built in code so settings_menu.tscn keeps every node name
## the rest of the UI relies on. Takes effect on the next region you walk into.
func _build_quality_row() -> void:
	var vbox: VBoxContainer = $Margin/VBox
	var lbl := Label.new()
	lbl.name = "QualityLabel"
	lbl.text = "Graphics"
	lbl.tooltip_text = SettingsManager.get_setting_label("graphics_quality")
	lbl.add_theme_font_size_override("font_size", _Modal.SMALL)
	lbl.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	vbox.add_child(lbl)
	vbox.move_child(lbl, vbox.get_child_count() - 2)
	var opt := OptionButton.new()
	opt.name = "QualityOption"
	opt.add_item("Full", 1)
	opt.add_item("Reduced", 0)
	opt.select(0 if int(SettingsManager.get_setting("graphics_quality")) >= 1 else 1)
	opt.tooltip_text = "Applies to the next region you enter."
	opt.item_selected.connect(func(i: int) -> void:
		SettingsManager.set_setting("graphics_quality", opt.get_item_id(i))
	)
	vbox.add_child(opt)
	vbox.move_child(opt, vbox.get_child_count() - 2)

## One dry line under the title. Also, quietly, the truth: changes apply live.
func _build_subtitle() -> void:
	var sub := Label.new()
	sub.name = "Subtitle"
	sub.text = _Comedy.any(SUBTITLES)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", _Modal.SMALL)
	sub.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	var vbox: VBoxContainer = $Margin/VBox
	vbox.add_child(sub)
	vbox.move_child(sub, 1)
