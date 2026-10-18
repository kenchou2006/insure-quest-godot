extends SceneTree
## Run: godot --headless --path client --script res://tests/secretary_flow_smoke.gd
## One shared secretary layer for every choice, with real clicks and animations on:
## 女秘書 / 男秘書 / 不使用秘書 → 單人培訓 → 看線索 (the right secretary, or none and no dim) →
## 下一步：選工具 (a real Button: loading, saves customer / found clues / secretary) → 公事包.
## Also: a failed switch shows its reason and gives the button back, and the top-right items are
## real buttons that do something.

const FEMALE := preload("res://assets/startup/advisor_f.png")
const MALE := preload("res://assets/startup/advisor_m.png")
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
	var toasts: Array = []
	func secretary_guide() -> Control:
		return guide
	func toast(t: String, _c: Color = Color.WHITE, _s := 3.0) -> void:
		toasts.append(t)


class GameStub extends Control:
	var main: Node = null


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


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


## The secretary's portrait shown right now (tutorial dialog or corner card), or null
func _portrait_atlas(g: Control) -> Texture2D:
	var t: Texture2D = null
	if g._overlay and g._overlay.visible:
		t = g._overlay._portrait.texture
	elif g._card.visible:
		t = g._portrait.texture
	return (t as AtlasTexture).atlas if t is AtlasTexture else null


func _flow(sel: String) -> void:
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
	# Choosing on the selection screen, then the training screen opens
	g.choose(sel != "none", sel if sel != "none" else "female")
	g._seen_states = []
	g.screen_changed("game")
	var cs: Control = load("res://scripts/ui/case_setup.gd").new()
	cs.z_index = 110
	game.add_child(cs)
	await _wait(0.8)
	check(cs.selected_secretary == sel, "%s: case setup sees selected_secretary (%s)" % [sel, cs.selected_secretary])
	# Through the entry tutorial (secretary only)
	for i in range(4):
		if g._open and g._modal:
			g._line_done()
			await _click(_center(g._overlay._continue))
	await _click(_center(cs._accept))
	await _wait(2.2)
	check(cs._step == 2, "%s: 看線索 page (step %d)" % [sel, cs._step])

	# 看線索: the right secretary, or nothing at all
	match sel:
		"female":
			check(g.secretary_id == "aly" and g.is_open(), "female: Aly speaks on the clues page")
			check(_portrait_atlas(g) == FEMALE, "female: Aly's portrait")
			check(g._overlay._heading.text.begins_with("女性培訓秘書 · Aly"), "female: Aly's dialog (%s)" % g._overlay._heading.text)
		"male":
			check(g.secretary_id == "kevin" and g.is_open(), "male: Kevin speaks on the clues page")
			check(_portrait_atlas(g) == MALE, "male: Kevin's portrait")
			check(g._overlay._heading.text.begins_with("男性培訓秘書 · Kevin"), "male: Kevin's dialog (%s)" % g._overlay._heading.text)
		"none":
			check(g._overlay == null, "none: no dim layer exists")
			check(not g.is_open() and not g._card.visible and not g._icon.visible, "none: no secretary, dialog or portrait")
			check(g._voice == "", "none: no voice")
	if g._open and g._modal:
		await _click(_center(g._overlay._skip))
		check(not g._overlay.visible and g._overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s: 跳過 removes the dim" % sel)

	# 下一步：選工具 is a real Button with a loading state
	var next: Button = cs._page.find_child("NextToolsButton", true, false)
	check(next != null and next is Button, "%s: 下一步 is a Godot Button" % sel)
	await _click(_center(next))
	check(cs._step == 3 or (next.get("_loading") == true), "%s: 下一步 reacts at once (loading or switched)" % sel)
	await _wait(0.9)
	var view: Control = cs.find_child("BriefcaseView", true, false)
	check(cs._step == 3 and view != null and view.is_visible_in_tree(), "%s: 公事包 opened" % sel)
	check(str(cs.current_customer.get("customer_name", "")) == "林雨晴", "%s: current_customer saved" % sel)
	check(cs.unlocked_clues.size() == 2 and str(cs.unlocked_clues[0].get("title", "")) == "收入不穩", "%s: unlocked_clues saved" % sel)
	check(cs.selected_secretary == sel, "%s: selected_secretary saved" % sel)
	if sel == "none":
		check(g._overlay == null and not g.is_open(), "none: briefcase without secretary or dim")
	else:
		check(g.is_open() and _portrait_atlas(g) == (FEMALE if sel == "female" else MALE), "%s: same secretary on the briefcase" % sel)
		g._close_modal(true)
	main.queue_free()
	await _wait(0.1)


func _run() -> void:
	var GuideScript: GDScript = load("res://scripts/ui/training_secretary.gd")
	var prefs: String = GuideScript.PREFS
	var had := FileAccess.file_exists(prefs)
	var backup := FileAccess.get_file_as_string(prefs) if had else ""
	var opts := [{"id": "yuqing", "name": "林雨晴", "age": 29, "job": "自由接案插畫家", "difficulty": "入門", "family": "單身", "incomeInfo": "月收入 3–8 萬不等", "amount": "NT$ 600,000", "goal": "工作室", "intro": "接案"}]
	root.get_node("Net").set("state", {"phase": "playing", "caseOptions": opts, "codex": [], "briefcaseSize": 3,
		"tools": [{"id": "needs_form"}, {"id": "cashflow"}, {"id": "compliance_check"}]})

	for sel: String in ["female", "male", "none"]:
		await _flow(sel)

	# A switch that cannot happen says why and gives the button back
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
	g.choose(false, "female")
	var cs: Control = load("res://scripts/ui/case_setup.gd").new()
	game.add_child(cs)
	await _wait(0.5)
	cs._go_step(2)
	await _wait(0.8)
	cs.client = {}
	var next: Button = cs._page.find_child("NextToolsButton", true, false)
	await _click(_center(next))
	var err: Label = cs._page.find_child("NextToolsError", true, false)
	check(cs._step == 2, "failed switch stays on the clues page")
	check(err != null and err.visible and err.text.contains("指定客戶"), "failed switch shows its reason")
	check(not main.toasts.is_empty(), "failed switch also shows a toast")
	check(next.get("_loading") == false and not next.disabled and next._label.text == "下一步：選工具", "button usable again after a failure")

	# Top-right: real buttons that do something
	for n: String in ["AdvisorButton", "SettingsButton", "RecordsButton", "SoundButton"]:
		var b: Node = cs.find_child(n, true, false)
		check(b is Button and (b as Button).is_visible_in_tree(), "%s is a visible Button" % n)
		check(b is Button and (b as Button).pressed.get_connections().size() > 0, "%s does something when pressed" % n)
	var mm: Node = root.get_node("MusicManager")
	var was_muted: bool = mm.muted
	(cs.find_child("SoundButton", true, false) as Button).pressed.emit()
	check(mm.muted != was_muted, "音效 toggles the sound")
	mm.set_muted(was_muted)
	(cs.find_child("AdvisorButton", true, false) as Button).pressed.emit()
	var texts := ""
	for l in cs.find_children("*", "Label", true, false):
		texts += (l as Label).text + "\n"
	check(texts.contains("顧問資料") and texts.contains("培訓秘書：自行挑戰"), "顧問 opens the advisor panel")
	main.queue_free()
	await _wait(0.1)

	if had:
		var f := FileAccess.open(prefs, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	elif FileAccess.file_exists(prefs):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs))
	print("secretary_flow_smoke: ", "OK" if failures == 0 else "%d failure(s)" % failures)
	quit(1 if failures else 0)
