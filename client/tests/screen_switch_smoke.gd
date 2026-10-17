extends SceneTree
## Run: godot --headless --path client --script res://tests/screen_switch_smoke.gd
## Screen switching: the app starts on the loading veil, the multiplayer lobby never shows during a
## solo start or after leaving, and only one screen exists at a time.

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("_run")


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _screens(main: Node) -> Array:
	var out: Array = []
	for c in main.get_children():
		if c is Control and c.get_script() != null:
			var p := str(c.get_script().resource_path)
			if p.ends_with("startup.gd") or p.ends_with("menu.gd") or p.ends_with("lobby.gd") or p.ends_with("game.gd") or p.ends_with("secretary_setup.gd") or p.ends_with("records.gd") or p.ends_with("report.gd"):
				if not c.is_queued_for_deletion():
					out.append(p.get_file())
	return out


func _run() -> void:
	var net: Node = root.get_node("Net")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# 1. Launch: the veil is up before any screen, then lifts once the cover has drawn
	check(main._veil != null and main._veil.visible, "starts on the loading veil")
	await _wait(1.0)
	check(main.get_screen_kind() == "startup", "cover is the first screen (%s)" % main.get_screen_kind())
	check(not main._veil.visible, "veil lifted after the cover drew")
	check(_screens(main) == ["startup.gd"], "one screen only at launch (%s)" % str(_screens(main)))

	# 2. Solo start: the room lobby phase stays behind the veil
	main.show_menu()
	await _wait(0.6)
	main._expect_room = true
	main._hold_veil()
	net.set("is_solo", true)
	net.set("room_code", "LOCAL")
	main._on_state({"phase": "lobby", "players": []})
	await _wait(0.4)
	check(main.get_screen_kind() != "lobby", "solo start never shows the lobby (%s)" % main.get_screen_kind())
	check(main._veil.visible, "loading veil held during the solo lobby phase")
	check(not _screens(main).has("lobby.gd"), "no lobby node during solo start")

	# 3. After leaving, late lobby states are ignored
	main._expect_room = false
	net.set("is_solo", false)
	net.set("room_code", "")
	main.show_startup()
	await _wait(0.8)
	main._on_state({"phase": "lobby", "players": []})
	await _wait(0.3)
	check(main.get_screen_kind() == "startup", "late lobby state after leaving is ignored")
	check(not main._veil.visible, "back on the cover without the veil")

	# 4. Multiplayer join still shows the lobby (hidden until switched in, under the veil)
	main._expect_room = true
	net.set("room_code", "ABCDE")
	main._on_state({"phase": "lobby", "code": "ABCDE", "players": [], "hostId": ""})
	check(main.get_screen_kind() == "lobby", "multiplayer lobby shown when joining a room")
	check(main._veil.visible, "lobby is switched in under the veil")
	await _wait(0.8)
	check(not main._veil.visible, "veil lifts after the lobby drew")
	check(_screens(main) == ["lobby.gd"], "old screen freed, one screen only (%s)" % str(_screens(main)))
	main._expect_room = false
	net.set("room_code", "")

	print("screen_switch_smoke: ", "OK" if failures == 0 else "%d failure(s)" % failures)
	quit(1 if failures else 0)
