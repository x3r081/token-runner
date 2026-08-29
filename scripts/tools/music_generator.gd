extends RefCounted
class_name MusicGenerator
## Build-time musical score for Token Runner (AUDIO_BIBLE.md, "Neon Afterhours").
##
## Five music tracks (stereo) and four ambience beds (mono), synthesized as real
## music: chord progressions, basslines, drum patterns and a leitmotif that the
## menu owns and explore/victory quote. Invoked by run_generate.gd in SceneTree
## script mode — no autoloads may be touched here.
##
## Engineering law (validated numerically after generation):
## - 44100 Hz 16-bit PCM via AudioStreamWAV.save_to_wav().
## - Loop-exact: total samples = bars * 4 * samples_per_beat, all note tails and
##   echoes wrap modulo the loop length, every sustained oscillator is quantized
##   to an integer number of cycles per loop, and a final seam ramp makes
##   |last - first| == 0 before quantization.
## - Peak <= -3 dBFS (tanh ceiling at -4.4), music RMS -20..-14 dBFS, ambience
##   RMS -30..-22 dBFS, |DC| < 0.001. All RNG is seeded — output is reproducible.
##
## The composition was prototyped and listen-checked numerically (loop seams,
## spectra, RMS, clipping) before being ported here 1:1.

const SR := 44100
const TS := 4096                # wavetable size
const TS_MASK := 4095
const EDGE := 128               # smoothed waveform edges — loop-seam friendly
const NOISE_N := 131072
const OUT_DIR := "res://assets/audio/"

## The Token Runner leitmotif (A minor, 2 bars). Flat [beat, midi, dur] triples.
## The menu states it; explore and victory quote it.
const MOTIF: Array = [
	0.0, 69, 1.0, 1.0, 72, 0.5, 1.5, 74, 0.5, 2.0, 76, 1.5,
	3.5, 74, 0.5, 4.0, 72, 1.0, 5.0, 71, 1.0, 6.0, 69, 1.75,
]
## Diatonic thirds below the motif, for the harmonized quotes.
const MOTIF_HARM: Array = [65, 69, 71, 72, 71, 69, 67, 65]

## 303-ish 16-step patterns: semitone offset from the bar root, -1 = rest.
const ACID_PAT: Array = [0, 0, 12, 0, 0, -1, 0, 12, 0, 0, 3, 0, 12, -1, 0, 3]
const ACID_ACC: Array = [0, 4, 10, 12]
const BOSS_PAT: Array = [0, 0, 0, 12, 0, -1, 0, 0, 12, 0, 0, 1, 0, -1, 12, 1]
const BOSS_ACC: Array = [0, 3, 8, 12]

## Cricket chirps for ambient_outdoor: [start_sec, amp] pairs (seeded, fixed).
const CRICKETS: Array = [
	9.982, 0.0642, 15.509, 0.0632, 5.938, 0.0605, 5.028, 0.0657,
	3.665, 0.0855, 11.756, 0.0617, 3.783, 0.0649, 4.536, 0.0615,
	20.886, 0.0846, 12.809, 0.0687, 10.016, 0.0844, 4.038, 0.0564,
	21.021, 0.0537, 4.775, 0.0512,
]

var _saw: PackedFloat32Array
var _pulse: PackedFloat32Array
var _p25: PackedFloat32Array
var _tri: PackedFloat32Array
var _sine: PackedFloat32Array
var _noise: PackedFloat32Array

var _bl: PackedFloat32Array     # left (and the only channel when mono)
var _br: PackedFloat32Array
var _scr: PackedFloat32Array    # per-note scratch buffer, reused
var _scr2: PackedFloat32Array
var _n: int = 0                 # loop length in frames
var _stereo := true
var _noise_pos := 0


func generate_all() -> void:
	if not _packed_arrays_by_ref():
		push_error("MusicGenerator: packed arrays are not by-ref here; refusing to emit silent WAVs.")
		return
	var t0 := Time.get_ticks_msec()
	_build_tables()
	_make_menu()
	_make_explore()
	_make_combat()
	_make_boss()
	_make_victory()
	_make_amb_interior()
	_make_amb_industrial()
	_make_amb_outdoor()
	_make_amb_ethereal()
	print("Music generated in %d ms." % (Time.get_ticks_msec() - t0))


## Every helper mutates member buffers through parameters/aliases, which relies
## on Godot 4.1+ pass-by-reference packed arrays — both across function calls
## and through Array elements (_finalize iterates [_bl, _br]). Fail loudly if
## that ever changes instead of writing nine wrong files.
func _packed_arrays_by_ref() -> bool:
	var probe := PackedFloat32Array([0.0])
	_poke(probe)
	if probe[0] != 1.0:
		return false
	var holder: Array = [probe]
	var alias: PackedFloat32Array = holder[0]
	alias[0] = 2.0
	return probe[0] == 2.0


func _poke(p: PackedFloat32Array) -> void:
	p[0] = 1.0


# ---------------------------------------------------------------- wavetables

## Band-limited-ish single-cycle tables. Sharp saw/pulse edges are replaced by
## short linear ramps (EDGE/TS of a cycle) — less alias grit, and a wrap that
## cannot click at the loop seam.
func _build_tables() -> void:
	var e := float(EDGE) / float(TS)
	_saw.resize(TS)
	_pulse.resize(TS)
	_p25.resize(TS)
	_tri.resize(TS)
	_sine.resize(TS)
	for i in TS:
		var ph := float(i) / float(TS)
		if ph < 1.0 - e:
			_saw[i] = -1.0 + 2.0 * ph / (1.0 - e)
		else:
			_saw[i] = 1.0 - 2.0 * (ph - (1.0 - e)) / e
		if ph < e:
			_pulse[i] = -1.0 + 2.0 * ph / e
		elif ph < 0.5:
			_pulse[i] = 1.0
		elif ph < 0.5 + e:
			_pulse[i] = 1.0 - 2.0 * (ph - 0.5) / e
		else:
			_pulse[i] = -1.0
		var v25: float
		if ph < e:
			v25 = -1.0 + 2.0 * ph / e
		elif ph < 0.25:
			v25 = 1.0
		elif ph < 0.25 + e:
			v25 = 1.0 - 2.0 * (ph - 0.25) / e
		else:
			v25 = -1.0
		_p25[i] = v25 + 0.5    # remove the 25%-duty DC offset
		_tri[i] = 4.0 * ph - 1.0 if ph < 0.5 else 3.0 - 4.0 * ph
		_sine[i] = sin(TAU * ph)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	_noise.resize(NOISE_N)
	for i in NOISE_N:
		_noise[i] = rng.randf_range(-1.0, 1.0)


