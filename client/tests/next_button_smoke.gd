extends SceneTree
## Run: godot --headless --path client --script res://tests/next_button_smoke.gd
## 看線索 → 下一步：選工具 with real mouse events: the pointer reaches the button (hover), a click opens
## the briefcase once (fast repeated clicks too), the step bar follows, 林雨晴's data is kept, and
## going back to 看線索 from the briefcase leaves 下一步 working with the packed tools kept.

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
	func toast(_t: String, _c: Color = Color.WHITE, _s := 3.0) -> void:
		pass


class GameStub extends Control:
	var main: Node = null


func _move(pos: Vector2) -> void:
	var w: Vector2 = root.get_final_transform() * pos
	var m := InputEventMouseMotion.new()
	m.position = w
	m.global_position = w
	root.push_input(m)
	await process_frame


func _click(pos: Vector2) -> void:
	await _move(pos)
	var w: Vector2 = root.get_final_transform() * pos
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = w
		e.global_position = w
		root.push_input(e)
		await process_frame


func _next(cs: Control) -> Button:
	return cs._page.find_child("NextToolsButton", true, false) as Button


func _views(cs: Control) -> int:
	return cs.find_children("BriefcaseView", "", true, false).size()


func _run() -> void:
	var GuideScript: GDScript = load("res://scripts/ui/training_secretary.gd")
	var prefs: String = GuideScript.PREFS
	var had := FileAccess.file_exists(prefs)
	var backup := FileAccess.get_file_as_string(prefs) if had else ""
	var opts := [{"id": "yuqing", "name": "林雨晴", "age": 29, "job": "自由接案插畫家", "difficulty": "入門", "family": "單身", "incomeInfo": "月收入 3–8 萬不等", "amount": "NT$ 600,000", "goal": "工作室", "intro": "接案"}]
	root.get_node("Net").set("state", {"phase": "playing", "caseOptions": opts, "codex": [], "briefcaseSize": 3,
		"tools": [{"id": "needs_form"}, {"id": "cashflow"}, {"id": "family_map"}, {"id": "gap_sheet"}, {"id": "risk_survey"}, {"id": "compliance_check"}]})

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
	g.choose(true, "female")
	g._seen_states = ["training_entry", "first_assignment", "dossier_unlocking", "clue_review", "tool_selection", "meeting_ready"]
	g.screen_changed("game")
	var cs: Control = load("res://scripts/ui/case_setup.gd").new()
	cs.z_index = 110
	game.add_child(cs)
	await _wait(0.6)
	await _click(cs._accept.get_global_rect().get_center())
	await _wait(2.0)
	check(cs._step == 2, "看線索 page (step %d)" % cs._step)

	# 1. The pointer reaches the button: hover, then a click opens the briefcase
	var next := _next(cs)
	check(next != null and not next.disabled and next.mouse_filter == Control.MOUSE_FILTER_STOP, "下一步 is an enabled Button that takes the mouse")
	await _move(next.get_global_rect().get_center())
	check(root.gui_get_hovered_control() == next, "hover reaches 下一步 (got %s)" % str(root.gui_get_hovered_control()))
	check(next._visual.self_modulate != Color.WHITE, "hover lights the button")
	# 2. Fast repeated clicks: one switch, one briefcase
	var c := next.get_global_rect().get_center()
	for i in range(4):
		await _click(c)
	await _wait(0.9)
	check(cs._step == 3 and _views(cs) == 1, "fast clicks open the briefcase once (step %d, %d views)" % [cs._step, _views(cs)])
	check(cs._step_items[0].text == "看線索" and cs._step_items[1].state == "active", "step bar shows 選工具 as current")
	check(str(cs.current_customer.get("customer_name", "")) == "林雨晴" and cs.unlocked_clues.size() == 2, "林雨晴's case kept")

	# Pack two tools, then go back to 看線索 with the step bar
	cs._on_toggle_tool("cashflow")
	cs._on_toggle_tool("compliance_check")
	var back: Button = cs.find_child("BackToCluesButton", true, false)
	check(back != null and back.visible, "看線索 step is clickable on the briefcase page")
	await _click(back.get_global_rect().get_center())
	await _wait(0.5)
	check(cs._step == 2 and _views(cs) == 0, "back on 看線索 (step %d)" % cs._step)
	check(cs._tools == ["cashflow", "compliance_check"], "packed tools kept (%s)" % str(cs._tools))
	check(not back.visible, "back link hidden on the clues page")

	# 3. 下一步 works again after coming back, with the tools still packed
	next = _next(cs)
	await _move(next.get_global_rect().get_center())
	check(root.gui_get_hovered_control() == next, "hover reaches 下一步 after coming back")
	await _click(next.get_global_rect().get_center())
	await _wait(0.9)
	check(cs._step == 3 and _views(cs) == 1, "下一步 opens the briefcase again")
	check(cs._briefcase.selected == ["cashflow", "compliance_check"], "briefcase shows the kept tools (%s)" % str(cs._briefcase.selected))

	# 4. Several round trips stay clean
	for i in range(5):
		back = cs.find_child("BackToCluesButton", true, false)
		await _click(back.get_global_rect().get_center())
		await _wait(0.4)
		await _click(_next(cs).get_global_rect().get_center())
		await _wait(0.8)
	check(cs._step == 3 and _views(cs) == 1 and cs._page.get_child_count() == 1, "5 round trips: one page, one briefcase")

	# 5. Back right after 下一步 (before the briefcase's late build): the clues page stays
	back = cs.find_child("BackToCluesButton", true, false)
	await _click(back.get_global_rect().get_center())
	await _wait(0.4)
	await _click(_next(cs).get_global_rect().get_center())
	await _wait(0.2)
	await _click(back.get_global_rect().get_center())
	await _wait(1.0)
	check(cs._step == 2 and _views(cs) == 0 and _next(cs) != null, "quick back wins over the late briefcase build (step %d, %d views)" % [cs._step, _views(cs)])
	await _click(_next(cs).get_global_rect().get_center())
	await _wait(0.9)
	check(cs._step == 3 and _views(cs) == 1, "下一步 still works after the quick back")

	main.queue_free()
	await _wait(0.1)
	if had:
		var f := FileAccess.open(prefs, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	elif FileAccess.file_exists(prefs):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs))
	print("next_button_smoke: ", "OK" if failures == 0 else "%d failure(s)" % failures)
	quit(1 if failures else 0)
