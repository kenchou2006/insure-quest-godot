extends Node
## AudioManager (autoload): named sound slots, the five mission buses and the music states.
## Buses: Music (theme, owned by MusicManager), UI (buttons / cards), Tension (countdown and crisis
## layers), Voice (secretary), Ambience (room tone). Tension follows the 音效 slider, Ambience the
## 背景音樂 slider. Each slot has its own player, so a sound restarts instead of stacking, and a
## cooldown; a hard limiter on Master keeps every mix below clipping.
## A file dropped at res://assets/audio/sfx/<slot>.ogg|.wav|.mp3 replaces the built-in synth.

signal music_state_changed(state: String)

const SFX_DIR := "res://assets/audio/sfx/"
const MIX_RATE := 22050
const FADE := 1.2

## bus, level (dB) and minimum seconds between two plays
const SLOTS := {
	"ui_hover": ["UI", -16.0, 0.09],
	"ui_click": ["UI", -9.0, 0.05],
	"ui_back": ["UI", -10.0, 0.05],
	"dice_roll": ["UI", -7.0, 0.4],
	"dice_land": ["UI", -6.0, 0.25],
	"piece_step": ["UI", -13.0, 0.08],
	"clue_scan": ["UI", -11.0, 0.25],
	"card_flip": ["UI", -10.0, 0.1],
	"gold_scan": ["UI", -13.0, 0.4],
	"trust_up": ["UI", -9.0, 0.35],
	"trust_down": ["UI", -9.0, 0.35],
	"budget_over": ["Tension", -11.0, 0.9],
	"compliance_risk": ["Tension", -9.0, 0.6],
	"event_minor": ["UI", -9.0, 0.6],
	"event_major": ["Tension", -7.0, 0.9],
	"mission_success": ["UI", -8.0, 1.0],
	"mission_fail": ["UI", -10.0, 1.0],
	"node_unlock": ["UI", -9.0, 0.5],
	"xp_gain": ["UI", -11.0, 0.3],
	"confirm_soft": ["UI", -9.0, 0.3],
	"timer_warn": ["Tension", -10.0, 1.0],
	"timer_tick": ["Tension", -15.0, 0.45],
	"timer_tick_strong": ["Tension", -11.0, 0.45],
	"heartbeat": ["Tension", -10.0, 0.6],
	"toast": ["UI", -15.0, 0.4],
	"page_whoosh": ["UI", -16.0, 0.3],
}
## Looping layers: bus, level when fully on (dB)
const LOOPS := {
	"tension_warn": ["Tension", -18.0],
	"tension_danger": ["Tension", -15.0],
	"tension_critical": ["Tension", -14.0],
	"ambience_room": ["Ambience", -26.0],
}

var _players: Dictionary = {}
var _last: Dictionary = {}
var _streams: Dictionary = {}
var _loops: Dictionary = {}
var _loop_tweens: Dictionary = {}
var _music_state := ""
var _music_tween: Tween
var _lowpass: AudioEffectLowPassFilter
var _amplify: AudioEffectAmplify
var _ready_done := false
var muted_layers := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_buses()
	_install_effects()
	MusicManager.volumes_changed.connect(_sync_follow_buses)
	_sync_follow_buses()
	if Engine.is_editor_hint() or DisplayServer.get_name() == "headless" and not OS.has_environment("IQ_AUDIO_TEST"):
		_ready_done = true
		return
	# Spread synthesis over frames so the first screens never hitch
	_warm_up()


