extends RefCounted
class_name SfxGenerator
## Build-time SFX synthesis (AUDIO_BIBLE.md — "Neon Afterhours").
##
## Every sound is LAYERED per the bible: a transient (click/chirp), a tonal
## body with a real attack/decay envelope, and a filtered tail. Nothing is a
## naked sine. Comedy lives here — denied is a flat wrong-buzzer, player_death
## is a sad-trombone-shaped portamento womp, deploy_success is a slot machine
## paying out into a major chord — but token_collect plays hundreds of times a
## run, so the bread-and-butter sounds stay soft-spectrum and pleasant.
##
## Contract (validated numerically after generation, not vibes):
## mono 16-bit PCM 44100 Hz, sfx_<name>.wav, 0.05-1.2 s (stings <= 3 s),
## peak inside -6..-3 dBFS, |DC| < 0.001, 2-5 ms edge fades so nothing clicks.
## Deterministic: every sound owns a fixed RNG seed. No autoloads — this runs
## from run_generate.gd in SceneTree script mode where autoloads do not exist.

const SR := 44100
const OUT_DIR := "res://assets/audio/"
## -4.44 dBFS — the exact middle of the mandated -6..-3 peak window.
const TARGET_PEAK := 0.60

var _written: int = 0
var _failed: int = 0


func generate_all() -> void:
	var t_start: int = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save("token_collect", _gen_token_collect())
	_save("quest_complete", _gen_quest_complete())
	_save("upgrade", _gen_upgrade())
	_save("damage", _gen_damage())
	_save("coffee", _gen_coffee())
	_save("ui_click", _gen_ui_click())
	_save("ui_hover", _gen_ui_hover())
	_save("ability", _gen_ability())
	_save("enemy_death", _gen_enemy_death())
	for v: int in 4:
		_save("footstep_%d" % v, _gen_footstep(v))
	_save("dash", _gen_dash())
	_save("portal_enter", _gen_portal_enter())
	_save("dialogue_blip", _gen_dialogue_blip())
	_save("choice_select", _gen_choice_select())
	_save("projectile_shoot", _gen_projectile_shoot())
	_save("enemy_hit", _gen_enemy_hit())
	_save("player_death", _gen_player_death())
	_save("heal", _gen_heal())
	_save("purchase", _gen_purchase())
	_save("denied", _gen_denied())
	_save("achievement", _gen_achievement())
	_save("deploy_success", _gen_deploy_success())
	_save("boss_spawn", _gen_boss_spawn())
	_save("pickup_rare", _gen_pickup_rare())
	_save("menu_open", _gen_menu_open())
	_save("menu_close", _gen_menu_close())
	_save("typing", _gen_typing())
	print("[sfx_generator] %d SFX written, %d failed (%d ms)" % [
		_written, _failed, Time.get_ticks_msec() - t_start])


# --------------------------------------------------------------------------
# Synthesis toolkit
# --------------------------------------------------------------------------

func _buf(duration: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(round(duration * float(SR))))
	return b


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


## Tonal layer: exponential pitch glide f0 -> f1, attack ramp then exponential
## decay, summed harmonics with 1/h falloff (1 = sine, ~3 = mellow pluck,
## 5+ = saw-ish rasp), optional vibrato. Adds into buf starting at t0.
func _add_tone(buf: PackedFloat32Array, t0: float, dur: float, f0: float, f1: float,
		amp: float, attack: float, decay: float, harmonics: int = 1,
		vib_hz: float = 0.0, vib_depth: float = 0.0) -> void:
	var start: int = int(t0 * float(SR))
	var count: int = int(dur * float(SR))
	var phase: float = 0.0
	for i: int in count:
		var idx: int = start + i
		if idx >= buf.size():
			break
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var freq: float = f0 * pow(f1 / f0, u)
		if vib_depth > 0.0:
			freq *= 1.0 + vib_depth * sin(TAU * vib_hz * t)
		phase += TAU * freq / float(SR)
		var env: float = minf(t / maxf(attack, 0.0005), 1.0) * exp(-decay * t)
		env *= clampf((dur - t) / 0.004, 0.0, 1.0)
		var s: float = 0.0
		for h: int in harmonics:
			var hf: float = float(h + 1)
			s += sin(phase * hf) / hf
		buf[idx] += s * env * amp


