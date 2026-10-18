extends SceneTree
## Run: godot --headless --path client --script res://tests/map_guide_smoke.gd
## Map page 培訓秘書 focus guide, with real mouse events on a stand-in map page (前往下一站, three
## tabs, zoom / reset, a map node): first visit plays once, the dim takes every click and hover
## while the guide is up, typewriter + first tap completes the line, 繼續 / 開始操作, 略過導覽,
## voice failure, Aly / Kevin, guide_seen["map"], replay from the entry, fast clicks and 10 enters
## never stack dims, screen changes clean up, and everything is clickable again afterwards.

const FEMALE := preload("res://assets/startup/advisor_f.png")
const MALE := preload("res://assets/startup/advisor_m.png")
var failures := 0
var pressed := {}


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


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
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = w
		e.global_position = w
		root.push_input(e)
		await process_frame


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


class MainStub extends Control:
	var guide: Control
	func secretary_guide() -> Control:
		return guide


## Stand-in map page: the controls the guide must pause and give back
func _map_page(holder: Control) -> Dictionary:
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(page)
	var out := {}
	var specs := [["roll", "前往下一站", Rect2(420, 330, 200, 56)], ["tab_task", "任務", Rect2(900, 40, 110, 44)],
		["tab_client", "客戶", Rect2(1015, 40, 110, 44)], ["tab_growth", "成長", Rect2(1130, 40, 110, 44)],
		["zoom_in", "+", Rect2(700, 30, 44, 44)], ["zoom_reset", "復位", Rect2(750, 30, 60, 44)],
		["node", "02 合規演練", Rect2(300, 450, 160, 40)], ["task_item", "辨識錯誤話術", Rect2(900, 300, 330, 44)]]
	for sp: Array in specs:
		var b := Button.new()
		b.text = sp[1]
		b.position = (sp[2] as Rect2).position
		b.size = (sp[2] as Rect2).size
		var id: String = sp[0]
		pressed[id] = 0
		b.pressed.connect(func(): pressed[id] += 1)
		page.add_child(b)
		out[id] = b
	return out


func _dims() -> int:
	return root.find_children("DimOverlay", "ColorRect", true, false).size()


func _run() -> void:
	var GuideScript: GDScript = load("res://scripts/ui/training_secretary.gd")
	var prefs: String = GuideScript.PREFS
	var had := FileAccess.file_exists(prefs)
	var backup := FileAccess.get_file_as_string(prefs) if had else ""

	var main := MainStub.new()
	main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(main)
	var page_holder := Control.new()
	page_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main.add_child(page_holder)
	var ui := _map_page(page_holder)
	var g: Control = GuideScript.new()
	main.add_child(g)
	main.guide = g
	await process_frame
	g.choose(true, "female")
	g.guide_seen = {}
	g.screen_changed("game")
	var f = g._focus
	var ctx := {"client_name": "林雨晴", "focus": ui.roll}

	# 1. First visit: plays once by itself
	g.map_page(true, ctx)
	check(g._map_pill.visible, "map shows the small 培訓秘書 entry")
	await _wait(1.0)
	check(f.guide_active and f.input_locked and f.secretary_is_speaking, "first visit opens the focus guide")
	check(f.dim.visible and f.dim.mouse_filter == Control.MOUSE_FILTER_STOP and f.layer > 0, "dim up on its own layer and takes the mouse")
	check(f.dim.color.is_equal_approx(Color("#021C19", 0.68)), "dim colour #021C19 at 68%")
	check(not g._map_pill.visible, "entry hidden while the guide is up")
	check(f.name_label.text.begins_with("女性培訓秘書 · Aly") and (f.portrait.texture as AtlasTexture).atlas == FEMALE, "Aly's portrait and name")
	check(f.dialogues.size() == 3 and str(f.dialogues[2]).contains("林雨晴"), "client line reads the current client (%s)" % str(f.dialogues))
	check(f.page_label.text == "1／3", "page indicator 1／3 (%s)" % f.page_label.text)

	# 2. Everything behind is paused: no hover, no clicks
	for id in ["roll", "tab_task", "zoom_in", "node", "task_item"]:
		await _move(_center(ui[id]))
		check(root.gui_get_hovered_control() == f.dim, "%s: hover goes to the dim (%s)" % [id, str(root.gui_get_hovered_control())])
		await _click(_center(ui[id]))
		check(pressed[id] == 0, "%s cannot be pressed during the guide" % id)

	# 3. Typewriter: the first tap completes the sentence, never skips it
	f.show_dialogue(0)
	await _wait(0.15)
	check(f.text.visible_ratio < 1.0 and not f.continue_button.visible, "line types out, 繼續 hidden meanwhile")
	await _click(_center(f.panel))
	check(f.text.visible_ratio == 1.0 and f.current_dialogue_index == 0, "first tap shows the whole line, same page")
	check(f.continue_button.visible and f.continue_button.text == "繼續", "繼續 after text (and voice) finish")
	await _click(_center(f.continue_button))
	check(f.current_dialogue_index == 1 and f.text.text == "金色標記是你目前的位置。查看右側任務後，按下『前往下一站』開始合規演練。", "page 2, verbatim line")
	await _wait(2.6)
	check(f.continue_button.visible, "page 2 finishes typing by itself")
	await _click(_center(f.continue_button))
	await _wait(2.6)
	check(f.current_dialogue_index == 2 and f.continue_button.text == "開始操作", "last page offers 開始操作")
	await _click(_center(f.continue_button))

	# 4. Finished: everything back, saved, focus on 前往下一站
	check(not f.guide_active and not f.input_locked and not f.secretary_is_speaking, "flags cleared")
	check(not f.dim.visible and f.dim.mouse_filter == Control.MOUSE_FILTER_IGNORE and not f.visible, "dim hidden and ignoring the mouse")
	check(not f.portrait.visible and not f.panel.visible and not f.skip_button.visible, "portrait, dialogue and buttons hidden")
	check(g._map_pill.visible, "entry back")
	check(bool(g.guide_seen.get("map", false)), "guide_seen[\"map\"] = true")
	var cfg := ConfigFile.new()
	cfg.load(prefs)
	check(bool((cfg.get_value("guide", "guide_seen", {}) as Dictionary).get("map", false)), "guide_seen saved to %s" % prefs)
	check(root.gui_get_focus_owner() == ui.roll, "focus back on 前往下一站")
	for id in ["roll", "tab_task", "tab_client", "tab_growth", "zoom_in", "zoom_reset", "node", "task_item"]:
		await _move(_center(ui[id]))
		check(root.gui_get_hovered_control() == ui[id], "%s hover works after the guide" % id)
		await _click(_center(ui[id]))
		check(pressed[id] == 1, "%s clickable after the guide (%d)" % [id, pressed[id]])

	# 5. Seen: entering the map again does not force it
	g.map_page(false, ctx)
	g.map_page(true, ctx)
	await _wait(1.2)
	check(not f.guide_active, "seen guide is not played again by itself")

	# 6. Entry replays it; fast clicks open one guide only; 略過導覽 cleans up
	for i in range(4):
		await _click(_center(g._map_pill)) if g._map_pill.visible else await _wait(0.02)
	await _wait(0.3)
	check(f.guide_active and _dims() == 1, "entry replays the guide; fast clicks → one dim (%d)" % _dims())
	var skip_rect: Rect2 = f.skip_button.get_global_rect()
	check(not skip_rect.intersects(f.panel.get_global_rect()) and not skip_rect.intersects(f.portrait.get_global_rect()), "略過導覽 clear of portrait and dialogue")
	await _click(_center(f.skip_button))
	check(not f.guide_active and not f.dim.visible and f.dim.mouse_filter == Control.MOUSE_FILTER_IGNORE, "略過導覽 cleans up")
	await _click(_center(ui.roll))
	check(pressed.roll == 2, "前往下一站 works after skipping")

	# 7. Voice: a line whose end never comes, and a voice that cannot play
	g.open_map_guide()
	f.voice_fallback_per_char = 0.01
	f.speak_line = func(_t): return true
	f.show_dialogue(0)
	f.complete_typewriter()
	check(not f.continue_button.visible and f.voice_indicator.text == "● 語音播放中", "繼續 waits for the voice")
	await _wait(1.9)
	check(f.continue_button.visible, "voice that never reports its end still lets the player go on")
	f.speak_line = func(_t): return false
	f.show_dialogue(1)
	f.complete_typewriter()
	check(f.continue_button.visible and f.voice_indicator.text.begins_with("靜音"), "failed voice: silent state, text and 繼續 still work")
	await _click(_center(f.voice_button))
	check(not f.voice_enabled and f.voice_button.text == "語音：關" and not g.voice_on, "voice toggle off (saved)")
	await _click(_center(f.voice_button))
	check(f.voice_enabled and g.voice_on, "voice toggle on")
	f.speak_line = g._speak_focus_line
	f.voice_fallback_per_char = 0.32
	f.end_secretary_focus("test")

	# 8. Kevin: male portrait and name; the choice is not reset by the map
	g.choose(true, "male")
	g.screen_changed("game")
	g.map_page(true, ctx)
	g.open_map_guide()
	check(g.secretary_id == "kevin" and f.name_label.text.begins_with("男性培訓秘書 · Kevin") and (f.portrait.texture as AtlasTexture).atlas == MALE, "Kevin's portrait and name")
	g.map_page(true, ctx)
	check(g.secretary_id == "kevin" and g.role == "male", "map does not reset the secretary")

	# 9. Screen change and leaving the map end the guide
	g.screen_changed("menu")
	check(not f.guide_active and not f.dim.visible and not g._map_pill.visible, "screen change ends the guide")
	g.screen_changed("game")
	g.map_page(true, ctx)
	g.open_map_guide()
	g.map_page(false, ctx)
	check(not f.guide_active and not f.dim.visible, "leaving the map ends the guide")

	# 10. In and out of the map 10 times with the guide: nothing piles up
	for i in range(10):
		g.map_page(true, ctx)
		g.open_map_guide()
		await process_frame
		g.map_page(false, ctx)
		await process_frame
	g.map_page(true, ctx)
	check(_dims() == 1 and root.find_children("SecretaryGuide", "CanvasLayer", true, false).size() == 1, "10 visits: one guide layer, one dim")
	check(not f.dim.visible and f.dim.mouse_filter == Control.MOUSE_FILTER_IGNORE, "no dim left after 10 visits")
	await _click(_center(ui.roll))
	check(pressed.roll == 3, "前往下一站 still works after 10 visits")

	# 11. A dim left visible without a guide is released on the next frame
	f.visible = true
	f.dim.visible = true
	f.dim.mouse_filter = Control.MOUSE_FILTER_STOP
	await process_frame
	await process_frame
	check(not f.dim.visible and f.dim.mouse_filter == Control.MOUSE_FILTER_IGNORE, "stray dim released by the watchdog")

	# 12. No secretary: no entry, no guide
	g.choose(false, "female")
	g.screen_changed("game")
	g.map_page(true, ctx)
	g.open_map_guide()
	check(not g._map_pill.visible and not f.guide_active, "自行挑戰: no entry and no guide")

	# 13. Layout at several screen sizes (content units: 1920×1080 / 1366×768 windows scale to 1280×720)
	g.choose(true, "female")
	g.screen_changed("game")
	g.map_page(true, ctx)
	g.open_map_guide()
	f.complete_typewriter()
	await _wait(0.4)
	for real: Vector2 in [Vector2(1280, 720), Vector2(1366, 768), Vector2(1920, 1080), Vector2(800, 450), Vector2(1280, 600)]:
		f._layout_for(real)
		await process_frame
		await process_frame
		var pr: Rect2 = f.portrait.get_rect()
		var dr: Rect2 = f.panel.get_rect()
		var sr: Rect2 = f.skip_button.get_rect()
		var vr: Rect2 = f.voice_button.get_rect()
		var cr: Rect2 = f.continue_button.get_global_rect()
		var view := Rect2(Vector2.ZERO, real)
		var ratio := pr.size.y / real.y
		check(view.encloses(pr) and ratio >= 0.28 and ratio <= 0.38, "%s: portrait inside, %.0f%% of height" % [str(real), ratio * 100.0])
		check(view.encloses(dr) and view.encloses(cr), "%s: dialogue and 繼續 inside (%s)" % [str(real), str(dr)])
		check(not dr.intersects(sr) and not pr.intersects(sr) and not dr.intersects(vr), "%s: 略過導覽 / 語音 not covered" % str(real))
		check(dr.end.x <= pr.position.x + 1.0 or dr.end.y <= pr.position.y + pr.size.y * 0.45, "%s: dialogue clear of the face" % str(real))
		check(dr.size.x >= minf(460.0, real.x - 32.0) - 1.0 and dr.size.x <= 621.0, "%s: dialogue %.0f px wide" % [str(real), dr.size.x])
		check(f.text.get_line_count() <= 2, "%s: two lines at most (%d)" % [str(real), f.text.get_line_count()])
	f.end_secretary_focus("test")

	main.queue_free()
	await _wait(0.1)
	if had:
		var fw := FileAccess.open(prefs, FileAccess.WRITE)
		fw.store_string(backup)
		fw.close()
	elif FileAccess.file_exists(prefs):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs))
	print("map_guide_smoke: ", "OK" if failures == 0 else "%d failure(s)" % failures)
	quit(1 if failures else 0)