func _midi_hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


## Built-in tanh saturates cleanly at extreme inputs; the exp-based identity
## overflows to NaN past |x| ~ 355 (numpy's tanh, which the prototype used,
## saturates — this keeps the port's behavior identical at every input).
func _tanh(x: float) -> float:
	return tanh(x)


# ---------------------------------------------------------------- engine

func _begin(frames: int, stereo: bool, noise_seed: int) -> void:
	_n = frames
	_stereo = stereo
	_bl.resize(frames)
	_bl.fill(0.0)
	if stereo:
		_br.resize(frames)
		_br.fill(0.0)
	else:
		_br.resize(0)
	_noise_pos = (noise_seed * 7919) % NOISE_N


## Add the scratch buffer into the master, wrapping modulo the loop length.
## This wrap is what makes release tails and echoes loop-exact.
func _scr_mix(start: int, gl: float, gr: float) -> void:
	var m := _scr.size()
	var s := start % _n
	var done := 0
	while done < m:
		var k := mini(m - done, _n - s)
		if _stereo:
			for i in k:
				_bl[s + i] += _scr[done + i] * gl
				_br[s + i] += _scr[done + i] * gr
		else:
			for i in k:
				_bl[s + i] += _scr[done + i] * gl
		done += k
		s = 0


## Add one oscillator into the scratch. Frequency is quantized to an integer
## number of cycles per LOOP (granularity SR/_n < 0.03 Hz — inaudible), so any
## voice sustaining across the seam returns to its start phase exactly.
func _scr_osc(table: PackedFloat32Array, freq: float, phase0: float) -> void:
	var cycles := maxf(1.0, roundf(freq * float(_n) / float(SR)))
	var inc := cycles * float(TS) / float(_n)
	var ph := phase0 * float(TS)
	var n := _scr.size()
	for i in n:
		_scr[i] += table[int(ph) & TS_MASK]
		ph += inc


## Linear attack ramp + linear release over the final rel samples.
func _scr_env_ar(att: int, rel: int) -> void:
	var n := _scr.size()
	var a := mini(att, n)
	if a > 0:
		for i in a:
			_scr[i] *= float(i) / float(a)
	var r := mini(rel, n)
	if r > 0:
		for i in r:
			_scr[n - r + i] *= 1.0 - float(i) / float(r)


## One-pole lowpass over the scratch. laps=2 runs the filter around the buffer
## twice with carried state — the circular steady state, for seamless beds.
func _scr_lp(fc: float, laps: int = 1) -> void:
	var a := 1.0 - exp(-TAU * fc / float(SR))
	var y := 0.0
	var n := _scr.size()
	for _lap in laps:
		for i in n:
			y += a * (_scr[i] - y)
			_scr[i] = y


## Generic melodic note: nosc detuned oscillators -> AR env -> lowpass -> mix.
## The scratch keeps the finished note afterwards so echoes can re-mix it.
func _tone_note(table: PackedFloat32Array, phase0: float, start: int, body: int,
		rel: int, freq: float, amp: float, lp: float, att: float, pan: float,
		det_cents: float = 0.0, nosc: int = 1) -> void:
	var n := body + rel
	_scr.resize(n)
	_scr.fill(0.0)
	if nosc <= 1:
		_scr_osc(table, freq, phase0)
	else:
		for o in nosc:
			var spread := float(o) / float(nosc - 1) * 2.0 - 1.0
			_scr_osc(table, freq * pow(2.0, spread * det_cents / 1200.0), phase0)
		var inv := 1.0 / float(nosc)
		for i in n:
			_scr[i] *= inv
	_scr_env_ar(int(att * SR), rel)
	_scr_lp(lp)
	var pa := (pan + 1.0) * 0.25 * PI
	_scr_mix(start, amp * cos(pa), amp * sin(pa))


## Two decaying repeats of whatever note is sitting in the scratch, the first
## on the opposite side of the field. Wraps modulo the loop like everything.
func _echo(start: int, amp: float, pan: float, d: int, g1: float = 0.42,
		g2: float = 0.18) -> void:
	var pa := (-pan + 1.0) * 0.25 * PI
	_scr_mix(start + d, amp * g1 * cos(pa), amp * g1 * sin(pa))
	pa = (pan + 1.0) * 0.25 * PI
	_scr_mix(start + 2 * d, amp * g2 * cos(pa), amp * g2 * sin(pa))


## A melodic line of flat [beat, midi, dur_beats] triples.
func _play_line(line: Array, start_beat: float, spb: int, amp: float,
		table: PackedFloat32Array, lp: float, att: float, rel: float,
		pan: float, echo_beats: float, transpose: int = 0) -> void:
	for i in range(0, line.size(), 3):
		var b := float(line[i])
		var m := float(line[i + 1]) + float(transpose)
		var d := float(line[i + 2])
		var st := int(round((start_beat + b) * float(spb)))
		var body := int(d * float(spb) * 0.92)
		_tone_note(table, 0.25, st, body, int(rel * SR), _midi_hz(m), amp, lp,
				att, pan)
		if echo_beats > 0.0:
			_echo(st, amp, pan, int(echo_beats * float(spb)))


## Supersaw pad chord: every chord tone is 3 detuned saws spread across the
## field. Width comes from detune + pan, never phase tricks (mono-safe).
func _pad_chord(notes: Array, start: int, body: int, amp: float,
		lp: float = 1300.0, att: float = 0.9, rel: float = 1.4,
		det: float = 7.0) -> void:
	var pans: Array = [-0.5, 0.5, -0.25, 0.25]
	for i in notes.size():
		var pan: float = pans[i % 4]
		_tone_note(_saw, 0.5, start, body, int(rel * SR),
				_midi_hz(float(notes[i])), amp, lp, att, pan, det, 3)


