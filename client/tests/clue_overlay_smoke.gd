extends SceneTree
## Run: godot --headless --path client --script res://tests/clue_overlay_smoke.gd
## The clues page never stays locked: 單人培訓 → 接受任務 → 看客戶線索 → 跳過導覽 → 下一步：選工具,
## with animations on and real clicks; the dim only stands while its dialog is up, every page
## switch resets it, and without a secretary no dim layer exists at all. While the clue tutorial is
## still talking, 下一步：選工具 is bright, takes the click and ends the tutorial.

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


class MainStub extends Control:
	var guide: Control
	func secretary_guide() -> Control:
		return guide


class GameStub extends Control:
	var main: Node = null


## pos is in canvas units; push_input expects window pixels
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


func _next_button(cs: Control) -> Control:
	for b in cs._page.find_children("*", "Button", true, false):
		if b.get("text_value") == "下一步：選工具":
			return b
	return null


## Main stub with the secretary layer and a case setup inside a game stub
func _scene(secretary: bool) -> Array:
	var GuideScript: GDScript = load("res://scripts/ui/training_secretary.gd")
	var main := MainStub.new()
	main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(main)
	var game := GameStub.new()
	game.main = main
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main.add_child(game)
	var g: Control = GuideScript.new()
	main.add_child(g)
	main.guide = g
	await process_frame
	g.choose(secretary, "female")
	g._seen_states = []
	g.screen_changed("game")
	var cs: Control = load("res://scripts/ui/case_setup.gd").new()
	cs.z_index = 110
	game.add_child(cs)
	await _wait(0.8)
	return [main, g, cs]