## Creates any mission bus that the layout file lacks (Tension / Ambience on old saves)
static func ensure_buses() -> void:
	for bus: String in ["Music", "UI", "Voice", "Tension", "Ambience"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


func _install_effects() -> void:
	var master := 0
	var has_limiter := false
	for k in range(AudioServer.get_bus_effect_count(master)):
		var fx := AudioServer.get_bus_effect(master, k)
		if fx is AudioEffectHardLimiter or fx is AudioEffectLimiter:
			has_limiter = true
	if not has_limiter:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		lim.pre_gain_db = 0.0
		AudioServer.add_bus_effect(master, lim)
	var mi := AudioServer.get_bus_index("Music")
	if mi < 0:
		return
	for k in range(AudioServer.get_bus_effect_count(mi)):
		var fx := AudioServer.get_bus_effect(mi, k)
		if fx is AudioEffectLowPassFilter:
			_lowpass = fx
		elif fx is AudioEffectAmplify:
			_amplify = fx
	if _lowpass == null:
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(mi, _lowpass)
	if _amplify == null:
		_amplify = AudioEffectAmplify.new()
		_amplify.volume_db = 0.0
		AudioServer.add_bus_effect(mi, _amplify)


func _sync_follow_buses() -> void:
	var pairs := {"Tension": "UI", "Ambience": "Music"}
	for bus: String in pairs:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var src: String = pairs[bus]
		var db := MusicManager.get_volume_db(src)
		AudioServer.set_bus_volume_db(i, db)
		AudioServer.set_bus_mute(i, db <= MusicManager.MIN_DB)


func _warm_up() -> void:
	for slot: String in SLOTS.keys():
		_stream(slot)
		await get_tree().process_frame
	for loop: String in LOOPS.keys():
		_stream(loop)
		await get_tree().process_frame
	_ready_done = true


# --- One-shots --------------------------------------------------------------------------------

## Plays a named slot. Same slot never overlaps itself; repeats inside the cooldown are dropped.
func play(slot: String, pitch := 1.0) -> void:
	if Engine.is_editor_hint() or not SLOTS.has(slot):
		return
	var spec: Array = SLOTS[slot]
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(slot, -99.0)) < float(spec[2]):
		return
	_last[slot] = now
	var p: AudioStreamPlayer = _players.get(slot)
	if p == null:
		p = AudioStreamPlayer.new()
		p.name = "Slot_" + slot
		p.bus = spec[0]
		add_child(p)
		_players[slot] = p
	var st := _stream(slot)
	if st == null:
		return
	p.stream = st
	p.volume_db = float(spec[1])
	p.pitch_scale = pitch
	p.play()


func last_played(slot: String) -> float:
	return float(_last.get(slot, -1.0))


func _stream(slot: String) -> AudioStream:
	if _streams.has(slot):
		return _streams[slot]
	var st: AudioStream = null
	for ext in [".ogg", ".wav", ".mp3"]:
		var path: String = SFX_DIR + slot + ext
		if ResourceLoader.exists(path):
			st = load(path)
			break
	if st == null:
		st = _synth(slot)
	_streams[slot] = st
	return st


# --- Loops and music states -----------------------------------------------------------------------

## Fades a looping layer to on (1) or off (0) over FADE seconds; never cuts abruptly
func set_layer(loop: String, on: bool, fade := FADE) -> void:
	if Engine.is_editor_hint() or not LOOPS.has(loop):
		return
	var spec: Array = LOOPS[loop]
	var p: AudioStreamPlayer = _loops.get(loop)
	if p == null:
		if not on:
			return
		p = AudioStreamPlayer.new()
		p.name = "Loop_" + loop
		p.bus = spec[0]
		p.volume_db = -60.0
		add_child(p)
		_loops[loop] = p
	if _loop_tweens.has(loop) and (_loop_tweens[loop] as Tween).is_valid():
		(_loop_tweens[loop] as Tween).kill()
	if on and not p.playing:
		var st := _stream(loop)
		if st == null:
			return
		p.stream = st
		p.volume_db = -60.0
		p.play()
	var target := float(spec[1]) if on else -60.0
	var tw := create_tween()
	tw.tween_property(p, "volume_db", target, fade).set_trans(Tween.TRANS_SINE)
	if not on:
		tw.tween_callback(p.stop)
	_loop_tweens[loop] = tw


func layer_on(loop: String) -> bool:
	var p: AudioStreamPlayer = _loops.get(loop)
	return p != null and p.playing and p.volume_db > -40.0


## Music colour per screen: map (full), meeting (filtered, a little lower, thinking room),
## critical (dipped), result_success / result_reflect, report. Cross-fades over 1.2 s.
func set_music_state(state: String) -> void:
	if state == _music_state or Engine.is_editor_hint():
		return
	_music_state = state
	var cutoff := 20000.0
	var gain := 0.0
	match state:
		"meeting":
			cutoff = 2600.0
			gain = -2.5
		"critical":
			cutoff = 1400.0
			gain = -8.0
		"result_reflect":
			cutoff = 1800.0
			gain = -3.0
		"report":
			cutoff = 6000.0
			gain = -1.5
	if _lowpass == null or _amplify == null:
		_install_effects()
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	if _lowpass:
		_music_tween.tween_property(_lowpass, "cutoff_hz", cutoff, FADE).set_trans(Tween.TRANS_SINE)
	if _amplify:
		_music_tween.tween_property(_amplify, "volume_db", gain, FADE).set_trans(Tween.TRANS_SINE)
	music_state_changed.emit(state)