func _sub_note(start: int, body: int, midi: int, amp: float,
		rel: float = 0.25) -> void:
	_tone_note(_sine, 0.25, start, body, int(rel * SR), _midi_hz(float(midi)),
			amp, 200.0, 0.04, 0.0)


# ---------------------------------------------------------------- drum kit

## Kick: pitch-swept sine (160 -> 46 Hz) + highpassed noise click.
func _kick(start: int, amp: float, dur: float = 0.30) -> void:
	var n := int(dur * SR)
	_scr.resize(n)
	var d := 1.0
	var dm := exp(-1.0 / (0.045 * SR))
	var e := 1.0
	var em := exp(-1.0 / (0.12 * SR))
	var ph := 0.0
	for i in n:
		ph += (46.0 + 114.0 * d) / float(SR)
		d *= dm
		_scr[i] = sin(TAU * ph) * e
		e *= em
	for i in 24:
		_scr[i] *= float(i) / 24.0
	var c := int(0.004 * SR)
	var npos := _noise_pos
	var prev := 0.0
	for i in c:
		var v := _noise[npos]
		npos += 1
		if npos == NOISE_N:
			npos = 0
		_scr[i] += (v - prev) * 0.8 * (1.0 - float(i) / float(c - 1))
		prev = v
	_noise_pos = npos
	_scr_mix(start, amp * 0.5, amp * 0.5)


## Snare: highpassed noise burst + 185 Hz enveloped body.
func _snare(start: int, amp: float, dur: float = 0.22,
		body_hz: float = 185.0) -> void:
	var n := int(dur * SR)
	_scr.resize(n)
	var e1 := 1.0
	var em1 := exp(-1.0 / (0.06 * SR))
	var e2 := 1.0
	var em2 := exp(-1.0 / (0.05 * SR))
	var npos := _noise_pos
	var prev := 0.0
	for i in n:
		var v := _noise[npos]
		npos += 1
		if npos == NOISE_N:
			npos = 0
		_scr[i] = (v - prev) * 2.2 * e1 \
				+ sin(TAU * body_hz * float(i) / float(SR)) * e2 * 0.8
		prev = v
		e1 *= em1
		e2 *= em2
	_noise_pos = npos
	for i in 20:
		_scr[i] *= float(i) / 20.0
	_scr_mix(start, amp * 0.5, amp * 0.5)


## Hat: short highpassed noise tick.
func _hat(start: int, amp: float, dur: float = 0.05,
		pan: float = 0.15) -> void:
	var n := int(dur * SR)
	_scr.resize(n)
	var e := 1.0
	var em := exp(-1.0 / (dur * 0.35 * SR))
	var npos := _noise_pos
	var prev := 0.0
	for i in n:
		var v := _noise[npos]
		npos += 1
		if npos == NOISE_N:
			npos = 0
		_scr[i] = (v - prev) * 2.5 * e
		prev = v
		e *= em
	_noise_pos = npos
	for i in 12:
		_scr[i] *= float(i) / 12.0
	var pa := (pan + 1.0) * 0.25 * PI
	_scr_mix(start, amp * cos(pa), amp * sin(pa))


## Crash-ish noise splash for section turnarounds.
func _crash(start: int, amp: float, dur: float = 1.2) -> void:
	var n := int(dur * SR)
	_scr.resize(n)
	var e := 1.0
	var em := exp(-1.0 / (dur * 0.3 * SR))
	var npos := _noise_pos
	var prev := 0.0
	for i in n:
		var v := _noise[npos]
		npos += 1
		if npos == NOISE_N:
			npos = 0
		_scr[i] = (v - prev) * 2.0 * e
		prev = v
		e *= em
	_noise_pos = npos
	var a := int(0.002 * SR)
	for i in a:
		_scr[i] *= float(i) / float(a)
	_scr_mix(start, amp * 0.55, amp * 0.45)


## 303-ish acid note: saw -> resonant SVF with a decaying cutoff envelope,
## mild tanh drive. Accents open the filter wider.
func _acid(start: int, gate: int, freq: float, amp: float, fc_peak: float,
		q: float, pan: float = 0.0) -> void:
	_scr.resize(gate)
	_scr.fill(0.0)
	_scr_osc(_saw, freq, 0.5)
	_scr_env_ar(16, int(0.012 * SR))
	var fbase := TAU * 260.0 / float(SR)
	var fenv := TAU * fc_peak / float(SR) - fbase
	var dmul := exp(-1.0 / (0.030 * SR))
	var lp := 0.0
	var bp := 0.0
	for i in gate:
		var f := fbase + fenv
		fenv *= dmul
		lp += f * bp
		var hp := _scr[i] - lp - q * bp
		bp += f * hp
		_scr[i] = _tanh(lp * 1.5)
	var pa := (pan + 1.0) * 0.25 * PI
	_scr_mix(start, amp * cos(pa), amp * sin(pa))


## Half-time wobble bass: detuned saw pair through an LFO-swept SVF.
## lfo_cycles is integer per note, so the sweep is loop-safe by construction.
func _wobble(start: int, body: int, freq: float, amp: float, lfo_cycles: int,
		fc_lo: float, fc_hi: float) -> void:
	_scr.resize(body)
	_scr.fill(0.0)
	_scr_osc(_saw, freq, 0.5)
	_scr_osc(_saw, freq * 1.007, 0.5)
	var lp := 0.0
	var bp := 0.0
	var wf := TAU * float(lfo_cycles) / float(body)
	for i in body:
		_scr[i] *= 0.5
		var lfo := 0.5 + 0.5 * sin(wf * float(i) - PI * 0.5)
		var f := TAU * (fc_lo + (fc_hi - fc_lo) * lfo) / float(SR)
		lp += f * bp
		var hp := _scr[i] - lp - 0.6 * bp
		bp += f * hp
		_scr[i] = lp
	_scr_env_ar(int(0.01 * SR), int(0.05 * SR))
	_scr_mix(start, amp * 0.5, amp * 0.5)


# ---------------------------------------------------------------- mixdown

