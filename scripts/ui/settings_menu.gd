extends PanelContainer

func _ready() -> void:
	$Margin/VBox/MasterSlider.value = SettingsManager.get_setting("master_volume")
	$Margin/VBox/MusicSlider.value = SettingsManager.get_setting("music_volume")
	$Margin/VBox/SFXSlider.value = SettingsManager.get_setting("sfx_volume")
	$Margin/VBox/FullscreenBtn.button_pressed = SettingsManager.get_setting("fullscreen")
	$Margin/VBox/CameraShakeBtn.button_pressed = SettingsManager.get_setting("camera_shake")
	$Margin/VBox/MasterSlider.value_changed.connect(func(v): SettingsManager.set_setting("master_volume", v))
	$Margin/VBox/MusicSlider.value_changed.connect(func(v): SettingsManager.set_setting("music_volume", v))
	$Margin/VBox/SFXSlider.value_changed.connect(func(v): SettingsManager.set_setting("sfx_volume", v))
	$Margin/VBox/FullscreenBtn.toggled.connect(func(v): SettingsManager.set_setting("fullscreen", v))
	$Margin/VBox/CameraShakeBtn.toggled.connect(func(v): SettingsManager.set_setting("camera_shake", v))
	$Margin/VBox/CloseBtn.pressed.connect(queue_free)
	$Margin/VBox/CameraShakeLabel.tooltip_text = SettingsManager.get_setting_label("camera_shake")
