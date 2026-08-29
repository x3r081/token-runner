extends PanelContainer
## Settings: every row keeps its real name first and earns its joke second, so
## the label still tells you what the control does even when it is being rude.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Comedy = preload("res://scripts/ui/comedy_lines.gd")

const SUBTITLES := [
	"Everything below actually works. We were as surprised as you.",
	"No telemetry, no account, no cookie banner. Revolutionary.",
	"Zero settings here are placeholders. That is the whole flex.",
	"Six options. Shipped. Documented. A personal best.",
]

## label node -> settings key. Drives both the "Name — quip" text and tooltips.
const LABEL_KEYS := {
	"MasterLabel": ["master_volume", "Master Volume"],
	"MusicLabel": ["music_volume", "Music Volume"],
	"SFXLabel": ["sfx_volume", "SFX Volume"],
	"CameraShakeLabel": ["camera_shake", "Camera Shake"],
}

func _ready() -> void:
	theme = _GameTheme.create()
	add_theme_stylebox_override("panel", _GameTheme.panel_box(_GameTheme.CYAN, 4.0))
	# Room for the longer, chattier labels.
	offset_left = -280.0
	offset_right = 280.0
	offset_top = -230.0
	offset_bottom = 230.0
	_GameTheme.style_heading($Margin/VBox/Title, _GameTheme.CYAN, 22)
	_GameTheme.style_button($Margin/VBox/CloseBtn, _GameTheme.CYAN, 15)
	_build_subtitle()
	for lbl: Label in [$Margin/VBox/MasterLabel, $Margin/VBox/MusicLabel,
			$Margin/VBox/SFXLabel, $Margin/VBox/CameraShakeLabel]:
		lbl.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var pair: Array = LABEL_KEYS.get(String(lbl.name), [])
		if pair.size() == 2:
			var quip: String = SettingsManager.get_setting_label(String(pair[0]))
			var plain: String = String(pair[1])
			if quip.is_empty():
				lbl.text = plain
			else:
				lbl.text = "%s — %s" % [plain, quip]
			lbl.tooltip_text = quip
	# Checkbox rows say what they toggle, then say something about you.
	$Margin/VBox/MusicEnabledBtn.text = "Music (off by default — your ears thanked us)"
	$Margin/VBox/MusicEnabledBtn.tooltip_text = "Turns the ambient track on. It is validated, gentle, and entirely optional."
	$Margin/VBox/FullscreenBtn.text = "Fullscreen (commit to the bit)"
	$Margin/VBox/FullscreenBtn.tooltip_text = SettingsManager.get_setting_label("fullscreen")
	$Margin/VBox/CameraShakeBtn.text = "Camera shake on hits and deaths"
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
	$Margin/VBox/CloseBtn.pressed.connect(queue_free)
	$Margin/VBox/CameraShakeLabel.tooltip_text = SettingsManager.get_setting_label("camera_shake")
	_GameTheme.open_panel(self)

## One dry line under the title. Also, quietly, the truth: changes apply live.
func _build_subtitle() -> void:
	var sub := Label.new()
	sub.name = "Subtitle"
	sub.text = _Comedy.any(SUBTITLES) + "\nEvery change applies immediately and saves itself."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", _GameTheme.with_alpha(_GameTheme.TEXT_DIM, 0.85))
	var vbox: VBoxContainer = $Margin/VBox
	vbox.add_child(sub)
	vbox.move_child(sub, 1)