## DC removal, RMS normalize, tanh ceiling (peak can never pass -4.4 dBFS),
## then a seam ramp that spreads |first - last| across the whole loop so the
## seam delta is exactly zero. Saves the WAV and prints its measurements.
func _finalize(file_name: String, rms_target: float) -> void:
	var chans: Array = [_bl, _br] if _stereo else [_bl]
	var sum_sq := 0.0
	for c: PackedFloat32Array in chans:
		var mean := 0.0
		for i in _n:
			mean += c[i]
		mean /= float(_n)
		for i in _n:
			c[i] -= mean
			sum_sq += c[i] * c[i]
	var rms := sqrt(sum_sq / float(_n * chans.size()))
	var g := rms_target / maxf(rms, 1e-9)
	var peak := 0.0
	var seam := 0.0
	sum_sq = 0.0
	for c: PackedFloat32Array in chans:
		var mean := 0.0
		for i in _n:
			var v := 0.6 * _tanh(c[i] * g / 0.6)
			c[i] = v
			mean += v
		mean /= float(_n)
		for i in _n:
			c[i] -= mean
		var j := c[0] - c[_n - 1]
		var jstep := j / float(_n - 1)
		mean = 0.0
		for i in _n:
			c[i] += jstep * float(i)
			mean += c[i]
		mean /= float(_n)
		for i in _n:
			var v := c[i] - mean
			c[i] = v
			sum_sq += v * v
			var av := absf(v)
			if av > peak:
				peak = av
		seam = maxf(seam, absf(c[0] - c[_n - 1]))
	rms = sqrt(sum_sq / float(_n * chans.size()))
	var bytes := PackedByteArray()
	var chn := 2 if _stereo else 1
	bytes.resize(_n * 2 * chn)
	if _stereo:
		for i in _n:
			bytes.encode_s16(i * 4, int(clampf(_bl[i], -0.999, 0.999) * 32767.0))
			bytes.encode_s16(i * 4 + 2, int(clampf(_br[i], -0.999, 0.999) * 32767.0))
	else:
		for i in _n:
			bytes.encode_s16(i * 2, int(clampf(_bl[i], -0.999, 0.999) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SR
	stream.stereo = _stereo
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = _n
	var err := stream.save_to_wav(OUT_DIR + file_name)
	if err != OK:
		push_error("MusicGenerator: failed to save %s (%d)" % [file_name, err])
		return
	print("  %s  %.2fs  peak %.2f dBFS  rms %.2f dBFS  seam %.5f" % [
			file_name, float(_n) / float(SR),
			20.0 * log(maxf(peak, 1e-9)) / log(10.0),
			20.0 * log(maxf(rms, 1e-9)) / log(10.0), seam])


# ================================================================ music

## MENU — 80 BPM, 12 bars (36 s), A minor. Wistful pads over a city-at-night
## heartbeat; the leitmotif enters mid-loop and again, up an octave, at the end.
@warning_ignore("integer_division")
func _make_menu() -> void:
	var spb := 33075          # 44100 * 60 / 80, exact
	var bar := spb * 4
	var bars := 12
	_begin(bar * bars, true, 101)
	var am7: Array = [45, 55, 60, 64]
	var f7: Array = [41, 52, 57, 60]
	var c7: Array = [48, 55, 59, 64]
	var g6: Array = [43, 55, 59, 64]
	var dm7: Array = [50, 57, 60, 65]
	var esus: Array = [40, 52, 57, 59]
	# [start_bar, len_bars, chord, sub_root]
	var chords: Array = [
		[0, 2, am7, 33], [2, 2, f7, 29], [4, 2, c7, 36], [6, 2, g6, 31],
		[8, 1, am7, 33], [9, 1, f7, 29], [10, 1, dm7, 38], [11, 1, esus, 28],
	]
	for ch: Array in chords:
		var st: int = int(ch[0]) * bar
		var body: int = int(ch[1]) * bar
		_pad_chord(ch[2], st, body, 0.085, 1300.0, 0.9, 1.4)
		_sub_note(st, body, int(ch[3]), 0.14)
	# slow pulse arp, 8th notes, quieter through the first half
	var step := spb / 2
	for ch: Array in chords:
		var cb: int = ch[0]
		var notes: Array = ch[2]
		var seq: Array = [notes[0], notes[1], notes[2], notes[3],
				int(notes[0]) + 12, int(notes[2]) + 12,
				int(notes[1]) + 12, int(notes[3]) + 12]
		var nsteps: int = int(ch[1]) * 8
		for k in nsteps:
			var st := cb * bar + k * step
			var vel := 1.0 if k % 2 == 0 else 0.68
			var a := 0.040 * vel * (0.75 if cb < 4 else 1.0)
			var pan := 0.25 if k % 2 == 0 else -0.25
			_tone_note(_p25, 0.25, st, int(step * 0.9), int(0.08 * SR),
					_midi_hz(float(seq[k % 8])), a, 2400.0, 0.004, pan)
			if k % 4 == 0:
				_echo(st, a, pan, int(0.75 * spb), 0.40, 0.15)
	# leitmotif: first statement subtle, closing statements up an octave
	_play_line(MOTIF, 16.0, spb, 0.075, _tri, 2200.0, 0.02, 0.35, -0.1, 1.0)
	_play_line(MOTIF, 32.0, spb, 0.105, _tri, 2600.0, 0.02, 0.35, 0.1, 1.0, 12)
	_play_line(MOTIF, 40.0, spb, 0.105, _tri, 2600.0, 0.02, 0.5, -0.1, 1.0, 12)
	# heartbeat kick, hats only in the back half
	for b in bars:
		_kick(b * bar, 0.09)
	for b in range(8, 12):
		for k in 4:
			_hat(b * bar + k * spb + spb / 2, 0.028, 0.05, 0.3)
	_finalize("music_menu.wav", 0.13)


## EXPLORE — 84 BPM, 16 bars (45.7 s), lo-fi C major groove with swung dusty
## hats and a vinyl bed. Phrase plan A A B A; the final A quotes the leitmotif.
@warning_ignore("integer_division")
func _make_explore() -> void:
	var spb := 31500          # 44100 * 60 / 84, exact
	var bar := spb * 4
	var bars := 16
	_begin(bar * bars, true, 202)
	var c7: Array = [48, 55, 59, 64]
	var am7: Array = [45, 52, 55, 60]
	var f7: Array = [41, 52, 57, 60]
	var g7: Array = [43, 53, 59, 62]
	var em7: Array = [40, 50, 55, 59]
	var dm7: Array = [50, 57, 60, 65]
	var prog: Array = [
		[c7, 36], [am7, 33], [f7, 29], [g7, 31],
		[c7, 36], [am7, 33], [f7, 29], [g7, 31],
		[em7, 28], [am7, 33], [dm7, 38], [g7, 31],
		[c7, 36], [am7, 33], [f7, 29], [g7, 31],
	]
	var swing := int(0.10 * spb)
	var step16 := spb / 4
	var stab_pans: Array = [-0.3, 0.0, 0.3]
	for b in bars:
		var entry: Array = prog[b]
		var notes: Array = entry[0]
		var root: int = entry[1]
		var st := b * bar
		_pad_chord(notes, st, bar, 0.06, 1100.0, 0.5, 0.8)
		# sub bass locked to the kick pattern
		_sub_note(st, 6 * step16, root, 0.17, 0.1)
		_sub_note(st + 7 * step16, 3 * step16, root, 0.17, 0.1)
		_sub_note(st + 10 * step16, 4 * step16, root, 0.17, 0.1)
		for s16: int in [0, 7, 10]:
			_kick(st + s16 * step16, 0.17)
		for s16: int in [4, 12]:
			_snare(st + s16 * step16, 0.115)
		for k in 8:
			var off := swing if k % 2 == 1 else 0
			var vels: Array = [1.0, 0.55, 0.8, 0.55]
			var vel: float = vels[k % 4]
			_hat(st + k * 2 * step16 + off, 0.032 * vel, 0.04,
					0.2 if k % 2 == 0 else -0.2)
		# off-beat rhodes-ish stabs on the upper chord tones
		for s16: int in [3, 11]:
			for i in 3:
				_tone_note(_tri, 0.25, st + s16 * step16, int(1.2 * step16),
						int(0.12 * SR), _midi_hz(float(notes[i + 1])), 0.045,
						1600.0, 0.005, stab_pans[i])
	# the explore hook (A phrases)
	var hook: Array = [
		0.0, 67, 1.0, 1.5, 64, 0.5, 2.0, 69, 1.5, 4.0, 67, 0.75,
		5.0, 64, 0.75, 6.0, 62, 1.5, 8.0, 60, 1.0, 9.5, 62, 0.5,
		10.0, 64, 1.5, 12.5, 62, 0.75, 13.5, 59, 0.75, 14.25, 60, 1.5,
	]
	_play_line(hook, 0.0, spb, 0.085, _p25, 2000.0, 0.01, 0.2, 0.15, 0.75)
	_play_line(hook, 16.0, spb, 0.085, _p25, 2000.0, 0.01, 0.2, -0.15, 0.75)
	# B phrase: 16th arps + a slower counterline
	for b in range(8, 12):
		var entry: Array = prog[b]
		var notes: Array = entry[0]
		var seq: Array = [notes[1], notes[2], notes[3], notes[2]]
		for k in 16:
			_tone_note(_p25, 0.25, b * bar + k * step16, int(step16 * 0.85),
					int(0.06 * SR), _midi_hz(float(seq[k % 4]) + 12.0), 0.028,
					2600.0, 0.003, 0.3 if k % 2 == 0 else -0.3)
	var counter: Array = [
		0.0, 74, 1.5, 2.0, 72, 1.0, 4.0, 69, 1.5,
		8.0, 65, 1.0, 10.0, 67, 1.5, 12.0, 62, 2.0,
	]
	_play_line(counter, 32.0, spb, 0.07, _tri, 1800.0, 0.01, 0.3, -0.1, 1.0)
	# final A: the leitmotif quote, then again an octave up with a harmony
	_play_line(MOTIF, 48.0, spb, 0.09, _p25, 2200.0, 0.01, 0.25, 0.1, 0.75)
	_play_line(MOTIF, 56.0, spb, 0.10, _p25, 2400.0, 0.01, 0.3, 0.1, 0.75, 12)
	var harm: Array = []
	for i in 8:
		harm.append(MOTIF[i * 3])
		harm.append(int(MOTIF_HARM[i]) + 12)
		harm.append(MOTIF[i * 3 + 2])
	_play_line(harm, 56.0, spb, 0.055, _p25, 2000.0, 0.01, 0.3, -0.25, 0.75)
	# vinyl bed: filtered noise with a slow 6-cycle wow
	_scr.resize(_n)
	_scr_noise_fill()
	_scr_lp(3500.0)
	_scr_lp(3500.0)
	var wf := TAU * 6.0 / float(_n)
	for i in _n:
		_scr[i] *= 0.012 * (1.0 + 0.3 * sin(wf * float(i)))
	_scr_mix(0, 0.5, 0.5)
	_finalize("music_explore.wav", 0.13)


## COMBAT — 126 BPM, 24 bars (45.7 s), darksynth A minor. Acid 16th bass under
## a four-on-the-floor kick; arrangement A(drone) B(stabs+lead hook) A'.
@warning_ignore("integer_division")
func _make_combat() -> void:
	var spb := 21000          # 44100 * 60 / 126, exact
	var bar := spb * 4
	var bars := 24
	_begin(bar * bars, true, 303)
	var roots: Array = [
		33, 33, 33, 31, 33, 33, 33, 31,
		29, 31, 33, 28, 29, 31, 33, 28,
		33, 33, 33, 31, 33, 33, 33, 31,
	]
	var step16 := spb / 4
	for b in bars:
		var st := b * bar
		var r: int = roots[b]
		var in_b := b >= 8 and b < 16
		for s16 in 16:
			var off: int = ACID_PAT[s16]
			if off < 0:
				continue
			var acc := s16 in ACID_ACC
			_acid(st + s16 * step16, int(step16 * 0.8),
					_midi_hz(float(r + off)), 0.15 if acc else 0.11,
					3800.0 if acc else 1800.0, 0.30)
		for s16: int in [0, 4, 8, 12]:
			_kick(st + s16 * step16, 0.21)
		if b % 4 == 3:
			_kick(st + 14 * step16, 0.17)
		for s16: int in [4, 12]:
			_snare(st + s16 * step16, 0.14)
		for s16: int in [2, 6, 10, 14]:
			_hat(st + s16 * step16, 0.045, 0.05, 0.25 if s16 % 4 == 2 else -0.25)
		_hat(st + 10 * step16, 0.03, 0.11, 0.1)
		if in_b:
			for s16: int in [1, 3, 5, 7, 9, 11, 13, 15]:
				_hat(st + s16 * step16, 0.014, 0.03, -0.1)
	# low drone pads across the A sections
	for sb: int in [0, 16]:
		_tone_note(_saw, 0.5, sb * bar, 8 * bar, int(1.5 * SR), _midi_hz(45.0),
				0.05, 850.0, 1.2, -0.4, 9.0, 3)
		_tone_note(_saw, 0.5, sb * bar, 8 * bar, int(1.5 * SR), _midi_hz(52.0),
				0.05, 850.0, 1.2, 0.4, 9.0, 3)
	# B-section chord stabs (F G Am E, harmonic-minor lift)
	var stab_chords: Dictionary = {
		29: [41, 48, 57], 31: [43, 50, 59], 33: [45, 52, 60], 28: [40, 47, 56],
	}
	var stab_pans: Array = [-0.35, 0.0, 0.35]
	for b in range(8, 16):
		var st := b * bar
		var chn: Array = stab_chords[int(roots[b])]
		for s16: int in [0, 11]:
			for i in 3:
				_tone_note(_saw, 0.5, st + s16 * step16, int(1.1 * step16),
						int(0.1 * SR), _midi_hz(float(chn[i]) + 12.0), 0.06,
						2200.0, 0.003, stab_pans[i], 8.0, 3)
	# sparser Am stabs through A'
	for b in range(16, 24, 2):
		var st := b * bar
		var am: Array = [45, 52, 60]
		for i in 3:
			_tone_note(_saw, 0.5, st + 11 * step16, int(1.1 * step16),
					int(0.1 * SR), _midi_hz(float(am[i]) + 12.0), 0.05,
					2000.0, 0.003, stab_pans[i], 8.0, 3)
	# combat lead hook, four passes over the B section
	var phrase: Array = [
		0.0, 76, 0.5, 0.5, 79, 0.5, 1.0, 81, 0.75, 2.0, 79, 0.5,
		2.5, 76, 0.5, 3.0, 74, 1.0, 4.0, 76, 0.5, 4.5, 72, 0.5,
		5.0, 74, 0.75, 6.0, 72, 0.5, 6.5, 71, 0.5, 7.0, 69, 1.0,
	]
	var lead_amps: Array = [0.10, 0.10, 0.115, 0.115]
	for i in 4:
		_play_line(phrase, 32.0 + 8.0 * float(i), spb, lead_amps[i], _pulse,
				3200.0, 0.005, 0.12, 0.2 if i % 2 == 0 else -0.2, 0.75)
	_finalize("music_combat.wav", 0.13)


## BOSS — 140 BPM, 24 bars (41.1 s), combat's angrier phrygian sibling.
## A(chug) B(half-time wobble drop) A'(dim stabs + shrieking hook).
@warning_ignore("integer_division")
func _make_boss() -> void:
	var spb := 18900          # 44100 * 60 / 140, exact
	var bar := spb * 4
	var bars := 24
	_begin(bar * bars, true, 404)
	var roots: Array = [
		33, 34, 33, 28, 33, 34, 33, 28,
		33, 33, 34, 34, 33, 33, 28, 28,
		33, 34, 33, 28, 33, 34, 33, 28,
	]
	var step16 := spb / 4
	for b in bars:
		var st := b * bar
		var r: int = roots[b]
		if b >= 8 and b < 16:
			# half-time drop
			_wobble(st, bar, _midi_hz(float(r)), 0.16, 6, 320.0, 2100.0)
			_sub_note(st, bar - int(0.05 * SR), r - 12, 0.12, 0.15)
			_kick(st, 0.23)
			if b % 2 == 1:
				_kick(st + 10 * step16, 0.19)
			_snare(st + 8 * step16, 0.19, 0.32, 170.0)
			for s16: int in [2, 10]:
				_hat(st + s16 * step16, 0.03, 0.05, 0.2)
		else:
			for s16 in 16:
				var off: int = BOSS_PAT[s16]
				if off < 0:
					continue
				var acc := s16 in BOSS_ACC
				_acid(st + s16 * step16, int(step16 * 0.82),
						_midi_hz(float(r + off)), 0.145 if acc else 0.105,
						4200.0 if acc else 2000.0, 0.28)
			for s16: int in [0, 4, 8, 12]:
				_kick(st + s16 * step16, 0.23)
			if b % 2 == 1:
				_kick(st + 6 * step16, 0.18)
			for s16: int in [4, 12]:
				_snare(st + s16 * step16, 0.15)
			for s16 in 16:
				_hat(st + s16 * step16, 0.04 if s16 % 4 == 2 else 0.016, 0.03,
						0.2 if s16 % 2 == 0 else -0.2)
	_crash(8 * bar, 0.06, 1.5)
	_crash(16 * bar, 0.06, 1.5)
	# eerie semitone cluster floating over the drop
	_tone_note(_sine, 0.25, 8 * bar, 8 * bar, int(1.2 * SR), _midi_hz(81.0),
			0.022, 4000.0, 2.0, -0.3)
	_tone_note(_sine, 0.25, 8 * bar, 8 * bar, int(1.2 * SR), _midi_hz(82.0),
			0.022, 4000.0, 2.0, 0.3)
	# diminished stabs through A'
	var dim: Array = [57, 60, 63, 66]
	var dim_pans: Array = [-0.4, -0.15, 0.15, 0.4]
	for b in range(16, 24, 2):
		var st := b * bar
		for s16: int in [0, 7]:
			for i in 4:
				_tone_note(_saw, 0.5, st + s16 * step16, step16,
						int(0.08 * SR), _midi_hz(float(dim[i])), 0.045,
						2400.0, 0.003, dim_pans[i], 8.0, 3)
	# the boss hook: phrygian b2 riffing, four passes over A'
	var phrase: Array = [
		0.0, 81, 0.5, 0.5, 82, 0.5, 1.0, 81, 0.5, 1.5, 79, 0.5,
		2.0, 76, 1.0, 3.0, 74, 0.5, 3.5, 76, 0.5, 4.0, 77, 0.75,
		5.0, 76, 0.75, 6.0, 74, 0.5, 6.5, 72, 0.5, 7.0, 69, 1.0,
	]
	var lead_amps: Array = [0.11, 0.11, 0.125, 0.125]
	for i in 4:
		_play_line(phrase, 64.0 + 8.0 * float(i), spb, lead_amps[i], _pulse,
				3400.0, 0.004, 0.1, 0.2 if i % 2 == 0 else -0.2, 0.5)
	_finalize("music_boss.wav", 0.13)


## VICTORY — 105 BPM, 12 bars (27.4 s), C major. Fanfare (the leitmotif,
## transposed major) into an upbeat groove; bar 12 lands on G7 so the loop
## resolves back into the opening hit.
@warning_ignore("integer_division")
func _make_victory() -> void:
	var spb := 25200          # 44100 * 60 / 105, exact
	var bar := spb * 4
	_begin(bar * 12, true, 505)
	var cmaj: Array = [48, 55, 60, 64]
	var gmaj: Array = [43, 55, 59, 62]
	var amin: Array = [45, 57, 60, 64]
	var fmaj: Array = [41, 53, 57, 65]
	var step16 := spb / 4
	var stab_pans: Array = [-0.4, -0.15, 0.15, 0.4]
	# fanfare hits: [beat, chord, dur_beats]
	var hits: Array = [
		[0.0, cmaj, 0.75], [1.5, cmaj, 0.75], [4.0, gmaj, 0.75],
		[5.5, gmaj, 0.75], [8.0, amin, 0.75], [10.0, fmaj, 0.75],
		[12.0, gmaj, 3.6],
	]
	for h: Array in hits:
		var st := int(float(h[0]) * float(spb))
		var chn: Array = h[1]
		var body := int(float(h[2]) * float(spb))
		for i in 4:
			_tone_note(_saw, 0.5, st, body, int(0.3 * SR),
					_midi_hz(float(chn[i]) + 12.0), 0.06, 2400.0, 0.01,
					stab_pans[i], 9.0, 3)
		_sub_note(st, body, int(chn[0]) - 12, 0.15, 0.15)
		_kick(st, 0.18)
	# the leitmotif in major, then an ascending run landing on high C
	var motif_maj: Array = [
		0.0, 72, 1.0, 1.0, 76, 0.5, 1.5, 77, 0.5, 2.0, 79, 1.5,
		3.5, 77, 0.5, 4.0, 76, 1.0, 5.0, 74, 1.0, 6.0, 72, 1.5,
	]
	_play_line(motif_maj, 0.0, spb, 0.13, _pulse, 2800.0, 0.008, 0.25, 0.1, 0.5)
	var run: Array = [
		0.0, 72, 0.5, 0.5, 74, 0.5, 1.0, 76, 0.5, 1.5, 77, 0.5,
		2.0, 79, 0.5, 2.5, 81, 0.5, 3.0, 83, 0.5, 3.5, 84, 4.2,
	]
	_play_line(run, 8.0, spb, 0.12, _pulse, 3000.0, 0.008, 0.4, -0.1, 0.5)
	# bar-4 snare roll into a crash
	for k in 8:
		_snare(3 * bar + (8 + k) * step16, 0.035 + 0.011 * float(k))
	_crash(4 * bar, 0.07)
	# groove, bars 5-12
	var groove: Array = [
		[cmaj, 36], [gmaj, 31], [amin, 33], [fmaj, 29],
		[cmaj, 36], [fmaj, 29], [gmaj, 31], [gmaj, 31],
	]
	for gi in 8:
		var st := (4 + gi) * bar
		var entry: Array = groove[gi]
		var chn: Array = entry[0]
		var root: int = entry[1]
		_pad_chord(chn, st, bar, 0.05, 1400.0, 0.3, 0.6)
		_sub_note(st, 3 * step16, root, 0.15, 0.08)
		_sub_note(st + 4 * step16, 3 * step16, root + 12, 0.15, 0.08)
		_sub_note(st + 8 * step16, 3 * step16, root, 0.15, 0.08)
		_sub_note(st + 12 * step16, 3 * step16, root + 12, 0.15, 0.08)
		for s16: int in [0, 4, 8, 12]:
			_kick(st + s16 * step16, 0.19)
		for s16: int in [4, 12]:
			_snare(st + s16 * step16, 0.13)
		for k in 8:
			_hat(st + k * 2 * step16, 0.04 if k % 2 == 0 else 0.024, 0.05,
					0.2 if k % 2 == 0 else -0.2)
		_hat(st + 14 * step16, 0.03)
		_hat(st + 15 * step16, 0.025)
		var seq: Array = [chn[1], chn[2], chn[3], chn[2]]
		for k in 16:
			_tone_note(_p25, 0.25, st + k * step16, int(step16 * 0.85),
					int(0.05 * SR), _midi_hz(float(seq[k % 4]) + 12.0), 0.032,
					3000.0, 0.003, 0.3 if k % 2 == 0 else -0.3)
	# closing leitmotif over the groove, harmonized on the repeat
	_play_line(motif_maj, 32.0, spb, 0.11, _pulse, 2800.0, 0.01, 0.25, 0.15, 0.5)
	var motif_maj2: Array = motif_maj.duplicate()
	motif_maj2[23] = 2.5    # let the final note ring into the loop turnaround
	_play_line(motif_maj2, 40.0, spb, 0.11, _pulse, 2800.0, 0.01, 0.4, 0.15, 0.5)
	var vharm: Array = [69, 72, 74, 76, 74, 72, 71, 69]
	var harm: Array = []
	for i in 8:
		harm.append(motif_maj[i * 3])
		harm.append(vharm[i])
		harm.append(motif_maj[i * 3 + 2])
	_play_line(harm, 40.0, spb, 0.065, _pulse, 2400.0, 0.01, 0.4, -0.25, 0.5)
	_finalize("music_victory.wav", 0.13)


# ================================================================ ambience
# All beds are 24 s mono. Every tone and LFO runs an integer number of cycles
# per loop, and noise beds are filtered circularly (two laps with carried
# state), so the seam is steady-state by construction.

func _scr_noise_fill() -> void:
	var n := _scr.size()
	var npos := _noise_pos
	for i in n:
		_scr[i] = _noise[npos]
		npos += 1
		if npos == NOISE_N:
			npos = 0
	_noise_pos = npos


## Quantized sine partial with a quantized-cycle amplitude LFO, straight into
## the master (mono only): amp * sin(tone) * (base + depth * sin(lfo)).
func _amb_tone(freq: float, amp: float, lfo_cycles: int, lfo_depth: float,
		lfo_base: float) -> void:
	var cycles := maxf(1.0, roundf(freq * float(_n) / float(SR)))
	var inc := cycles * float(TS) / float(_n)
	var linc := float(lfo_cycles) * float(TS) / float(_n)
	var ph := 0.0
	var lph := 0.0
	for i in _n:
		_bl[i] += amp * _sine[int(ph) & TS_MASK] \
				* (lfo_base + lfo_depth * _sine[int(lph) & TS_MASK])
		ph += inc
		lph += linc


## INTERIOR — PSU mains hum (50/100/150 Hz), a cycling fridge resonance, and a
## dark noise floor. The localhost apartment at 3AM.
func _make_amb_interior() -> void:
	_begin(24 * SR, false, 606)
	_amb_tone(50.0, 0.32, 5, 0.12, 1.0)
	_amb_tone(100.0, 0.14, 5, 0.12, 1.0)
	_amb_tone(150.0, 0.07, 5, 0.12, 1.0)
	_amb_tone(118.0, 0.10, 9, 0.5, 0.5)
	_amb_tone(236.0, 0.045, 9, 0.5, 0.5)
	_scr.resize(_n)
	_scr_noise_fill()
	_scr_lp(240.0, 2)
	for i in _n:
		_bl[i] += _scr[i] * 2.4
	_finalize("ambient_interior.wav", 0.05)


## INDUSTRIAL — deep rumble, four beating metal partials, periodic steam vents.
func _make_amb_industrial() -> void:
	_begin(24 * SR, false, 707)
	_scr.resize(_n)
	_scr_noise_fill()
	_scr_lp(90.0, 2)
	var wf := TAU * 4.0 / float(_n)
	for i in _n:
		_bl[i] += _scr[i] * 7.0 * (1.0 + 0.3 * sin(wf * float(i)))
	# metal partials: each is a detuned beating pair with its own slow swell
	var partials: Array = [
		[167.0, 0.09, 3], [254.0, 0.065, 5], [397.0, 0.045, 7], [613.0, 0.032, 11],
	]
	for p: Array in partials:
		var f: float = p[0]
		var a: float = float(p[1]) * 0.8
		var c: int = p[2]
		_amb_tone(f, a, c, 0.35, 0.65)
		_amb_tone(f + 0.7, a * 0.8, c, 0.35, 0.65)
	# steam vents
	var vents: Array = [4.0, 2.2, 12.5, 1.8, 19.0, 2.6]
	for v in range(0, vents.size(), 2):
		var dur: float = vents[v + 1]
		var m := int(dur * SR)
		_scr.resize(m)
		_scr_noise_fill()
		var prev := 0.0
		for i in m:
			var raw := _scr[i]
			_scr[i] = raw - prev
			prev = raw
		_scr_lp(3000.0)
		var atk := 0.5 * SR
		var dm := exp(-1.0 / (dur * 0.45 * SR))
		var e := 1.0
		for i in m:
			_scr[i] *= minf(float(i) / atk, 1.0) * e * 0.9
			e *= dm
		_scr_mix(int(float(vents[v]) * SR), 1.0, 0.0)
	_finalize("ambient_industrial.wav", 0.05)


## OUTDOOR — gusting wind, a faint two-note night pad, synth crickets.
func _make_amb_outdoor() -> void:
	_begin(24 * SR, false, 808)
	_scr.resize(_n)
	_scr_noise_fill()
	_scr_lp(420.0, 2)
	var w2 := TAU * 2.0 / float(_n)
	var w5 := TAU * 5.0 / float(_n)
	for i in _n:
		_bl[i] += _scr[i] * 4.0 \
				* (1.0 + 0.30 * sin(w2 * float(i)) + 0.18 * sin(w5 * float(i)))
	_amb_tone(110.0, 0.10, 3, 0.25, 1.0)
	_amb_tone(165.0, 0.05, 3, 0.25, 1.0)
	# crickets: trilled high chirps at fixed seeded times
	var m := int(0.35 * SR)
	for ci in range(0, CRICKETS.size(), 2):
		var amp: float = CRICKETS[ci + 1]
		_scr.resize(m)
		for i in m:
			var t := float(i) / float(SR)
			var carrier := sin(TAU * 3800.0 * t) * 0.5 + sin(TAU * 4200.0 * t) * 0.3
			var trill := 0.5 + 0.5 * sin(TAU * 28.0 * t - PI * 0.5)
			_scr[i] = carrier * trill * sin(PI * float(i) / float(m)) * amp
		_scr_mix(int(float(CRICKETS[ci]) * SR), 1.0, 0.0)
	_finalize("ambient_outdoor.wav", 0.05)


## ETHEREAL — a beating Aadd9 sine cloud, high shimmer, band-passed air.
func _make_amb_ethereal() -> void:
	_begin(24 * SR, false, 909)
	var partials: Array = [
		[220.0, 0.12, 2], [329.63, 0.10, 3], [493.88, 0.075, 5], [739.99, 0.05, 7],
	]
	for p: Array in partials:
		var f: float = p[0]
		var a: float = p[1]
		var c: int = p[2]
		_amb_tone(f, a, c, 0.4, 0.6)
		_amb_tone(f + 0.35, a * 0.85, c, 0.4, 0.6)
	_amb_tone(1760.0, 0.020, 4, 0.5, 0.5)
	_amb_tone(2637.0, 0.013, 4, 0.5, 0.5)
	# air: LP 5k noise minus its LP 600 core = a gentle band of breath
	_scr.resize(_n)
	_scr_noise_fill()
	_scr_lp(5000.0, 2)
	_scr2 = _scr.duplicate()
	var a5 := 1.0 - exp(-TAU * 600.0 / float(SR))
	var y := 0.0
	for _lap in 2:
		for i in _n:
			y += a5 * (_scr2[i] - y)
			_scr2[i] = y
	for i in _n:
		_bl[i] += (_scr[i] - _scr2[i]) * 0.35
	_finalize("ambient_ethereal.wav", 0.05)
