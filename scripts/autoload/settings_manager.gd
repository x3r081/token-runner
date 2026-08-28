extends Node
## Persistent game settings.

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULTS := {
	"master_volume": 0.6,
	"music_volume": 0.25,
	"sfx_volume": 0.35,
	"fullscreen": false,
	"resolution_index": 2,
	"camera_shake": true,
	"ui_scale": 1.0,
	"graphics_quality": 1,
}

const RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

var settings: Dictionary = {}

func _ready() -> void:
	load_settings()
	apply_all()

func load_settings() -> void:
	settings = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for key in DEFAULTS:
			if cfg.has_section_key("settings", key):
				settings[key] = cfg.get_value("settings", key)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in settings:
		cfg.set_value("settings", key, settings[key])
	cfg.save(SETTINGS_PATH)

func get_setting(key: String):
	return settings.get(key, DEFAULTS.get(key))

func set_setting(key: String, value) -> void:
	settings[key] = value
	save_settings()
	apply_setting(key)
	settings_changed.emit()

func apply_all() -> void:
	for key in settings:
		apply_setting(key)

func apply_setting(key: String) -> void:
	match key:
		"master_volume", "music_volume", "sfx_volume":
			AudioManager.set_volumes(
				settings.master_volume,
				settings.music_volume,
				settings.sfx_volume
			)
			# Music stays gated until player opts in via settings.
			if settings.music_volume > 0.3:
				AudioManager.enable_music()
		"fullscreen":
			if settings.fullscreen:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		"resolution_index":
			var idx: int = clampi(settings.resolution_index, 0, RESOLUTIONS.size() - 1)
			var res: Vector2i = RESOLUTIONS[idx]
			if not settings.fullscreen:
				DisplayServer.window_set_size(res)
		"ui_scale":
			get_tree().root.content_scale_factor = settings.ui_scale

func get_setting_label(key: String) -> String:
	match key:
		"camera_shake": return "Disable if reality already shakes enough."
		"fullscreen": return "Pretend you have a dedicated battlestation."
		"master_volume": return "Controls everything. Like a tech lead."
		"music_volume": return "Lo-fi beats to ignore production alerts."
		"sfx_volume": return "Token sounds. Cash register optional."
		_: return ""