## Noise layer: white noise through a one-pole low-pass whose cutoff sweeps
## lp0 -> lp1, optionally high-passed at hp. Same attack/decay envelope shape
## as _add_tone. Covers transient clicks (short + high hp), whooshes (swept
## cutoff), crunches (down-sweep) and sparkle tails (high hp, low amp).
func _add_noise(buf: PackedFloat32Array, rng: RandomNumberGenerator, t0: float,
		dur: float, amp: float, attack: float, decay: float, lp0: float,
		lp1: float, hp: float = 0.0) -> void:
	var start: int = int(t0 * float(SR))
	var count: int = int(dur * float(SR))
	var lp_y: float = 0.0
	var hp_y: float = 0.0
	var ah: float = 1.0 - exp(-TAU * hp / float(SR)) if hp > 0.0 else 0.0
	for i: int in count:
		var idx: int = start + i
		if idx >= buf.size():
			break
		var t: float = float(i) / float(SR)
		var u: float = t / dur
		var cutoff: float = lerpf(lp0, lp1, u)
		var a: float = 1.0 - exp(-TAU * cutoff / float(SR))
		var x: float = rng.randf_range(-1.0, 1.0)
		lp_y += a * (x - lp_y)
		var s: float = lp_y
		if hp > 0.0:
			hp_y += ah * (s - hp_y)
			s = s - hp_y
		var env: float = minf(t / maxf(attack, 0.0005), 1.0) * exp(-decay * t)
		env *= clampf((dur - t) / 0.004, 0.0, 1.0)
		buf[idx] += s * env * amp


## The sad-trombone engine. Frequency follows a keyframe table (times/freqs),
## so held notes and portamento slides live in one continuous phase — no
## re-articulation clicks between notes. Vibrato depth grows over the length
## of the phrase, and a sub-octave sine rides underneath for the "womp".
func _add_womp(buf: PackedFloat32Array, times: PackedFloat32Array,
		freqs: PackedFloat32Array, amp: float, harmonics: int, vib_hz: float,
		vib_max: float, sub_amp: float) -> void:
	var phase: float = 0.0
	var sub_phase: float = 0.0
	var total: float = times[times.size() - 1]
	var n: int = int(total * float(SR))
	for i: int in n:
		if i >= buf.size():
			break
		var t: float = float(i) / float(SR)
		var seg: int = 0
		while seg < times.size() - 2 and t > times[seg + 1]:
			seg += 1
		var span: float = maxf(times[seg + 1] - times[seg], 0.001)
		var u: float = (t - times[seg]) / span
		var freq: float = freqs[seg] + (freqs[seg + 1] - freqs[seg]) * u
		var vib: float = vib_max * (t / total)
		freq *= 1.0 + vib * sin(TAU * vib_hz * t)
		phase += TAU * freq / float(SR)
		sub_phase += TAU * freq * 0.5 / float(SR)
		var env: float = minf(t / 0.02, 1.0) * exp(-1.1 * t)
		env *= clampf((total - t) / 0.02, 0.0, 1.0)
		var s: float = 0.0
		for h: int in harmonics:
			var hf: float = float(h + 1)
			s += sin(phase * hf) / hf
		s += sin(sub_phase) * sub_amp
		buf[i] += s * env * amp


