extends SceneTree
## Run: godot --headless --path client --script res://tests/hall_smoke.gd
## Training hall: the chosen secretary only (female / male / none), mode cards, solo options,
## multiplayer login gate, and the corner dialog never covering the cards or options.

# Loaded at run time: these scripts use autoloads (Net, MusicManager), which exist only once the tree runs
var MenuScript: GDScript
var GuideScript: GDScript
const FEMALE := preload("res://assets/startup/advisor_f.png")
const MALE := preload("res://assets/startup/advisor_m.png")
var failures := 0


class MainStub extends Node:
	var guide: Control
	var calls: Array = []
	func secretary_guide() -> Control:
		return guide
	func toast(t: String, _c: Color = Color.WHITE, _s := 3.0) -> void:
		calls.append(["toast", t])
	func create_and_join(bots: Array, solo: bool) -> void:
		calls.append(["create", bots, solo])
	func join_room(code: String) -> void:
		calls.append(["join", code])
	func show_records(_u := "") -> void:
		calls.append(["records"])
	func resume_seat() -> void:
		calls.append(["resume"])
	func open_secretary_settings() -> void:
		calls.append(["secretary"])


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _hall(sel: String, view := Vector2(1280, 720)) -> Array:
	var stub := MainStub.new()
	root.add_child(stub)
	var guide: Control = GuideScript.new()
	stub.add_child(guide)
	stub.guide = guide
	guide.enabled = sel != "none"
	guide.role = sel if sel != "none" else "female"
	guide.secretary_id = {"female": "aly", "male": "kevin"}.get(sel, "none")
	guide._seen_states = []
	var m: Control = MenuScript.new()
	m.main = stub
	m.size = view
	root.add_child(m)
	m.size = view
	await _wait(0.6)
	return [m, stub]


func _portraits(n: Node) -> Array:
	var found: Array = []
	for c in n.find_children("*", "TextureRect", true, false):
		var t: Texture2D = (c as TextureRect).texture
		# Secretary portraits only (the top-bar logo is a cropped texture too)
		if c.is_visible_in_tree() and t is AtlasTexture and (t as AtlasTexture).atlas in [FEMALE, MALE]:
			found.append((t as AtlasTexture).atlas)
	return found


func _run() -> void:
	MenuScript = load("res://scripts/ui/menu.gd")
	GuideScript = load("res://scripts/ui/training_secretary.gd")
	# The secretary saves its state: keep the player's own file untouched
	var prefs: String = GuideScript.PREFS
	var had := FileAccess.file_exists(prefs)
	var backup := FileAccess.get_file_as_string(prefs) if had else ""
	# Female secretary: Aly from the cover's left portrait; the greeting is a 強制聚焦導覽
	var r := await _hall("female")
	var m: Control = r[0]
	var sec = m._secretary
	var g: Control = (r[1] as MainStub).guide
	check(sec.selected_secretary == "female" and sec.secretary_id == "aly", "female → aly")
	check(g.is_open() and g._overlay.visible, "female: hall greeting opens as the modal tutorial")
	check(g._heading.text.begins_with("女性培訓秘書"), "female heading (%s)" % g._heading.text)
	check(g._overlay.holes().size() == 2, "both mode cards kept bright")
	var ps := _portraits(m)
	check(ps.has(FEMALE) and not ps.has(MALE), "only the female cover portrait is shown")
	check(g._subtitle.text == g.SecretaryLines.lines("hall_intro")[0], "first greeting line shown")
	g._close_modal(true)
	check(not g.is_open() and not g._overlay.visible, "greeting closes and unlocks")
	for card in [m._solo_card, m._multi_card]:
		check(not sec.occupied_rect().intersects(card.get_rect()), "dialog clear of %s" % card.title)
	# Solo options appear only after picking 單人實戰
	check(not m._solo_opts.visible, "solo options hidden at first")
	m._pick_mode("solo")
	await _wait(0.3)
	check(m._solo_opts.visible, "solo options shown after picking solo")
	check(not sec.occupied_rect().intersects(m._solo_opts.get_rect()), "dialog clear of solo options")
	m._pick_mode("multi")
	check(not m._solo_opts.visible, "solo options hidden for multi")
	# Corner portrait replays the greeting tutorial
	check(not sec.is_open and sec._avatar.visible, "hall keeps the round portrait in the corner")
	sec._avatar.pressed.emit()
	await _wait(0.3)
	check(g.is_open() and g._modal, "round portrait replays the greeting")
	g._close_modal(true)
	# 進入單人實戰 starts solo with the existing defaults (2 senior AI advisors)
	var stub: MainStub = r[1]
	m._solo_card.activated.emit()
	check(stub.calls.has(["create", ["pro", "pro"], true]), "solo starts create_and_join (%s)" % str(stub.calls))
	# 建立多人房間 as a guest opens the identity panel instead of failing
	stub.calls.clear()
	m._on_multi_pressed()
	check(m._id_pop.visible, "guest multiplayer opens the identity panel")
	check(stub.calls.size() == 1 and stub.calls[0][0] == "toast", "guest multiplayer shows a login toast, no room")
	m._toggle_identity(false)
	m.queue_free()
	r[1].queue_free()
	await _wait(0.1)

	# Male secretary: Kevin from the cover's right portrait
	r = await _hall("male")
	m = r[0]
	sec = m._secretary
	g = (r[1] as MainStub).guide
	check(sec.secretary_id == "kevin", "male → kevin")
	check(g._heading.text.begins_with("男性培訓秘書"), "male heading (%s)" % g._heading.text)
	g._close_modal(true)
	ps = _portraits(m)
	check(ps.has(MALE) and not ps.has(FEMALE), "only the male cover portrait is shown")
	m.queue_free()
	r[1].queue_free()
	await _wait(0.1)

	# 自行挑戰: no portrait, no dialog until 開啟引導
	r = await _hall("none")
	m = r[0]
	sec = m._secretary
	g = (r[1] as MainStub).guide
	check(not sec.is_open and not g.is_open(), "solo challenge: no automatic dialog or tutorial")
	check(sec._pill.visible and not sec._avatar.visible, "solo challenge: 開啟引導 pill only")
	check(_portraits(m).is_empty(), "solo challenge: no secretary portrait")
	sec.open_dialog(false)
	await _wait(0.5)
	check(sec.is_open and sec._heading.text == "培訓引導" and not sec._portrait.visible, "開啟引導 shows text-only guide")
	m.queue_free()
	r[1].queue_free()
	await _wait(0.1)

	# Phone portrait: stacked cards, dialog clear of the first card
	UI.set_layout_profile("phone_portrait", Vector2i(480, 854))
	r = await _hall("female", Vector2(480, 854))
	m = r[0]
	check(m._portrait_mode, "portrait layout")
	check(m._solo_card.size.x > 400, "solo card spans the phone width")
	m.queue_free()
	r[1].queue_free()
	UI.set_layout_profile("desktop", Vector2i(1280, 720))
	await _wait(0.1)
	if had:
		var f := FileAccess.open(prefs, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	elif FileAccess.file_exists(prefs):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs))

	print("hall_smoke: ", "OK" if failures == 0 else "%d failure(s)" % failures)
	quit(1 if failures else 0)
