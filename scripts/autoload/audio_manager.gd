extends Node
## Safe audio management — silent by default until explicitly enabled.

var music_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
const MAX_SFX := 12

## Conservative defaults — silent > startling.
var master_vol: float = 0.6
var music_vol: float = 0.25
var sfx_vol: float = 0.35

## Startup safety gates — no auto audio until validated.
var music_enabled: bool = false
var sfx_enabled: bool = true
var startup_audio_validated: bool = false

var _streams: Dictionary = {}
var _bus_ready := false

func _ready() -> void:
	_setup_buses()
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	music_player.volume_db = -80.0
	add_child(music_player)
	for i in MAX_SFX:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.volume_db = -80.0
		add_child(p)
		sfx_players.append(p)
	_generate_procedural_audio()
	_load_validated_music()

func _setup_buses() -> void:
	if _bus_ready:
		return
	var idx := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus(idx + 1)
		AudioServer.set_bus_name(idx + 1, "Music")
		AudioServer.set_bus_send(idx + 1, "Master")
	if AudioServer.get_bus_index("SFX") == -1:
		var sfx_idx := AudioServer.get_bus_count()
		AudioServer.add_bus(sfx_idx)
		AudioServer.set_bus_name(sfx_idx, "SFX")
		AudioServer.set_bus_send(sfx_idx, "Master")
	_ensure_master_limiter()
	_bus_ready = true

## Guarantee a hard output ceiling so nothing can ever blast the player, no
## matter how many SFX stack or what a future stream contains.
func _ensure_master_limiter() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx < 0:
		return
	for e in AudioServer.get_bus_effect_count(master_idx):
		if AudioServer.get_bus_effect(master_idx, e) is AudioEffectHardLimiter:
			return
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -3.0
	AudioServer.add_bus_effect(master_idx, limiter)

func enable_music() -> void:
	music_enabled = true
	startup_audio_validated = true
	_apply_volumes()

func enable_sfx() -> void:
	sfx_enabled = true
	_apply_volumes()

func play_sfx(name: String) -> void:
	if not sfx_enabled or not _streams.has(name):
		return
	for p in sfx_players:
		if not p.playing:
			p.stream = _streams[name]
			p.volume_db = linear_to_db(sfx_vol * master_vol)
			p.play()
			return

func play_music(name: String, _fade: float = 0.5) -> void:
	if not music_enabled or not _streams.has(name):
		return
	if music_player.stream == _streams[name] and music_player.playing:
		return
	music_player.stream = _streams[name]
	music_player.volume_db = linear_to_db(music_vol * master_vol)
	music_player.play()

func stop_music() -> void:
	music_player.stop()

func set_volumes(master: float, music: float, sfx: float) -> void:
	master_vol = clampf(master, 0.0, 1.0)
	music_vol = clampf(music, 0.0, 1.0)
	sfx_vol = clampf(sfx, 0.0, 1.0)
	_apply_volumes()

func _apply_volumes() -> void:
	var music_db := linear_to_db(music_vol * master_vol) if music_enabled else -80.0
	var sfx_db := linear_to_db(sfx_vol * master_vol) if sfx_enabled else -80.0
	music_player.volume_db = music_db
	for p in sfx_players:
		if not p.playing:
			p.volume_db = sfx_db

func _generate_procedural_audio() -> void:
	_streams["token_collect"] = _make_tone(880.0, 0.08, 0.12)
	_streams["quest_complete"] = _make_chord([523.25, 659.25, 783.99], 0.4, 0.1)
	_streams["upgrade"] = _make_chord([392.0, 493.88, 587.33], 0.5, 0.1)
	_streams["damage"] = _make_noise_burst(0.12, 0.15)
	_streams["coffee"] = _make_tone(220.0, 0.2, 0.08)
	_streams["ui_click"] = _make_tone(1200.0, 0.04, 0.06)
	_streams["ui_hover"] = _make_tone(600.0, 0.03, 0.04)
	_streams["ability"] = _make_tone(440.0, 0.12, 0.1)
	_streams["enemy_death"] = _make_chord([200.0, 150.0], 0.3, 0.1)
	_streams["explore_music"] = _make_ambient_loop(90.0, 4.0)
	_streams["combat_music"] = _make_ambient_loop(120.0, 3.0)
	_streams["menu_music"] = _make_ambient_loop(60.0, 6.0)

func _load_validated_music() -> void:
	_load_looping_wav("res://assets/audio/menu_ambient.wav", "menu_music")
	_load_looping_wav("res://assets/audio/ambient_localhost.wav", "explore_music")

func _load_looping_wav(path: String, stream_name: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		_streams[stream_name] = stream

func _encode_sample(sample: float) -> int:
	return int(clamp((sample * 0.5 + 0.5) * 255.0, 0.0, 255.0))

func _make_tone(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(count)
	for i in count:
		var t := float(i) / sample_rate
		var env := 1.0 - float(i) / float(count)
		var sample := sin(TAU * freq * t) * env * volume
		data[i] = _encode_sample(sample)
	return _wav_from_data(data, sample_rate)

func _make_chord(freqs: Array, duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(count)
	for i in count:
		var t := float(i) / sample_rate
		var env := 1.0 - float(i) / float(count)
		var sample := 0.0
		for f in freqs:
			sample += sin(TAU * float(f) * t)
		sample = sample / freqs.size() * env * volume
		data[i] = _encode_sample(sample)
	return _wav_from_data(data, sample_rate)

func _make_noise_burst(duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(count)
	var rng := RandomNumberGenerator.new()
	for i in count:
		var env := 1.0 - float(i) / float(count)
		var sample := rng.randf_range(-1.0, 1.0) * env * volume
		data[i] = _encode_sample(sample)
	return _wav_from_data(data, sample_rate)

func _make_ambient_loop(base_freq: float, duration: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(count)
	for i in count:
		var t := float(i) / sample_rate
		var fade := sin(PI * float(i) / float(count - 1))
		var sample := (
			sin(TAU * base_freq * t) * 0.2
			+ sin(TAU * base_freq * 1.5 * t) * 0.08
			+ sin(TAU * base_freq * 0.5 * t) * 0.1
		) * 0.08 * fade
		data[i] = _encode_sample(sample)
	var stream := _wav_from_data(data, sample_rate)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	return stream

func _wav_from_data(data: PackedByteArray, sample_rate: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream
