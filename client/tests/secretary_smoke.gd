extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var guide = load("res://scripts/ui/training_secretary.gd").new()
	root.add_child(guide)
	# No preference writes: assert behavior using in-memory settings.
	guide.enabled = false
	guide.screen_changed("menu")
	assert(not guide.is_open(), "Opt-out must have no guide UI")
	guide.enabled = true
	guide.show_lines("first", ["第一句", "第二句"])
	assert(guide.is_open())
	assert(guide._subtitle.text == "第一句")
	guide._advance()
	assert(guide._subtitle.text == "第二句")
	guide.dismiss()
	guide.show_lines("first", ["第一句", "第二句"])
	assert(not guide.is_open(), "Refresh must not reopen a dismissed guide")
	guide.show_lines("second", ["新階段"])
	assert(guide.is_open())
	guide.screen_changed("records")
	assert(not guide.is_open(), "Leaving a screen must dismiss narration")
	guide.begin_training()
	guide.show_lines("first", ["新訓練"])
	assert(guide.is_open(), "New training can guide again")
	guide.enabled = false
	guide.dismiss()
	guide.screen_changed("report")
	assert(not guide.is_open())
	# Verify the actual opt-out path and reload, restoring any existing preference.
	var prefs_path: String = guide.PREFS
	var had_preferences := FileAccess.file_exists(prefs_path)
	var previous_preferences := FileAccess.get_file_as_string(prefs_path) if had_preferences else ""
	guide.choose(true, "male")
	guide.show_lines("portrait", ["封面人物"])
	assert((guide._portrait.texture as AtlasTexture).atlas == guide.MALE, "Kevin uses the cover portrait")
	guide.choose(false, "female")
	assert(not guide.is_open() and not guide.enabled and not guide._speech_unlocked)
	guide.screen_changed("menu")
	assert(not guide.is_open())
	var reloaded = load("res://scripts/ui/training_secretary.gd").new()
	root.add_child(reloaded)
	assert(reloaded.configured and not reloaded.enabled, "Opt-out persists across launches")
	reloaded.screen_changed("menu")
	assert(not reloaded.is_open())
	reloaded.queue_free()
	if had_preferences:
		var saved := FileAccess.open(prefs_path, FileAccess.WRITE)
		saved.store_string(previous_preferences)
		saved.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs_path))
	guide.queue_free()
	await process_frame
	print("SECRETARY_SMOKE_OK: opt-out persistence, cover portraits, subtitles, next, skip deduplication, scene exit, training reset")
	quit()