## Edge fades (no clicks), DC removal, then peak-normalize into the mandated
## window. Order matters: fading first keeps the edges at ~0, subtracting the
## mean before scaling keeps final DC at ~0 regardless of the gain applied.
func _finalize(buf: PackedFloat32Array, fade_in: float = 0.003,
		fade_out: float = 0.005) -> PackedFloat32Array:
	var n: int = buf.size()
	if n == 0:
		return buf
	var fi: int = mini(int(fade_in * float(SR)), n / 2)
	var fo: int = mini(int(fade_out * float(SR)), n / 2)
	for i: int in fi:
		buf[i] *= float(i) / float(fi)
	for i: int in fo:
		buf[n - 1 - i] *= float(i) / float(fo)
	var mean: float = 0.0
	for i: int in n:
		mean += buf[i]
	mean /= float(n)
	for i: int in n:
		buf[i] -= mean
	var peak: float = 0.0
	for i: int in n:
		peak = maxf(peak, absf(buf[i]))
	if peak > 0.0001:
		var g: float = TARGET_PEAK / peak
		for i: int in n:
			buf[i] *= g
	return buf


func _save(sfx_name: String, buf: PackedFloat32Array) -> void:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i: int in buf.size():
		var v: int = int(roundf(clampf(buf[i], -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SR
	stream.stereo = false
	stream.data = bytes
	var path: String = ProjectSettings.globalize_path(OUT_DIR + "sfx_%s.wav" % sfx_name)
	var err: Error = stream.save_to_wav(path)
	if err == OK:
		_written += 1
	else:
		_failed += 1
		push_error("[sfx_generator] failed to write %s (error %d)" % [path, err])


# --------------------------------------------------------------------------
# The 9 existing stream names (call sites depend on these — names are law)
# --------------------------------------------------------------------------

## The most-played sound in the game. Two consonant partials (E6 + B6, a
## fifth) with a B5 grace note, soft attack, nothing above the sparkle band —
## engineered to still be pleasant on the 50th pickup of a run.
func _gen_token_collect() -> PackedFloat32Array:
	var b := _buf(0.32)
	var rng := _rng(101)
	_add_noise(b, rng, 0.0, 0.004, 0.25, 0.0005, 300.0, 9000.0, 9000.0, 2500.0)
	_add_tone(b, 0.0, 0.035, 987.77, 987.77, 0.30, 0.002, 24.0, 2)
	_add_tone(b, 0.028, 0.28, 1318.51, 1318.51, 0.42, 0.003, 13.0, 2)
	_add_tone(b, 0.028, 0.24, 1975.53, 1975.53, 0.16, 0.003, 17.0, 1)
	_add_noise(b, rng, 0.04, 0.26, 0.10, 0.01, 13.0, 8000.0, 5000.0, 3200.0)
	return _finalize(b)


## Ascending C-major arpeggio into a held top note. Sincere, per the bible —
## the music plays it straight so the SFX jokes land elsewhere.
func _gen_quest_complete() -> PackedFloat32Array:
	var b := _buf(1.1)
	var rng := _rng(102)
	_add_noise(b, rng, 0.0, 0.003, 0.10, 0.0005, 300.0, 7000.0, 7000.0, 2500.0)
	var notes := PackedFloat32Array([523.25, 659.25, 783.99, 1046.5])
	for i: int in notes.size():
		_add_tone(b, float(i) * 0.09, 0.45, notes[i], notes[i], 0.30, 0.003, 7.0, 3)
	_add_tone(b, 0.27, 0.70, 1318.51, 1318.51, 0.12, 0.02, 3.5, 1)
	_add_noise(b, rng, 0.30, 0.70, 0.07, 0.05, 5.0, 8000.0, 4500.0, 3000.0)
	return _finalize(b)


## Octave power-up glide with a confirming blip on top.
func _gen_upgrade() -> PackedFloat32Array:
	var b := _buf(0.8)
	var rng := _rng(103)
	_add_noise(b, rng, 0.0, 0.003, 0.10, 0.0005, 300.0, 6000.0, 6000.0, 2200.0)
	_add_tone(b, 0.0, 0.35, 330.0, 660.0, 0.35, 0.004, 3.2, 4)
	_add_tone(b, 0.12, 0.30, 495.0, 990.0, 0.12, 0.01, 4.0, 2)
	_add_tone(b, 0.40, 0.25, 880.0, 880.0, 0.20, 0.004, 8.0, 2)
	_add_noise(b, rng, 0.35, 0.40, 0.07, 0.03, 6.0, 7000.0, 4000.0, 2800.0)
	return _finalize(b)


## Getting hit: low thump with a crunch on top. Short — it must never mask
## the information of the frame it lands in.
func _gen_damage() -> PackedFloat32Array:
	var b := _buf(0.25)
	var rng := _rng(104)
	_add_noise(b, rng, 0.0, 0.003, 0.15, 0.0005, 300.0, 5000.0, 5000.0, 2000.0)
	_add_tone(b, 0.0, 0.16, 190.0, 70.0, 0.50, 0.002, 16.0, 2)
	_add_noise(b, rng, 0.0, 0.12, 0.30, 0.002, 38.0, 3000.0, 300.0, 120.0)
	return _finalize(b)


## Percolator. Seven band-limited bubble blips over a low gurgle, one big
## bloop at the end, a wisp of steam. The joke is that it is acoustically
## sincere coffee.
func _gen_coffee() -> PackedFloat32Array:
	var b := _buf(1.0)
	var rng := _rng(105)
	_add_noise(b, rng, 0.0, 0.95, 0.20, 0.05, 2.2, 240.0, 180.0)
	var bt: float = 0.03
	for i: int in 7:
		var f0: float = rng.randf_range(260.0, 430.0)
		_add_tone(b, bt, rng.randf_range(0.05, 0.09), f0, f0 * rng.randf_range(2.1, 2.9),
			rng.randf_range(0.16, 0.30), 0.004, 26.0, 2)
		bt += rng.randf_range(0.09, 0.16)
	_add_tone(b, 0.82, 0.10, 300.0, 840.0, 0.34, 0.004, 22.0, 2)
	_add_noise(b, rng, 0.62, 0.36, 0.06, 0.08, 6.0, 5000.0, 6500.0, 2000.0)
	return _finalize(b)


func _gen_ui_click() -> PackedFloat32Array:
	var b := _buf(0.09)
	var rng := _rng(106)
	_add_noise(b, rng, 0.0, 0.003, 0.12, 0.0005, 200.0, 6000.0, 6000.0, 2500.0)
	_add_tone(b, 0.0, 0.06, 1900.0, 1900.0, 0.30, 0.002, 65.0, 2)
	_add_tone(b, 0.0, 0.04, 950.0, 950.0, 0.10, 0.002, 70.0, 1)
	return _finalize(b)


func _gen_ui_hover() -> PackedFloat32Array:
	var b := _buf(0.07)
	var rng := _rng(107)
	_add_noise(b, rng, 0.0, 0.005, 0.10, 0.001, 200.0, 6000.0, 6000.0, 2000.0)
	_add_tone(b, 0.0, 0.055, 1396.9, 1396.9, 0.30, 0.004, 55.0, 2)
	return _finalize(b)


## Rising saw-ish zap with a shimmer octave and an air whoosh underneath.
func _gen_ability() -> PackedFloat32Array:
	var b := _buf(0.5)
	var rng := _rng(108)
	_add_noise(b, rng, 0.0, 0.002, 0.12, 0.0005, 300.0, 6000.0, 6000.0, 2500.0)
	_add_tone(b, 0.0, 0.30, 240.0, 960.0, 0.32, 0.01, 5.0, 5)
	_add_tone(b, 0.0, 0.30, 480.0, 1920.0, 0.10, 0.01, 6.0, 1, 30.0, 0.01)
	_add_noise(b, rng, 0.0, 0.45, 0.14, 0.06, 6.0, 600.0, 2600.0, 300.0)
	return _finalize(b)


## A crunchy fall to the floor plus a high fizz — the audio half of the
## dissolve shader.
func _gen_enemy_death() -> PackedFloat32Array:
	var b := _buf(0.55)
	var rng := _rng(109)
	_add_tone(b, 0.0, 0.42, 420.0, 70.0, 0.40, 0.003, 6.0, 6)
	_add_tone(b, 0.0, 0.30, 100.0, 48.0, 0.30, 0.003, 8.0, 1)
	_add_noise(b, rng, 0.0, 0.35, 0.22, 0.002, 12.0, 2500.0, 200.0)
	_add_noise(b, rng, 0.15, 0.40, 0.08, 0.03, 8.0, 6000.0, 3000.0, 2500.0)
	return _finalize(b)


# --------------------------------------------------------------------------
# New stream names (AUDIO_BIBLE round-4 list)
# --------------------------------------------------------------------------

## Four distinct soft variants: low body thud + a swept scuff + a tiny heel
## click, each with its own tuning so alternation never machine-guns.
func _gen_footstep(variant: int) -> PackedFloat32Array:
	var b := _buf(0.14)
	var rng := _rng(9000 + variant)
	var body := PackedFloat32Array([162.0, 149.0, 178.0, 155.0])
	var scuff := PackedFloat32Array([850.0, 700.0, 980.0, 760.0])
	_add_tone(b, 0.0, 0.09, body[variant], body[variant] * 0.62, 0.40, 0.002, 34.0, 2)
	_add_noise(b, rng, 0.0, 0.11, 0.22, 0.002, 30.0, scuff[variant], 280.0, 150.0)
	_add_noise(b, rng, 0.0, 0.02, 0.10, 0.0008, 140.0, 3000.0, 2000.0, 900.0)
	return _finalize(b)


## Two crossing whooshes — up then down — with a faint airy tone inside.
func _gen_dash() -> PackedFloat32Array:
	var b := _buf(0.32)
	var rng := _rng(114)
	_add_noise(b, rng, 0.0, 0.20, 0.30, 0.07, 6.0, 450.0, 2400.0, 250.0)
	_add_noise(b, rng, 0.14, 0.18, 0.22, 0.02, 12.0, 2400.0, 600.0, 250.0)
	_add_tone(b, 0.0, 0.25, 300.0, 520.0, 0.08, 0.05, 8.0, 2)
	return _finalize(b)


## Low whoomp, detuned rising shimmer pair, sparkle, and an arrival bell.
func _gen_portal_enter() -> PackedFloat32Array:
	var b := _buf(1.15)
	var rng := _rng(115)
	_add_tone(b, 0.0, 0.30, 150.0, 55.0, 0.40, 0.01, 6.0, 3)
	_add_tone(b, 0.10, 1.00, 280.0, 860.0, 0.20, 0.15, 1.8, 2, 6.0, 0.008)
	_add_tone(b, 0.10, 1.00, 283.0, 873.0, 0.16, 0.15, 1.8, 2, 6.0, 0.008)
	_add_noise(b, rng, 0.30, 0.80, 0.07, 0.20, 2.5, 5000.0, 9000.0, 2800.0)
	_add_tone(b, 0.95, 0.18, 1046.5, 1046.5, 0.15, 0.005, 10.0, 2)
	return _finalize(b)


## Typewriter-voice blip for dialogue reveal. Mellow — it repeats per line.
func _gen_dialogue_blip() -> PackedFloat32Array:
	var b := _buf(0.06)
	var rng := _rng(116)
	_add_noise(b, rng, 0.0, 0.002, 0.08, 0.0005, 300.0, 5000.0, 5000.0, 2000.0)
	_add_tone(b, 0.0, 0.05, 660.0, 660.0, 0.35, 0.003, 45.0, 3)
	return _finalize(b)


## Affirmative two-step blip a fifth up. Distinct from ui_click by contour.
func _gen_choice_select() -> PackedFloat32Array:
	var b := _buf(0.16)
	var rng := _rng(117)
	_add_noise(b, rng, 0.0, 0.002, 0.10, 0.0005, 300.0, 6000.0, 6000.0, 2500.0)
	_add_tone(b, 0.0, 0.06, 740.0, 740.0, 0.30, 0.003, 30.0, 2)
	_add_tone(b, 0.055, 0.10, 1108.7, 1108.7, 0.34, 0.003, 22.0, 2)
	_add_noise(b, rng, 0.06, 0.09, 0.05, 0.01, 20.0, 7000.0, 5000.0, 3000.0)
	return _finalize(b)


## Pew: fast falling sweep with a sub-partial and a bright attack click.
func _gen_projectile_shoot() -> PackedFloat32Array:
	var b := _buf(0.22)
	var rng := _rng(118)
	_add_noise(b, rng, 0.0, 0.003, 0.15, 0.0005, 300.0, 7000.0, 7000.0, 3500.0)
	_add_tone(b, 0.0, 0.15, 1500.0, 350.0, 0.40, 0.002, 14.0, 3)
	_add_tone(b, 0.0, 0.15, 750.0, 175.0, 0.15, 0.002, 14.0, 1)
	_add_noise(b, rng, 0.0, 0.12, 0.08, 0.002, 25.0, 4000.0, 800.0, 500.0)
	return _finalize(b)


## Landing a hit: brighter and shorter than taking one (see _gen_damage).
func _gen_enemy_hit() -> PackedFloat32Array:
	var b := _buf(0.16)
	var rng := _rng(119)
	_add_noise(b, rng, 0.0, 0.002, 0.12, 0.0005, 300.0, 6000.0, 6000.0, 2500.0)
	_add_tone(b, 0.0, 0.09, 260.0, 120.0, 0.45, 0.002, 30.0, 3)
	_add_noise(b, rng, 0.0, 0.10, 0.28, 0.002, 40.0, 1800.0, 400.0, 250.0)
	return _finalize(b)


## The descending portamento womp (COMEDY_BIBLE: Ctrl+Z, but for your whole
## body). Sad-trombone keyframes D4 - C#4 - C4 - B3, the last note drooping
## to A3 with vibrato that grows the longer it feels sorry for you.
func _gen_player_death() -> PackedFloat32Array:
	var b := _buf(1.9)
	var rng := _rng(120)
	var times := PackedFloat32Array([0.0, 0.26, 0.36, 0.60, 0.70, 0.94, 1.04, 1.86])
	var freqs := PackedFloat32Array([293.66, 293.66, 277.18, 277.18, 261.63, 261.63, 246.94, 220.0])
	_add_womp(b, times, freqs, 0.40, 5, 5.5, 0.03, 0.5)
	_add_noise(b, rng, 0.0, 1.80, 0.045, 0.30, 1.6, 900.0, 400.0)
	return _finalize(b)


## Warm staggered major-triad partials with slow attacks — the one gentle
## sound in the kit.
func _gen_heal() -> PackedFloat32Array:
	var b := _buf(0.6)
	var rng := _rng(121)
	_add_tone(b, 0.0, 0.50, 523.25, 523.25, 0.22, 0.03, 5.0, 1)
	_add_tone(b, 0.08, 0.45, 659.25, 659.25, 0.20, 0.03, 5.0, 1)
	_add_tone(b, 0.16, 0.42, 783.99, 783.99, 0.18, 0.03, 5.0, 1)
	_add_tone(b, 0.20, 0.35, 1046.5, 1046.5, 0.08, 0.05, 6.0, 1, 5.0, 0.008)
	_add_tone(b, 0.0, 0.50, 261.63, 261.63, 0.10, 0.04, 4.0, 1)
	_add_noise(b, rng, 0.15, 0.40, 0.05, 0.10, 5.0, 6000.0, 8000.0, 3000.0)
	return _finalize(b)


## Cash register: a low kerchunk, then a bell dyad. Tokens leave, sound stays.
func _gen_purchase() -> PackedFloat32Array:
	var b := _buf(0.45)
	var rng := _rng(122)
	_add_noise(b, rng, 0.0, 0.05, 0.30, 0.001, 50.0, 600.0, 250.0, 80.0)
	_add_tone(b, 0.0, 0.05, 200.0, 120.0, 0.25, 0.002, 40.0, 2)
	_add_noise(b, rng, 0.065, 0.003, 0.10, 0.0005, 300.0, 6000.0, 6000.0, 3000.0)
	_add_tone(b, 0.07, 0.32, 1174.66, 1174.66, 0.32, 0.003, 9.0, 2)
	_add_tone(b, 0.07, 0.28, 1760.0, 1760.0, 0.14, 0.003, 12.0, 1)
	_add_noise(b, rng, 0.10, 0.30, 0.06, 0.02, 10.0, 8000.0, 5000.0, 3200.0)
	return _finalize(b)


## The flat wrong-buzzer. Two low saws a sour ~semitone apart beating at ~5.5 Hz,
## zero pitch movement, and it just stops. The absence of drama IS the joke.
func _gen_denied() -> PackedFloat32Array:
	var b := _buf(0.45)
	var rng := _rng(123)
	_add_tone(b, 0.0, 0.42, 106.5, 106.5, 0.34, 0.006, 0.5, 7)
	_add_tone(b, 0.0, 0.42, 112.0, 112.0, 0.34, 0.006, 0.5, 7)
	_add_noise(b, rng, 0.0, 0.42, 0.05, 0.006, 0.5, 900.0, 900.0, 350.0)
	return _finalize(b)


## Sting: three-note fanfare into a held major third with octave shimmer —
## quest_complete's grander sibling.
func _gen_achievement() -> PackedFloat32Array:
	var b := _buf(1.6)
	var rng := _rng(124)
	_add_noise(b, rng, 0.0, 0.003, 0.10, 0.0005, 300.0, 7000.0, 7000.0, 2500.0)
	var notes := PackedFloat32Array([523.25, 659.25, 783.99])
	for i: int in notes.size():
		_add_tone(b, float(i) * 0.13, 0.16, notes[i], notes[i], 0.28, 0.004, 9.0, 3)
	_add_tone(b, 0.39, 1.10, 1046.5, 1046.5, 0.30, 0.008, 2.6, 3)
	_add_tone(b, 0.39, 1.00, 1318.51, 1318.51, 0.14, 0.008, 3.0, 2)
	_add_tone(b, 0.45, 0.80, 2093.0, 2093.0, 0.07, 0.02, 3.5, 1, 5.5, 0.006)
	_add_noise(b, rng, 0.40, 1.00, 0.07, 0.05, 3.0, 8000.0, 4500.0, 3000.0)
	return _finalize(b)


## Sting: the slot machine pays out — fourteen accelerating coin ticks
## climbing the last 6% sharp, then the whole C-major chord lands with
## shimmer. You shipped. The machine is as surprised as you are.
func _gen_deploy_success() -> PackedFloat32Array:
	var b := _buf(2.7)
	var rng := _rng(125)
	var notes := PackedFloat32Array([523.25, 659.25, 783.99, 1046.5])
	var t0: float = 0.02
	for i: int in 14:
		var f: float = notes[i % 4] * (1.0 + 0.06 * (float(i) / 13.0))
		_add_tone(b, t0, 0.14, f, f, 0.24, 0.002, 20.0, 2)
		_add_tone(b, t0, 0.12, f * 1.5, f * 1.5, 0.09, 0.002, 24.0, 1)
		# Gap shrinks 130ms -> 77ms so the payout audibly accelerates into
		# the chord (last tick ends ~1.53s, chord lands at 1.55s).
		t0 += lerpf(0.13, 0.077, float(i) / 13.0)
	var chord := PackedFloat32Array([261.63, 329.63, 392.0, 523.25, 659.25])
	for f: float in chord:
		_add_tone(b, 1.55, 1.10, f, f, 0.22, 0.02, 2.4, 4)
	_add_noise(b, rng, 1.55, 1.00, 0.08, 0.02, 4.0, 7000.0, 4000.0, 3000.0)
	_add_tone(b, 1.55, 0.90, 1046.5, 1046.5, 0.10, 0.02, 4.0, 1)
	return _finalize(b)


## Sting: beating low drones swell under a rising noise bed, then the impact.
## Scope Creep has entered the building.
func _gen_boss_spawn() -> PackedFloat32Array:
	var b := _buf(2.0)
	var rng := _rng(126)
	_add_tone(b, 0.0, 1.50, 55.0, 55.0, 0.30, 0.90, 0.3, 4)
	_add_tone(b, 0.0, 1.50, 58.3, 58.3, 0.26, 0.90, 0.3, 4)
	_add_noise(b, rng, 0.0, 1.45, 0.14, 1.20, 0.2, 200.0, 1400.0)
	_add_tone(b, 1.45, 0.50, 70.0, 40.0, 0.55, 0.003, 6.0, 3)
	_add_noise(b, rng, 1.45, 0.40, 0.30, 0.002, 14.0, 2600.0, 300.0)
	return _finalize(b)


## token_collect's magical sibling: a five-note glissando up into a bell
## chord with a long sparkle. Rare should FEEL rare.
func _gen_pickup_rare() -> PackedFloat32Array:
	var b := _buf(0.9)
	var rng := _rng(127)
	_add_noise(b, rng, 0.0, 0.003, 0.10, 0.0005, 300.0, 8000.0, 8000.0, 3000.0)
	var gliss := PackedFloat32Array([523.25, 659.25, 783.99, 1046.5, 1318.51])
	for i: int in gliss.size():
		_add_tone(b, float(i) * 0.055, 0.09, gliss[i], gliss[i], 0.22, 0.003, 20.0, 2)
	_add_tone(b, 0.28, 0.60, 1046.5, 1046.5, 0.30, 0.004, 4.5, 2)
	_add_tone(b, 0.28, 0.55, 1318.51, 1318.51, 0.20, 0.004, 5.0, 2)
	_add_tone(b, 0.28, 0.50, 1567.98, 1567.98, 0.12, 0.004, 5.5, 1)
	_add_noise(b, rng, 0.30, 0.55, 0.08, 0.05, 4.0, 9000.0, 5000.0, 3500.0)
	return _finalize(b)


func _gen_menu_open() -> PackedFloat32Array:
	var b := _buf(0.2)
	var rng := _rng(128)
	_add_noise(b, rng, 0.0, 0.16, 0.25, 0.04, 10.0, 500.0, 2400.0, 300.0)
	_add_tone(b, 0.02, 0.12, 520.0, 780.0, 0.22, 0.008, 16.0, 2)
	return _finalize(b)


## menu_open played backwards, conceptually: swish and blip both fall.
func _gen_menu_close() -> PackedFloat32Array:
	var b := _buf(0.2)
	var rng := _rng(129)
	_add_noise(b, rng, 0.0, 0.16, 0.25, 0.03, 12.0, 2400.0, 500.0, 300.0)
	_add_tone(b, 0.02, 0.12, 780.0, 520.0, 0.22, 0.008, 16.0, 2)
	return _finalize(b)


## One soft mechanical key: band-passed click, low thock, tiny tick. Quiet —
## the vibe coder types a lot and the player is in the room with them.
func _gen_typing() -> PackedFloat32Array:
	var b := _buf(0.07)
	var rng := _rng(130)
	_add_noise(b, rng, 0.0, 0.006, 0.30, 0.0005, 160.0, 5500.0, 5500.0, 1600.0)
	_add_tone(b, 0.0, 0.04, 190.0, 190.0, 0.25, 0.001, 90.0, 2)
	_add_tone(b, 0.0, 0.025, 1400.0, 1400.0, 0.12, 0.001, 120.0, 1)
	return _finalize(b)