func music_state() -> String:
	return _music_state


## Room tone on while a game screen is up
func set_ambience(on: bool) -> void:
	set_layer("ambience_room", on, 1.5)


func stop_tension_layers() -> void:
	for l in ["tension_warn", "tension_danger", "tension_critical"]:
		set_layer(l, false, 0.9)


# --- Synthesis (replaceable placeholders, soft and short) ------------------------------------------

func _synth(slot: String) -> AudioStreamWAV:
	match slot:
		"ui_hover": return _tone([1320.0], 0.035, 0.12, 0.004)
		"ui_click": return _tone([880.0, 1320.0], 0.05, 0.22, 0.003)
		"ui_back": return _arp([880.0, 659.25], 0.06, 0.16)
		"dice_roll": return _rattle(0.9)
		"dice_land": return _thud(0.22, 140.0, 0.5)
		"piece_step": return _tone([660.0], 0.06, 0.16, 0.004)
		"clue_scan": return _sweep(500.0, 1700.0, 0.32, 0.12)
		"card_flip": return _noise_burst(0.09, 0.25, 0.35)
		"gold_scan": return _sweep(900.0, 2400.0, 0.4, 0.08)
		"trust_up": return _arp([587.33, 880.0], 0.13, 0.2)
		"trust_down": return _arp([392.0, 293.66], 0.16, 0.2)
		"budget_over": return _arp([329.63, 311.13], 0.14, 0.2)
		"compliance_risk": return _thud(0.35, 92.0, 0.42)
		"event_minor": return _arp([523.25, 659.25], 0.14, 0.16)
		"event_major": return _impact(0.7)
		"mission_success": return _arp([523.25, 659.25, 783.99, 1046.5], 0.12, 0.18)
		"mission_fail": return _arp([440.0, 392.0, 329.63], 0.18, 0.16)
		"node_unlock": return _arp([783.99, 1174.66], 0.14, 0.16)
		"xp_gain": return _arp([987.77, 1318.5], 0.08, 0.14)
		"confirm_soft": return _arp([659.25, 987.77], 0.1, 0.16)
		"timer_warn": return _arp([698.46, 523.25], 0.16, 0.18)
		"timer_tick": return _thud(0.12, 110.0, 0.36)
		"timer_tick_strong": return _thud(0.16, 120.0, 0.5)
		"heartbeat": return _heartbeat(0.75)
		"toast": return _tone([1046.5], 0.08, 0.1, 0.006)
		"page_whoosh": return _noise_burst(0.28, 0.12, 0.08)
		"tension_warn": return _pulse_loop(70.0, 2, 58.0, 0.32, false)
		"tension_danger": return _pulse_loop(96.0, 4, 62.0, 0.36, true)
		"tension_critical": return _pulse_loop(60.0, 2, 52.0, 0.4, false, true)
		"ambience_room": return _room_tone(4.0)
	return null


func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _env(t: float, dur: float, attack: float) -> float:
	if t < attack:
		return t / maxf(attack, 0.0001)
	return pow(maxf(0.0, 1.0 - (t - attack) / maxf(0.0001, dur - attack)), 2.0)


func _tone(freqs: Array, dur: float, vol: float, attack := 0.005) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / MIX_RATE
		var v := 0.0
		for f in freqs:
			v += sin(TAU * float(f) * t)
		s[i] = v / freqs.size() * vol * _env(t, dur, attack)
	return _wav(s)


func _arp(freqs: Array, step: float, vol: float) -> AudioStreamWAV:
	var dur := step * freqs.size() + 0.25
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for k in range(freqs.size()):
		var start := int(k * step * MIX_RATE)
		var f: float = freqs[k]
		var len_n := int((step + 0.25) * MIX_RATE)
		for i in range(len_n):
			var idx := start + i
			if idx >= n:
				break
			var t := float(i) / MIX_RATE
			var e := _env(t, step + 0.25, 0.006)
			s[idx] += (sin(TAU * f * t) + 0.25 * sin(TAU * f * 2.0 * t)) * vol * e * 0.8
	return _wav(s)


