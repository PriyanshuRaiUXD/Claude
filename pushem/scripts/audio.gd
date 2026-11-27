class_name GameAudio
extends Node


const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const RATE := 22050
const SFX_VOICES := 10


const YELL_VOICES := {
	PlayerPawn.WeightClass.LIGHT: {"f0": 370.0, "formant": 1.2, "gain_db": -1.0},
	PlayerPawn.WeightClass.NORMAL: {"f0": 215.0, "formant": 1.0, "gain_db": 0.0},
	PlayerPawn.WeightClass.HEAVY: {"f0": 118.0, "formant": 0.82, "gain_db": -4.0},
}


const MUSIC_START_TEMPO := 1.0
const MUSIC_END_TEMPO := 1.8
const MUSIC_TEMPO_CURVE := 1.3

const MUSIC_START_LEVEL := 0.55
const MUSIC_END_LEVEL := 1.0
const MUSIC_FADE_PER_SEC := 0.8

static var _instance: GameAudio

var _music: AudioStreamPlayer
var _music_level := 0.0
var _music_target := 0.0
var _preview_left := 0.0
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _sfx := {}
var _yells := {}

func _ready() -> void:
	_instance = self
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	apply_volumes()

	_sfx = {
		"flick": _flick_sound(),
		"bump": _bump_sound(),
		"fall": _fall_sound(),
		"go": _go_sound(),
		"win": _win_sound(),
		"tick": _tick_sound(),
	}
	for wclass: int in YELL_VOICES:
		var v: Dictionary = YELL_VOICES[wclass]

		_yells[wclass] = [
			_yell_sound(v["f0"], v["formant"], 750.0, 1200.0, 11),
			_yell_sound(v["f0"] * 1.07, v["formant"], 600.0, 1700.0, 23),
		]
	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_voices.append(p)

	_music = AudioStreamPlayer.new()
	_music.bus = MUSIC_BUS
	_music.stream = _music_loop()
	_music.volume_db = -80.0
	add_child(_music)


static func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if _instance == null or not _instance._sfx.has(sound):
		return
	var p: AudioStreamPlayer = _instance._voices[_instance._next_voice]
	_instance._next_voice = (_instance._next_voice + 1) % SFX_VOICES
	p.stream = _instance._sfx[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


static func set_music_progress(progress: float) -> void:
	if _instance == null:
		return
	var p := clampf(progress, 0.0, 1.0)
	_instance._music_target = lerpf(MUSIC_START_LEVEL, MUSIC_END_LEVEL, p)
	_instance._music.pitch_scale = lerpf(MUSIC_START_TEMPO, MUSIC_END_TEMPO,
			pow(p, MUSIC_TEMPO_CURVE))
	if not _instance._music.playing:
		_instance._music.play()


static func stop_music(immediately := false) -> void:
	if _instance == null:
		return
	_instance._music_target = 0.0
	if immediately:
		_instance._music_level = 0.0
		_instance._music.stop()
		_instance._music.pitch_scale = MUSIC_START_TEMPO


static func preview_music() -> void:
	if _instance == null:
		return
	set_music_progress(0.0)
	_instance._preview_left = 1.5


static func music_state() -> String:
	if _instance == null or not _instance._music.playing:
		return "off"
	return "%.2f@%.2f" % [_instance._music.pitch_scale, _instance._music_level]

func _process(delta: float) -> void:
	if _preview_left > 0.0:
		_preview_left = maxf(0.0, _preview_left - delta)
		if _preview_left == 0.0:
			stop_music()
	if not _music.playing:
		return
	_music_level = move_toward(_music_level, _music_target, delta * MUSIC_FADE_PER_SEC)
	if _music_level <= 0.0 and _music_target <= 0.0:
		_music.stop()
		_music.pitch_scale = MUSIC_START_TEMPO
		return
	_music.volume_db = linear_to_db(maxf(_music_level, 0.0001))


static func yell(wclass: int) -> void:
	if _instance == null or not _instance._yells.has(wclass):
		return
	var takes: Array = _instance._yells[wclass]
	var p: AudioStreamPlayer = _instance._voices[_instance._next_voice]
	_instance._next_voice = (_instance._next_voice + 1) % SFX_VOICES
	p.stream = takes.pick_random()
	p.volume_db = YELL_VOICES[wclass]["gain_db"]
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()


static func apply_volumes() -> void:
	_set_bus(MUSIC_BUS, Settings.music_volume)
	_set_bus(SFX_BUS, Settings.sfx_volume)

static func _set_bus(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))

static func _ensure_bus(bus: String) -> void:
	if AudioServer.get_bus_index(bus) >= 0:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus)
	AudioServer.set_bus_send(idx, "Master")


static func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

static func _buffer(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(seconds * RATE))
	return s


static func _flick_sound() -> AudioStreamWAV:
	var s := _buffer(0.22)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 700.0 * exp(-t * 6.0) + 150.0
		phase += f / RATE
		var env := exp(-t * 14.0) * minf(1.0, t * 200.0)
		s[i] = (rng.randf_range(-1.0, 1.0) * 0.35 + sin(TAU * phase) * 0.4) * env
	return _wav(s)


