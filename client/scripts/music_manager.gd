extends Node
## Global audio (autoload "MusicManager"): background music, the four audio buses and their saved volumes.
## Buses: Master, BGM (music), Voice (secretary speech), SFX (buttons, hints, mission complete).
## Music starts on the player's 「進入顧問培訓」 click (never on web page load), keeps playing through
## screen changes and returns to the cover, and dips while the secretary speaks.
## Secretary speech is browser / OS text-to-speech, which bypasses Godot's mixer, so the Voice bus
## volume (with Master and mute) is applied to each spoken line's TTS volume.

signal volumes_changed

const BUSES := ["Master", "BGM", "Voice", "SFX"]
const DEFAULT_DB := {"Master": 0.0, "BGM": -16.0, "Voice": -3.0, "SFX": -8.0}
## Sliders run 0..100 over MIN_DB..0 dB; 0 silences the bus
const MIN_DB := -40.0
## While the secretary speaks the music dips to DUCK_DB in DUCK_IN s and recovers in DUCK_OUT s
const DUCK_DB := -24.0
const DUCK_IN := 0.2
const DUCK_OUT := 0.5
const FADE_IN := 1.5
const SETTINGS_PATH := "user://audio_settings.cfg"
const THEME_PATH := "res://assets/audio/late_night_ledger.ogg"
## The file ends with the song's tail mixed over its first 3.95 s, so the loop resumes right after that
const THEME_LOOP_OFFSET := 3.95

var volume_db := DEFAULT_DB.duplicate()
var muted := false
var ducked := false
var _player: AudioStreamPlayer
var _bgm_db: float = DEFAULT_DB.BGM
var _duck_tween: Tween
var _fade_tween: Tween
## Id of the line currently speaking; end / cancel reports for older lines are ignored
var _utterance := 0
var _speech_timer: Timer
var _save_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	load_settings()
	_player = AudioStreamPlayer.new()
	_player.name = "Theme"
	_player.bus = "BGM"
	add_child(_player)
	_speech_timer = _one_shot(func(): _end_speech(_utterance))
	_save_timer = _one_shot(save_settings)
	if _tts_available():
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _end_speech)
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, _end_speech)


# --- Music -------------------------------------------------------------------------------------

## Starts the theme with a short fade-in. Does nothing while it already plays, so screen changes and
## returning to the cover never restart the song.
func play_music() -> void:
	if _player.playing:
		return
	if _player.stream == null:
		var theme := load(THEME_PATH) as AudioStreamOggVorbis
		if theme == null:
			push_warning("MusicManager: missing " + THEME_PATH)
			return
		theme.loop = true
		theme.loop_offset = THEME_LOOP_OFFSET
		_player.stream = theme
	_player.volume_db = MIN_DB
	_player.play()
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_player, "volume_db", 0.0, FADE_IN)


func is_music_playing() -> bool:
	return _player != null and _player.playing


# --- Volumes -----------------------------------------------------------------------------------

func get_volume_db(bus: String) -> float:
	return float(volume_db.get(bus, 0.0))


func set_volume_db(bus: String, db: float) -> void:
	if not volume_db.has(bus):
		return
	volume_db[bus] = clampf(db, MIN_DB, 0.0)
	_apply()
	_save_timer.start(0.4)


func set_muted(on: bool) -> void:
	muted = on
	_apply()
	_save_timer.start(0.4)


static func slider_to_db(value: float) -> float:
	return MIN_DB * (1.0 - clampf(value, 0.0, 100.0) / 100.0)


static func db_to_slider(db: float) -> float:
	return 100.0 * (1.0 - clampf(db, MIN_DB, 0.0) / MIN_DB)


func get_slider(bus: String) -> float:
	return db_to_slider(get_volume_db(bus))


func set_slider(bus: String, value: float) -> void:
	set_volume_db(bus, slider_to_db(value))


## Current BGM bus level (follows the player's setting, lower while ducked)
func bgm_bus_db() -> float:
	return _bgm_db


func _bgm_target() -> float:
	var user := get_volume_db("BGM")
	return minf(user, DUCK_DB) if ducked else user


func _apply() -> void:
	AudioServer.set_bus_mute(0, muted or get_volume_db("Master") <= MIN_DB)
	AudioServer.set_bus_volume_db(0, get_volume_db("Master"))
	for bus: String in ["Voice", "SFX"]:
		var i := AudioServer.get_bus_index(bus)
		AudioServer.set_bus_volume_db(i, get_volume_db(bus))
		AudioServer.set_bus_mute(i, get_volume_db(bus) <= MIN_DB)
	if _duck_tween:
		_duck_tween.kill()
	_apply_bgm(_bgm_target())
	volumes_changed.emit()


func _apply_bgm(db: float) -> void:
	_bgm_db = db
	var i := AudioServer.get_bus_index("BGM")
	AudioServer.set_bus_volume_db(i, db)
	AudioServer.set_bus_mute(i, get_volume_db("BGM") <= MIN_DB)


func _ensure_buses() -> void:
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for bus: String in BUSES:
			volume_db[bus] = clampf(float(cfg.get_value("audio", bus, DEFAULT_DB[bus])), MIN_DB, 0.0)
		muted = bool(cfg.get_value("audio", "muted", false))
	_apply()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for bus: String in BUSES:
		cfg.set_value("audio", bus, volume_db[bus])
	cfg.set_value("audio", "muted", muted)
	cfg.save(SETTINGS_PATH)


# --- Secretary speech --------------------------------------------------------------------------

## TTS volume 0..100 from the Voice and Master sliders; 0 when muted
func tts_volume() -> int:
	if muted or get_volume_db("Voice") <= MIN_DB or get_volume_db("Master") <= MIN_DB:
		return 0
	return clampi(roundi(100.0 * db_to_linear(get_volume_db("Voice") + get_volume_db("Master"))), 1, 100)


## Speaks one secretary line at the Voice volume and dips the music until it ends.
## Returns false when speech is silenced (mute / Voice at 0 / no TTS), so the caller keeps subtitles only.
func speak(text: String, voice_id: String) -> bool:
	var vol := tts_volume()
	if vol <= 0 or voice_id == "" or not _tts_available():
		return false
	_utterance += 1
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(text, voice_id, vol, 1.0, 1.0, _utterance)
	_set_ducked(true)
	# Fallback for platforms that never report the end of an utterance
	_speech_timer.start(1.5 + text.length() * 0.3)
	return true


func stop_speech() -> void:
	if _tts_available():
		DisplayServer.tts_stop()
	_end_speech(_utterance)


func _end_speech(id: int) -> void:
	if id != _utterance:
		return
	_speech_timer.stop()
	_set_ducked(false)


func _set_ducked(on: bool) -> void:
	if on == ducked:
		return
	ducked = on
	if _duck_tween:
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_method(_apply_bgm, _bgm_db, _bgm_target(), DUCK_IN if on else DUCK_OUT)


func _tts_available() -> bool:
	return DisplayServer.get_name() != "headless" and bool(ProjectSettings.get_setting("audio/general/text_to_speech", false))


func _one_shot(cb: Callable) -> Timer:
	var t := Timer.new()
	t.one_shot = true
	t.timeout.connect(cb)
	add_child(t)
	return t