func _run() -> void:
	var GuideScript: GDScript = load("res://scripts/ui/training_secretary.gd")
	var prefs: String = GuideScript.PREFS
	var had := FileAccess.file_exists(prefs)
	var backup := FileAccess.get_file_as_string(prefs) if had else ""
	UI.reduce_motion = false
	var opts := [{"id": "yuqing", "name": "林雨晴", "age": 29, "job": "自由接案插畫家", "difficulty": "入門", "family": "單身", "incomeInfo": "月收入 3–8 萬不等", "amount": "NT$ 600,000", "goal": "工作室", "intro": "接案"}]
	root.get_node("Net").set("state", {"phase": "playing", "caseOptions": opts, "codex": [], "briefcaseSize": 3,
		"tools": [{"id": "needs_form"}, {"id": "cashflow"}, {"id": "compliance_check"}]})

	# With a secretary: entry tutorial → accept → clues tutorial → 跳過 → 下一步
	var r := await _scene(true)
	var g: Control = r[1]
	var cs: Control = r[2]
	var ov: Control = g._overlay
	check(g.is_open() and ov.dialog_showing(), "mission page: tutorial with its dialog")
	for i in range(4):
		if g._open and g._modal:
			g._line_done()
			await _click(ov._continue.get_global_rect().get_center())
	check(not ov.visible and ov.mouse_filter == Control.MOUSE_FILTER_IGNORE, "我知道了 hides the dim at once")
	await _click(cs._accept.get_global_rect().get_center())
	check(cs._accepting, "accept reached the button")
	await _wait(2.2)
	check(cs._step == 2, "clues page (step %d)" % cs._step)
	check(is_equal_approx(cs._page.modulate.a, 1.0), "clues page fully shown (alpha %.2f)" % cs._page.modulate.a)
	check(g.is_open() and ov.visible and ov.dialog_showing(), "clue tutorial shows its dialog with the dim")
	await _click(ov._skip.get_global_rect().get_center())
	check(not g.is_open() and not ov.visible and ov.mouse_filter == Control.MOUSE_FILTER_IGNORE, "跳過: dim hidden, clicks pass")
	check(ov._shade.mouse_filter == Control.MOUSE_FILTER_IGNORE, "跳過: dim no longer catches clicks")
	var next := _next_button(cs)
	check(next != null, "下一步 button on the clues page")
	await _click(next.get_global_rect().get_center())
	await _wait(0.8)
	check(cs._step == 3 and cs._briefcase != null, "下一步 opens the briefcase (step %d)" % cs._step)
	check(is_equal_approx(cs._page.modulate.a, 1.0), "briefcase page fully shown")
	# Leaving the page while its tutorial is up: the next page starts unlocked, then teaches
	check(g.is_open() and ov.dialog_showing(), "tool tutorial up")
	cs.queue_free()
	await process_frame
	check(not ov.visible and not g._modal, "leaving the case setup resets the dim")
	(r[0] as Node).queue_free()
	await _wait(0.1)

	# Clue tutorial still up: 下一步：選工具 is bright, takes the click and ends the tutorial
	r = await _scene(true)
	g = r[1]
	cs = r[2]
	ov = g._overlay
	for i in range(4):
		if g._open and g._modal:
			g._line_done()
			await _click(ov._continue.get_global_rect().get_center())
	await _click(cs._accept.get_global_rect().get_center())
	await _wait(2.2)
	check(cs._step == 2 and g.is_open() and ov.visible and ov.dialog_showing(), "clue tutorial up (step %d)" % cs._step)
	next = _next_button(cs)
	var at: Vector2 = next.get_global_rect().get_center()
	check(ov.passes_click(at - ov.get_global_rect().position), "下一步 is a bright, pressable element of the clue tutorial")
	check(not ov.passes_click(cs._clue_sheet.get_global_rect().get_center() - ov.get_global_rect().position), "the clue sheet stays bright but locked")
	var wat: Vector2 = root.get_final_transform() * at
	var mm := InputEventMouseMotion.new()
	mm.position = wat
	mm.global_position = wat
	root.push_input(mm)
	await process_frame
	var hov := root.gui_get_hovered_control()
	check(hov == next or (hov != null and next.is_ancestor_of(hov)), "下一步 takes the mouse through the dim (got %s)" % str(hov))
	await _click(at)
	await _wait(0.8)
	check(cs._step == 3 and cs._briefcase != null, "下一步 during the tutorial opens the briefcase (step %d)" % cs._step)
	check(not ov.dialog_showing() or str(g._active_key).ends_with("tool_selection"), "the clue tutorial ended (%s)" % g._active_key)
	check(ov.visible == ov.dialog_showing(), "no dim without a dialog")
	(r[0] as Node).queue_free()
	await _wait(0.1)

	# Re-entering the clues page with a tutorial up resets it before the new page
	r = await _scene(true)
	g = r[1]
	cs = r[2]
	ov = g._overlay
	g._close_modal(true)
	cs._ready_to_accept = true
	cs._accept.set_enabled(true)
	cs._on_accept()
	g.show_states(["locked_client_info"], {})
	check(g._modal and ov.visible, "a tutorial is up during the unlock")
	cs._go_step(2)
	check(not ov.visible or ov.dialog_showing(), "page switch: no dim without a dialog")
	await _wait(0.8)
	check(cs._step == 2 and is_equal_approx(cs._page.modulate.a, 1.0), "clues page built and shown")
	g._close_modal(true)
	await _click(_next_button(cs).get_global_rect().get_center())
	await _wait(0.8)
	check(cs._step == 3, "下一步 works after a reset")
	(r[0] as Node).queue_free()
	await _wait(0.1)

	# 自行挑戰: no dim layer is ever created; the whole flow clicks through
	r = await _scene(false)
	g = r[1]
	cs = r[2]
	check(g._overlay == null, "no secretary: no dim layer")
	await _click(cs._accept.get_global_rect().get_center())
	await _wait(2.2)
	check(cs._step == 2 and g._overlay == null, "no secretary: clues page without a dim")
	await _click(_next_button(cs).get_global_rect().get_center())
	await _wait(0.8)
	check(cs._step == 3 and g._overlay == null, "no secretary: 下一步 works")
	(r[0] as Node).queue_free()
	await _wait(0.1)

	if had:
		var f := FileAccess.open(prefs, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	elif FileAccess.file_exists(prefs):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs))
	print("clue_overlay_smoke: ", "OK" if failures == 0 else "%d failure(s)" % failures)
	quit(1 if failures else 0)
