extends Node
## Regression test for conservative, safe audio: silent-by-default music,
## conservative volumes, a hard limiter on the Master bus, and generated streams
## whose peak amplitude is nowhere near full-scale (no harsh startup static).
##
## Run: godot --headless --path . --scene tests/audio_test.tscn

var passed := 0
var failed := 0

func _ready() -> void:
	_run()
	print("AUDIO TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	# Music must not auto-play; it stays gated until explicitly enabled.
	_check("music_disabled_by_default", AudioManager.music_enabled == false)
	AudioManager.play_music("menu_music")
	_check("music_does_not_play_until_enabled", AudioManager.music_player.stream == null)

	# Conservative default volumes.
	_check("master_volume_conservative", AudioManager.master_vol <= 0.7)
	_check("music_volume_conservative", AudioManager.music_vol <= 0.4)
	_check("sfx_volume_conservative", AudioManager.sfx_vol <= 0.5)

	# A hard limiter guarantees a safe output ceiling.
	var master_idx := AudioServer.get_bus_index("Master")
	var has_limiter := false
	var ceiling_ok := false
	for e in AudioServer.get_bus_effect_count(master_idx):
		var fx := AudioServer.get_bus_effect(master_idx, e)
		if fx is AudioEffectHardLimiter:
			has_limiter = true
			ceiling_ok = fx.ceiling_db <= 0.0
	_check("master_bus_has_hard_limiter", has_limiter)
	_check("limiter_ceiling_not_positive", ceiling_ok)

	# Generated streams exist and never approach full-scale amplitude.
	var worst := 0
	for name in ["token_collect", "ability", "damage", "quest_complete", "enemy_death"]:
		_check("stream_exists_%s" % name, AudioManager._streams.has(name))
		if AudioManager._streams.has(name):
			var s = AudioManager._streams[name]
			if s is AudioStreamWAV:
				for b in s.data:
					worst = maxi(worst, abs(int(b) - 128))
	# 8-bit unsigned centred at 128; full scale = 127. Keep well below.
	_check("no_near_full_scale_samples (peak dev %d/127)" % worst, worst < 96)

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