func _sweep(f0: float, f1: float, dur: float, vol: float) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / MIX_RATE
		var f := lerpf(f0, f1, t / dur)
		phase += TAU * f / MIX_RATE
		var e := sin(PI * t / dur)
		s[i] = sin(phase) * vol * e
	return _wav(s)


func _noise_burst(dur: float, vol: float, smooth: float) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	for i in range(n):
		var t := float(i) / MIX_RATE
		y = lerpf(y, randf_range(-1.0, 1.0), smooth)
		s[i] = y * vol * sin(PI * t / dur)
	return _wav(s)


func _thud(dur: float, f: float, vol: float) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / MIX_RATE
		var ff := f * (1.0 + 0.6 * exp(-t * 30.0))
		phase += TAU * ff / MIX_RATE
		s[i] = sin(phase) * vol * _env(t, dur, 0.004)
	return _wav(s)


func _rattle(dur: float) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var hits := 9
	for k in range(hits):
		var at := int((0.04 + k * dur / hits * (0.8 + randf() * 0.3)) * MIX_RATE)
		var len_n := int(0.05 * MIX_RATE)
		var f := randf_range(900.0, 1500.0)
		for i in range(len_n):
			if at + i >= n:
				break
			var t := float(i) / MIX_RATE
			s[at + i] += (sin(TAU * f * t) * 0.4 + randf_range(-0.3, 0.3)) * exp(-t * 70.0) * 0.32 * (1.0 - float(k) / hits * 0.5)
	return _wav(s)


func _impact(dur: float) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	var y := 0.0
	for i in range(n):
		var t := float(i) / MIX_RATE
		phase += TAU * (55.0 + 40.0 * exp(-t * 8.0)) / MIX_RATE
		y = lerpf(y, randf_range(-1.0, 1.0), 0.05)
		s[i] = (sin(phase) * 0.55 + y * 0.18) * _env(t, dur, 0.008)
	return _wav(s)


func _heartbeat(dur: float) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for beat in [0.0, 0.22]:
		var at := int(beat * MIX_RATE)
		var len_n := int(0.16 * MIX_RATE)
		var phase := 0.0
		for i in range(len_n):
			if at + i >= n:
				break
			var t := float(i) / MIX_RATE
			phase += TAU * (62.0 + 30.0 * exp(-t * 25.0)) / MIX_RATE
			s[at + i] += sin(phase) * 0.55 * exp(-t * 18.0) * (1.0 if beat == 0.0 else 0.7)
	return _wav(s)


## Low beat loop: bpm, beats per loop, sub frequency, level; danger adds an off-beat, critical a drone
func _pulse_loop(bpm: float, beats: int, f: float, vol: float, offbeat: bool, drone := false) -> AudioStreamWAV:
	var beat := 60.0 / bpm
	var dur := beat * beats
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for k in range(beats * (2 if offbeat else 1)):
		var at := int(k * beat / (2.0 if offbeat else 1.0) * MIX_RATE)
		var strong := not offbeat or k % 2 == 0
		var len_n := int(0.22 * MIX_RATE)
		var phase := 0.0
		for i in range(len_n):
			if at + i >= n:
				break
			var t := float(i) / MIX_RATE
			phase += TAU * f * (1.0 + 0.5 * exp(-t * 28.0)) / MIX_RATE
			s[at + i] += sin(phase) * vol * exp(-t * 14.0) * (1.0 if strong else 0.45)
	if drone:
		for i in range(n):
			var t := float(i) / MIX_RATE
			s[i] += sin(TAU * 41.2 * t) * 0.08 * (0.8 + 0.2 * sin(TAU * t / dur))
	return _wav(s, true)


## Soft filtered noise that loops without a seam (end blended into start)
func _room_tone(dur: float) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	var z := 0.0
	for i in range(n):
		y = lerpf(y, randf_range(-1.0, 1.0), 0.02)
		z = lerpf(z, y, 0.05)
		s[i] = z * 0.9
	var blend := int(0.5 * MIX_RATE)
	for i in range(blend):
		var a := float(i) / blend
		s[i] = s[i] * a + s[n - blend + i] * (1.0 - a)
	var trimmed := s.slice(0, n - blend)
	return _wav(trimmed, true)
