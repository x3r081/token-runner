extends Node
## Procedural and placeholder audio management.

var music_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
const MAX_SFX := 12

var master_vol: float = 1.0
var music_vol: float = 0.7
var sfx_vol: float = 0.8

var _streams: Dictionary = {}

func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Master"
	add_child(music_player)
	for i in MAX_SFX:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		sfx_players.append(p)
	_generate_procedural_audio()

func _generate_procedural_audio() -> void:
	_streams["token_collect"] = _make_tone(880.0, 0.08, 0.3)
	_streams["quest_complete"] = _make_chord([523.25, 659.25, 783.99], 0.4, 0.25)
	_streams["upgrade"] = _make_chord([392.0, 493.88, 587.33, 739.99], 0.5, 0.3)
	_streams["damage"] = _make_noise_burst(0.15, 0.4)
	_streams["coffee"] = _make_tone(220.0, 0.2, 0.2)
	_streams["ui_click"] = _make_tone(1200.0, 0.04, 0.15)
	_streams["ui_hover"] = _make_tone(600.0, 0.03, 0.08)
	_streams["ability"] = _make_tone(440.0, 0.12, 0.25)
	_streams["enemy_death"] = _make_chord([200.0, 150.0], 0.3, 0.3)
	_streams["explore_music"] = _make_ambient_loop(90.0, 4.0)
	_streams["combat_music"] = _make_ambient_loop(120.0, 3.0)
	_streams["menu_music"] = _make_ambient_loop(60.0, 6.0)

func play_sfx(name: String) -> void:
	if not _streams.has(name):
		return
	for p in sfx_players:
		if not p.playing:
			p.stream = _streams[name]
			p.volume_db = linear_to_db(sfx_vol * master_vol)
			p.play()
			return

func play_music(name: String, fade: float = 0.5) -> void:
	if not _streams.has(name):
		return
	if music_player.stream == _streams[name] and music_player.playing:
		return
	music_player.stream = _streams[name]
	music_player.volume_db = linear_to_db(music_vol * master_vol)
	music_player.play()

func stop_music() -> void:
	music_player.stop()

func set_volumes(master: float, music: float, sfx: float) -> void:
	master_vol = master
	music_vol = music
	sfx_vol = sfx
	music_player.volume_db = linear_to_db(music_vol * master_vol)

func _make_tone(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(count)
	for i in count:
		var t := float(i) / sample_rate
		var env := 1.0 - float(i) / count
		var sample := sin(TAU * freq * t) * env * volume
		data[i] = int(clamp((sample * 0.5 + 0.5) * 255, 0, 255))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream

func _make_chord(freqs: Array, duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(count)
	for i in count:
		var t := float(i) / sample_rate
		var env := 1.0 - float(i) / count
		var sample := 0.0
		for f in freqs:
			sample += sin(TAU * float(f) * t)
		sample = sample / freqs.size() * env * volume
		data[i] = int(clamp((sample * 0.5 + 0.5) * 255, 0, 255))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream

func _make_noise_burst(duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(count)
	var rng := RandomNumberGenerator.new()
	for i in count:
		var env := 1.0 - float(i) / count
		var sample := rng.randf_range(-1.0, 1.0) * env * volume
		data[i] = int(clamp((sample * 0.5 + 0.5) * 255, 0, 255))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream

func _make_ambient_loop(base_freq: float, duration: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(count)
	for i in count:
		var t := float(i) / sample_rate
		var sample := (
			sin(TAU * base_freq * t) * 0.3
			+ sin(TAU * base_freq * 1.5 * t) * 0.15
			+ sin(TAU * base_freq * 0.5 * t) * 0.2
		) * 0.25
		data[i] = int(clamp((sample * 0.5 + 0.5) * 255, 0, 255))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	stream.data = data
	return stream
