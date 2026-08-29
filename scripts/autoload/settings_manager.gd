extends Node
## Persistent game settings.

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"
## Audio is ON by default (AUDIO_BIBLE.md: silent-by-default was a
## placeholder-era safety, not a design decision). Volumes stay modest and the
## menu fades in — never startles. Keys are unchanged so old cfg files load;
## v1 cfgs (no config_version) get the one-time audio migration below.
const DEFAULTS := {
	"master_volume": 0.7,
	"music_volume": 0.4,
	"sfx_volume": 0.5,
	"fullscreen": false,
	"resolution_index": 2,
	"camera_shake": true,
	"ui_scale": 1.0,
	"graphics_quality": 1,
	"music_enabled": true,
	"config_version": 2,
}

## Audio values as they shipped in the silent-by-default era. A cfg without
## "config_version" predates audible-by-default, and back then save_settings()
## wrote EVERY key — so touching any setting persisted music_enabled=false as
## the old default, not as a choice. Those cfgs migrate once (below).
const _V1_AUDIO_DEFAULTS := {
	"master_volume": 0.6,
	"music_volume": 0.25,
	"sfx_volume": 0.35,
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
		if not cfg.has_section_key("settings", "config_version"):
			_migrate_v1_audio()

## One-time upgrade of placeholder-era cfgs (AUDIO_BIBLE hard rule: audio is ON
## by default; silent-by-default was a safety, not a decision). music_enabled
## false in a v1 cfg carried no intent, so it flips on; volumes are bumped only
## while they still sit exactly on the old defaults, so hand-picked levels
## survive. save_settings() stamps config_version, so any later deliberate
## mute or volume change sticks forever — this never runs twice.
func _migrate_v1_audio() -> void:
	settings.music_enabled = true
	for key: String in _V1_AUDIO_DEFAULTS:
		if is_equal_approx(float(settings[key]), float(_V1_AUDIO_DEFAULTS[key])):
			settings[key] = DEFAULTS[key]
	save_settings()

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
		"music_enabled":
			if settings.music_enabled:
				# Deferred: apply_all() runs during autoload _ready, and music
				# must not start until the tree is fully up (also keeps the
				# audio test's silent-at-_ready contract intact).
				call_deferred("_apply_music_enabled")
			else:
				AudioManager.music_enabled = false
				AudioManager.stop_music()
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

## Runs one frame after apply_setting("music_enabled") — no startle: the menu
## track fades in over 1.5s from silence.
func _apply_music_enabled() -> void:
	if not settings.music_enabled:
		return
	AudioManager.enable_music()
	if GameManager.state == GameManager.GameState.MENU:
		AudioManager.play_music("menu_music", 1.5)
	elif GameManager.state == GameManager.GameState.PLAYING:
		AudioManager.play_music("explore_music", 1.5)

func get_setting_label(key: String) -> String:
	match key:
		"camera_shake": return "Disable if reality already shakes enough."
		"fullscreen": return "Pretend you have a dedicated battlestation."
		"master_volume": return "Controls everything. Like a tech lead."
		"music_volume": return "Lo-fi beats to ignore production alerts."
		"music_enabled": return "The 3AM soundtrack. On by default, like your standup reminder."
		"sfx_volume": return "Token sounds. Cash register optional."
		"graphics_quality": return "Full turns on god rays, portal lensing and the heat shimmer. Reduced turns them off and nobody has to know."
		_: return ""
