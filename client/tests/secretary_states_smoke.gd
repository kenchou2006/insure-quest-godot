extends SceneTree
## Run: godot --headless --path client --script res://tests/secretary_states_smoke.gd
## State-driven secretary lines: once per state (saved), queued instead of cut off, replay from the
## corner portrait, Aly / Kevin / none, and a dialog no taller than 20% of the screen.

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var Lines: GDScript = load("res://scripts/secretary_lines.gd")
	var GuideScript: GDScript = load("res://scripts/ui/training_secretary.gd")
	var prefs: String = GuideScript.PREFS
	var had := FileAccess.file_exists(prefs)
	var backup := FileAccess.get_file_as_string(prefs) if had else ""
	if had:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs))

	# All eight states have lines, none mention the old flow
	for st: String in ["training_entry", "first_assignment", "dossier_unlocking", "clue_review", "tool_selection", "meeting_ready", "later_matching", "locked_client_info"]:
		check(Lines.has_state(st) and not Lines.lines(st).is_empty(), "lines for " + st)
		for l: String in Lines.lines(st):
			for old: String in ["請選擇一位客戶", "抽取", "隨機抽", "自己挑", "先選擇公事包", "點擊開始遊戲"]:
				check(not l.contains(old), "%s has no old-flow wording (%s)" % [st, old])

	var holder := Control.new()
	holder.size = Vector2(1280, 720)
	root.add_child(holder)
	var g: Control = GuideScript.new()
	holder.add_child(g)
	g.size = Vector2(1280, 720)
	g.choose(true, "female")
	g.screen_changed("game")

	# Entry: two states in order, female secretary
	g.show_states(["training_entry", "first_assignment"])
	check(g.is_open(), "entry lines open the dialog")
	check(g._subtitle.text == Lines.lines("training_entry")[0], "first line is training_entry")
	check(g._heading.text.begins_with("女性培訓秘書"), "female secretary heading")
	check((g._portrait.texture as AtlasTexture).atlas == g.FEMALE, "female cover portrait")
	check(g._card.size.y <= 720 * 0.2 + 0.5, "dialog at most 20%% of the screen (%.0f)" % g._card.size.y)
	g._advance()
	check(g._subtitle.text == Lines.lines("first_assignment")[0], "second line is first_assignment")
	# Moving to the next step: its line replaces the one playing (no lag behind the screen)
	g.show_states(["dossier_unlocking"])
	check(g._subtitle.text == Lines.lines("dossier_unlocking")[0], "the new step's line plays at once")
	g._collapse()
	check(not g.is_open() and g._icon.visible, "collapses to the corner portrait")

	# Once only, then replay from the portrait
	g.show_states(["training_entry"])
	check(not g.is_open(), "a state plays automatically only once")
	g.replay()
	check(g.is_open(), "portrait replays the current hint")
	g._collapse()

	# Voice off is kept
	g._toggle_voice()
	check(not g.voice_on, "voice can be turned off")

	# Kevin
	g.choose(true, "male")
	g.screen_changed("game")
	g.show_states(["clue_review"])
	check(g._heading.text.begins_with("男性培訓秘書"), "male secretary heading")
	check((g._portrait.texture as AtlasTexture).atlas == g.MALE, "male cover portrait")
	g._collapse()

	# No secretary: nothing at all
	g.choose(false, "female")
	g.screen_changed("game")
	g.show_states(["locked_client_info"])
	check(not g.is_open() and not g._icon.visible, "no secretary: no dialog, no portrait")

	# Saved across launches: choice, seen states, voice setting
	var again: Control = GuideScript.new()
	holder.add_child(again)
	check(again.configured and not again.enabled, "choice persists")
	check((again._seen_states as Array).has("training_entry"), "seen states persist")
	check(not again.voice_on, "voice-off persists")

	holder.queue_free()
	await process_frame
	if had:
		var f := FileAccess.open(prefs, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	elif FileAccess.file_exists(prefs):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs))
	print("secretary_states_smoke: ", "OK" if failures == 0 else "%d failure(s)" % failures)
	quit(1 if failures else 0)
