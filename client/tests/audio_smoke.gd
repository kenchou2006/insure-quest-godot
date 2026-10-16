extends SceneTree
## Run: godot --headless --path client --script res://tests/audio_smoke.gd
## Buses, default volumes, ducking, mute isolation, saved settings, music continuity and the loop seam.

const MusicManagerScript := preload("res://scripts/music_manager.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _run() -> void:
	# Keep the player's real settings file untouched
	var path: String = MusicManagerScript.SETTINGS_PATH
	var backup := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	var mm: Node = root.get_node_or_null("MusicManager")
	if mm == null:
		mm = MusicManagerScript.new()
		mm.name = "MusicManager"
		root.add_child(mm)
	mm.load_settings()

	# 1. Four buses, all routed to Master
	for bus: String in ["Master", "BGM", "Voice", "SFX"]:
		check(AudioServer.get_bus_index(bus) != -1, "bus %s exists" % bus)
	for bus: String in ["BGM", "Voice", "SFX"]:
		check(AudioServer.get_bus_send(AudioServer.get_bus_index(bus)) == "Master", "%s sends to Master" % bus)

	# 2. Defaults: BGM -16, Voice -3, SFX -8
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("BGM")), -16.0), "BGM default -16 dB")
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Voice")), -3.0), "Voice default -3 dB")
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), -8.0), "SFX default -8 dB")
	check(mm.tts_volume() == roundi(100.0 * db_to_linear(-3.0)), "TTS volume follows Voice (-3 dB → 71)")

	# 3. Ducking: down to -24 within 0.2 s, back to the player's level within 0.5 s
	mm._set_ducked(true)
	await _wait(0.3)
	check(is_equal_approx(mm.bgm_bus_db(), -24.0), "ducked to -24 dB (got %.1f)" % mm.bgm_bus_db())
	mm._end_speech(mm._utterance)
	await _wait(0.6)
	check(is_equal_approx(mm.bgm_bus_db(), -16.0), "restored to -16 dB (got %.1f)" % mm.bgm_bus_db())
	# A quieter player setting is never raised by ducking
	mm.set_volume_db("BGM", -30.0)
	mm._set_ducked(true)
	await _wait(0.3)
	check(is_equal_approx(mm.bgm_bus_db(), -30.0), "ducking keeps a lower player level")
	mm._end_speech(mm._utterance)
	await _wait(0.6)
	# A stale end report (older line) does not lift the duck of the current line
	mm._set_ducked(true)
	mm._end_speech(mm._utterance - 1)
	check(mm.ducked, "old utterance end ignored")
	mm._end_speech(mm._utterance)
	await _wait(0.6)

	# 4. Music off: voice and SFX still play
	mm.set_slider("BGM", 0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("BGM")), "BGM slider 0 mutes BGM")
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Voice")), "Voice unaffected by BGM off")
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "SFX unaffected by BGM off")
	check(not AudioServer.is_bus_mute(0), "Master unaffected by BGM off")
	check(mm.tts_volume() > 0, "secretary still speaks with BGM off")
	Sound.play("click", mm)
	var sfx_player: AudioStreamPlayer = root.get_node_or_null("GlobalSoundPlayer")
	check(sfx_player != null and sfx_player.bus == "SFX", "sound effects play on the SFX bus")
	# Mute silences everything, including speech
	mm.set_muted(true)
	check(AudioServer.is_bus_mute(0), "mute silences Master")
	check(mm.tts_volume() == 0, "mute silences speech")
	mm.set_muted(false)

	# 5. Saved with ConfigFile and restored on the next launch
	mm.set_slider("BGM", 75)
	mm.set_slider("SFX", 30)
	mm.save_settings()
	var fresh: Node = MusicManagerScript.new()
	root.add_child(fresh)
	check(is_equal_approx(fresh.get_slider("BGM"), 75.0), "BGM slider restored")
	check(is_equal_approx(fresh.get_slider("SFX"), 30.0), "SFX slider restored")
	fresh.queue_free()

	# 6. Music: loops, and asking to play again (screen change / back to cover) does not restart it
	mm.play_music()
	var stream: AudioStreamOggVorbis = mm._player.stream
	check(stream != null and stream.loop, "theme is a looping OGG")
	check(stream != null and is_equal_approx(stream.loop_offset, 3.95), "loop offset 3.95 s")
	check(mm.is_music_playing(), "music playing after the enter click")
	check(mm._player.bus == "BGM", "music on the BGM bus")
	mm._player.seek(30.0)
	await _wait(0.2)
	mm.play_music()
	check(mm._player.get_playback_position() >= 30.0, "second play_music() keeps the song position")

	# 7. Loop seam: render across the end of the file; no silent gap
	if stream != null:
		var pb := stream.instantiate_playback()
		if pb.has_method("mix_audio"):
			var length := stream.get_length()
			pb.start(length - 0.5)
			var frames: PackedVector2Array = PackedVector2Array()
			for i in range(20):
				frames.append_array(pb.mix_audio(1.0, 2205))
			var win := 441
			var worst := 0.0
			var lowest := 1.0
			for i in range(0, frames.size() - win, win):
				var acc := 0.0
				for k in range(i, i + win):
					acc += frames[k].length_squared() * 0.5
				lowest = minf(lowest, sqrt(acc / win))
				worst = maxf(worst, (frames[i + 1] - frames[i]).length())
			check(linear_to_db(lowest) > -40.0, "no silent gap at the loop seam (lowest 10 ms %.1f dB)" % linear_to_db(lowest))
			check(pb.get_loop_count() == 1, "looped once across the seam")
			check(pb.get_playback_position() > stream.loop_offset and pb.get_playback_position() < stream.loop_offset + 0.6, "resumed after the loop offset")
		else:
			print("audio_smoke: mix_audio unavailable, seam render skipped")

	# Restore the player's settings
	if backup.size() > 0:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	print("audio_smoke: ", "OK" if failures == 0 else "%d failure(s)" % failures)
	quit(1 if failures else 0)
