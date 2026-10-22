extends SceneTree
## Run: godot --headless --path client --script res://tests/secretary_modal_smoke.gd
## 強制聚焦導覽: the dim swallows clicks, the explained element stays bright, 「跳過」 sits top-right
## clear of the portrait, 「繼續」/「我知道了」 appear after the line, and every exit unlocks the screen.

var failures := 0
var behind_pressed := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


## pos is in canvas units; push_input expects window pixels (the stretch transform applies)
func _click(pos: Vector2) -> void:
	var wpos: Vector2 = root.get_final_transform() * pos
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = wpos
		e.global_position = wpos
		root.push_input(e)
		await process_frame


func _run() -> void:
	var GuideScript: GDScript = load("res://scripts/ui/training_secretary.gd")
	var prefs: String = GuideScript.PREFS
	var had := FileAccess.file_exists(prefs)
	var backup := FileAccess.get_file_as_string(prefs) if had else ""

	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	# A button "behind" the tutorial
	var behind := Button.new()
	behind.text = "背後按鈕"
	behind.position = Vector2(560, 300)
	behind.size = Vector2(160, 60)
	behind.pressed.connect(func(): behind_pressed += 1)
	holder.add_child(behind)
	var g: Control = GuideScript.new()
	holder.add_child(g)
	await process_frame
	# Baseline: without a tutorial the button is clickable
	await _click(behind.get_global_rect().get_center())
	check(behind_pressed == 1, "baseline click reaches the button")
	behind_pressed = 0
	g.choose(true, "male")
	g._seen_states = []
	g.screen_changed("game")
	var ov: Control = g._overlay

	# Open: dim, bright target, lock
	g.show_states(["training_entry", "first_assignment"], {"training_entry": [behind]})
	await _wait(0.4)
	check(g.is_open() and ov.visible and ov.is_shown, "tutorial overlay shown")
	check(ov._shade.mouse_filter == Control.MOUSE_FILTER_STOP, "dim intercepts the mouse")
	check(ov.holes().size() == 1 and (ov.holes()[0] as Rect2).encloses(behind.get_global_rect()), "explained element kept bright")
	check((ov._dialog.get_theme_stylebox("panel") as StyleBoxFlat).border_color == Color("#C6A15B"), "gold dialog frame")
	check(ov._heading.text.begins_with("男性培訓秘書"), "Kevin's dialog")
	var skip_rect: Rect2 = ov._skip.get_global_rect()
	var view := root.get_visible_rect().size
	check(skip_rect.end.x > view.x * 0.8 and skip_rect.position.y < view.y * 0.15, "跳過 sits top-right (%s)" % str(skip_rect))
	check(not skip_rect.intersects(ov._portrait.get_global_rect()), "跳過 not covered by the portrait")
	await _click(behind.get_global_rect().get_center())
	check(behind_pressed == 0, "clicks do not reach the interface behind")
	check(not ov._continue.visible, "no 繼續 before the line is spoken")
	check(ov._progress > 0.0, "voice / subtitle progress advances")

	# Line spoken → 繼續 (more lines) → 我知道了 (last)
	g._line_done()
	check(ov._continue.visible and ov._continue.text == "繼續", "繼續 after the first line")
	g._on_continue()
	g._line_done()
	check(not ov.visible and ov._shade.mouse_filter == Control.MOUSE_FILTER_IGNORE, "last line automatically unlocks without another click")
	g._on_continue()
	check(not g.is_open() and ov._shade.mouse_filter == Control.MOUSE_FILTER_IGNORE, "我知道了 unlocks at once")
	await _wait(0.4)
	check(not ov.visible, "overlay faded out")
	await _click(behind.get_global_rect().get_center())
	check(behind_pressed == 1, "interface usable again after 我知道了")

	# 跳過 mid-line: stops and unlocks immediately
	g.replay()
	await _wait(0.2)
	check(g.is_open() and ov.visible, "replay from the portrait opens the tutorial again")
	ov.skip_pressed.emit()
	check(not g.is_open() and not ov.visible, "跳過 closes immediately")
	await _click(behind.get_global_rect().get_center())
	check(behind_pressed == 2, "interface usable again after 跳過")

	# Screen change during a tutorial never leaves the lock behind
	g._seen_states = []
	g.show_states(["clue_review"])
	g.screen_changed("menu")
	check(not g.is_open() and not ov.visible and ov._shade.mouse_filter == Control.MOUSE_FILTER_IGNORE, "screen change unlocks")

	# Seen tutorials are not forced again
	g.screen_changed("game")
	g.show_states(["clue_review"])
	check(not g.is_open(), "seen tutorial not forced again")

	# A dim never stands without its dialog: the guard releases it on the next frame
	g.show_states(["tool_selection"], {}, true)
	g._seen_states.erase("tool_selection")
	g._close_modal(true)
	ov.visible = true
	ov._shade.mouse_filter = Control.MOUSE_FILTER_STOP
	await process_frame
	await process_frame
	check(not ov.visible and ov.mouse_filter == Control.MOUSE_FILTER_IGNORE, "stray dim without a dialog is released")
	await _click(behind.get_global_rect().get_center())
	check(behind_pressed == 3, "interface usable after a stray dim")

	# Page switch while a tutorial is up: reset_overlay unlocks at once
	g.show_states(["tool_selection"])
	check(g.is_open() and ov.visible, "tutorial up before the page switch")
	g.reset_overlay()
	check(not g.is_open() and not ov.visible and ov.mouse_filter == Control.MOUSE_FILTER_IGNORE, "page switch resets the dim")

	# No secretary: the dim layer is never created
	g.choose(false, "female")
	await process_frame
	g._seen_states = []
	g.show_states(["meeting_ready"])
	check(not g.is_open() and g._overlay == null and not is_instance_valid(ov), "no secretary: no tutorial overlay")

	holder.queue_free()
	await process_frame
	if had:
		var f := FileAccess.open(prefs, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	elif FileAccess.file_exists(prefs):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs))
	print("secretary_modal_smoke: ", "OK" if failures == 0 else "%d failure(s)" % failures)
	quit(1 if failures else 0)
