extends PanelContainer

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

func _ready() -> void:
	theme = _GameTheme.create()
	add_theme_stylebox_override("panel", _GameTheme.panel_box(_GameTheme.CYAN, 4.0))
	_GameTheme.style_heading($Margin/VBox/Title, _GameTheme.CYAN, 22)
	_GameTheme.style_button($Margin/VBox/CloseBtn, _GameTheme.CYAN, 15)
	for lbl: Label in [$Margin/VBox/MasterLabel, $Margin/VBox/MusicLabel,
			$Margin/VBox/SFXLabel, $Margin/VBox/CameraShakeLabel]:
		lbl.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
		lbl.add_theme_font_size_override("font_size", 13)
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
