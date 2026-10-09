@tool
class_name Sound
## Sound manager: synthesizes sound effects programmatically with AudioStreamWAV without external audio files.
## Supports mute toggle and web-version delayed playback protection.

static var muted: bool = false
static var _player: AudioStreamPlayer = null
static var _streams: Dictionary = {}


static func is_muted() -> bool:
	return muted


static func toggle_mute() -> bool:
	muted = not muted
	return muted


static func play(name: String, caller: Node = null) -> void:
	if Engine.is_editor_hint():
		return
	if muted:
		return
	if _player == null or not is_instance_valid(_player):
		_player = AudioStreamPlayer.new()
		_player.name = "GlobalSoundPlayer"
		if caller != null and caller.get_tree() != null:
			caller.get_tree().root.add_child(_player)
		else:
			return

	var stream: AudioStreamWAV = _get_or_create_stream(name)
	if stream != null:
		_player.stream = stream
		_player.play()


static func _get_or_create_stream(name: String) -> AudioStreamWAV:
	if _streams.has(name):
		return _streams[name]
	var stream: AudioStreamWAV = null
	match name:
		"click":
			stream = _gen_tone(880.0, 0.04, 0.15)
		"step":
			stream = _gen_tone(440.0, 0.05, 0.12)
		"dice":
			stream = _gen_dice(0.12, 0.2)
		"win":
			stream = _gen_arpeggio([523.25, 659.25, 783.99, 1046.5], 0.07, 0.2)
		"fail":
			stream = _gen_slide(260.0, 130.0, 0.25, 0.22)
		"ding":
			stream = _gen_tone(1174.66, 0.12, 0.18)
	if stream != null:
		_streams[name] = stream
	return stream


static func _gen_tone(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var mix_rate: int = 22050
	var samples: int = int(duration * mix_rate)
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t: float = float(i) / float(mix_rate)
		var env: float = 1.0 - (float(i) / float(samples))
		var wave: float = sin(2.0 * PI * freq * t) * env * volume
		var val: int = clampi(int(wave * 32767.0), -32768, 32767)
		var idx: int = i * 2
		data[idx] = val & 0xFF
		data[idx + 1] = (val >> 8) & 0xFF
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = data
	return wav


static func _gen_dice(duration: float, volume: float) -> AudioStreamWAV:
	var mix_rate: int = 22050
	var samples: int = int(duration * mix_rate)
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t: float = float(i) / float(mix_rate)
		var env: float = 1.0 - (float(i) / float(samples))
		# Fast random impulses simulate dice impacts
		var noise: float = (randf() * 2.0 - 1.0) * 0.5
		var f: float = 300.0 + sin(t * 80.0) * 150.0
		var tone: float = sin(2.0 * PI * f * t) * 0.5
		var wave: float = (noise + tone) * env * volume
		var val: int = clampi(int(wave * 32767.0), -32768, 32767)
		var idx: int = i * 2
		data[idx] = val & 0xFF
		data[idx + 1] = (val >> 8) & 0xFF
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = data
	return wav


static func _gen_arpeggio(freqs: Array, note_dur: float, volume: float) -> AudioStreamWAV:
	var mix_rate: int = 22050
	var total_dur: float = note_dur * freqs.size()
	var total_samples: int = int(total_dur * mix_rate)
	var samples_per_note: int = int(note_dur * mix_rate)
	var data: PackedByteArray = PackedByteArray()
	data.resize(total_samples * 2)
	for i in range(total_samples):
		var note_idx: int = clampi(int(i / samples_per_note), 0, freqs.size() - 1)
		var freq: float = float(freqs[note_idx])
		var note_i: int = i % samples_per_note
		var t: float = float(note_i) / float(mix_rate)
		var env: float = 1.0 - (float(note_i) / float(samples_per_note))
		var wave: float = sin(2.0 * PI * freq * t) * env * volume
		var val: int = clampi(int(wave * 32767.0), -32768, 32767)
		var idx: int = i * 2
		data[idx] = val & 0xFF
		data[idx + 1] = (val >> 8) & 0xFF
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = data
	return wav


static func _gen_slide(start_f: float, end_f: float, duration: float, volume: float) -> AudioStreamWAV:
	var mix_rate: int = 22050
	var samples: int = int(duration * mix_rate)
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples * 2)
	var phase: float = 0.0
	for i in range(samples):
		var frac: float = float(i) / float(samples)
		var freq: float = lerpf(start_f, end_f, frac)
		phase += 2.0 * PI * freq / float(mix_rate)
		var env: float = 1.0 - frac
		# Adds square wave harmonics to create a falling sensation
		var wave: float = (sin(phase) + 0.3 * sin(phase * 2.0)) * env * volume
		var val: int = clampi(int(wave * 32767.0), -32768, 32767)
		var idx: int = i * 2
		data[idx] = val & 0xFF
		data[idx + 1] = (val >> 8) & 0xFF
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = data
	return wav