static func _bump_sound() -> AudioStreamWAV:
	var s := _buffer(0.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 55.0 + 120.0 * exp(-t * 30.0)
		phase += f / RATE
		s[i] = sin(TAU * phase) * exp(-t * 18.0) * 0.9 + rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.5

	return _wav(s)


static func _fall_sound() -> AudioStreamWAV:
	var s := _buffer(0.6)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 520.0 * exp(-t * 2.5) + 90.0 + sin(t * 40.0) * 20.0
		phase += f / RATE
		s[i] = sin(TAU * phase) * exp(-t * 3.0) * 0.45
	return _wav(s)


static func _go_sound() -> AudioStreamWAV:
	var s := _buffer(0.4)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 660.0 if t < 0.12 else 880.0
		phase += f / RATE
		var local_t := t if t < 0.12 else t - 0.12
		var env := exp(-local_t * 8.0)
		var sq := 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		s[i] = (sq * 0.15 + sin(TAU * phase) * 0.25) * env
	return _wav(s)


static func _win_sound() -> AudioStreamWAV:
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var step := 0.13
	var s := _buffer(step * 3 + 0.6)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var n := mini(int(t / step), 3)
		phase += notes[n] / RATE
		var local_t := t - n * step
		var env := exp(-local_t * (2.5 if n == 3 else 10.0))
		var tri := absf(fmod(phase, 1.0) * 4.0 - 2.0) - 1.0
		s[i] = (tri * 0.18 + sin(TAU * phase) * 0.2) * env
	return _wav(s)


static func _yell_sound(f0: float, formant: float, f1: float, f2: float,
		seed_value: int) -> AudioStreamWAV:
	var dur := 0.36
	var s := _buffer(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bp1 := _bandpass(f1 * formant, 5.0)
	var bp2 := _bandpass(f2 * formant, 7.0)
	var z1 := [0.0, 0.0, 0.0, 0.0]
	var z2 := [0.0, 0.0, 0.0, 0.0]
	var phase := 0.0
	var peak := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var k := t / dur
		var contour := 1.0 + 0.18 * sin(minf(k * 3.0, 1.0) * PI * 0.5) - 0.3 * k
		var vib := 1.0 + 0.02 * sin(TAU * 5.5 * t)
		phase += f0 * contour * vib / RATE
		var voiced := (fmod(phase, 1.0) * 2.0 - 1.0) * smoothstep(0.03, 0.07, t)
		var breath := rng.randf_range(-1.0, 1.0) * (0.35 - 0.25 * smoothstep(0.02, 0.09, t))
		var src := voiced + breath
		var y := _biquad(bp1, z1, src) + 0.6 * _biquad(bp2, z2, src)
		y *= 1.0 - smoothstep(dur - 0.14, dur, t)
		s[i] = y
		peak = maxf(peak, absf(y))
	if peak > 0.0:
		for i in s.size():
			s[i] *= 0.8 / peak
	return _wav(s)


static func _bandpass(fc: float, q: float) -> Array:
	var w := TAU * fc / RATE
	var alpha := sin(w) / (2.0 * q)
	var a0 := 1.0 + alpha
	return [alpha / a0, -alpha / a0, -2.0 * cos(w) / a0, (1.0 - alpha) / a0]

static func _biquad(c: Array, z: Array, x: float) -> float:
	var y: float = c[0] * x + c[1] * z[1] - c[2] * z[2] - c[3] * z[3]
	z[1] = z[0]
	z[0] = x
	z[3] = z[2]
	z[2] = y
	return y


static func _tick_sound() -> AudioStreamWAV:
	var s := _buffer(0.09)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = sin(TAU * 880.0 * t) * exp(-t * 40.0) * 0.5
	return _wav(s)


static func _music_loop() -> AudioStreamWAV:
	var beat := 60.0 / 128.0
	var beats := 16
	var roots := [110.0, 87.31, 130.81, 98.0]
	var chords := [[0, 3, 7, 12], [0, 4, 7, 12], [0, 4, 7, 12], [0, 4, 7, 12]]
	var s := _buffer(beat * beats)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var bass_phase := 0.0
	var lead_phase := 0.0
	var kick_phase := 0.0
	var last_beat := -1
	for i in s.size():
		var t := float(i) / RATE
		var b := int(t / beat) % beats
		var tb := t - b * beat
		var bar := b / 4
		var root: float = roots[bar]
		if b != last_beat:
			last_beat = b
			kick_phase = 0.0

		var eighth := int(tb / (beat / 2.0))
		var t8 := tb - eighth * (beat / 2.0)
		bass_phase += root * (2.0 if eighth == 1 else 1.0) / RATE
		var bass := (0.18 if fmod(bass_phase, 1.0) < 0.5 else -0.18) * exp(-t8 * 5.0)

		kick_phase += (50.0 + 100.0 * exp(-tb * 28.0)) / RATE
		var kick := sin(TAU * kick_phase) * exp(-tb * 11.0) * 0.5

		var hat := 0.0
		if tb >= beat / 2.0:
			hat = rng.randf_range(-1.0, 1.0) * exp(-(tb - beat / 2.0) * 70.0) * 0.1

		var sixteenth := int(tb / (beat / 4.0))
		var t16 := tb - sixteenth * (beat / 4.0)
		var chord: Array = chords[bar]
		lead_phase += root * 2.0 * pow(2.0, chord[sixteenth % 4] / 12.0) / RATE
		var tri := absf(fmod(lead_phase, 1.0) * 4.0 - 2.0) - 1.0
		var lead := tri * 0.11 * exp(-t16 * 9.0)

		s[i] = bass + kick + hat + lead
	return _wav(s, true)
