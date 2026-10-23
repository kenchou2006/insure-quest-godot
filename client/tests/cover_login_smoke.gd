extends SceneTree
## Run: godot --headless --path client --script res://tests/cover_login_smoke.gd

var failures := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame

	if not root.has_node("Net"):
		printerr("FAIL: Net autoload not found on root")
		quit(1)
		return

	var net: Node = root.get_node("Net")
	if net == null:
		printerr("FAIL: Net node is null")
		quit(1)
		return

	var orig_profile = net.get("user_profile")
	var orig_config = net.get("auth_config")

	var StartupScript = load("res://scripts/ui/startup.gd")
	if StartupScript == null:
		printerr("FAIL: startup.gd could not be loaded")
		quit(1)
		return

	var cover: Control = StartupScript.new() as Control
	if cover == null:
		printerr("FAIL: failed to instantiate startup.gd")
		quit(1)
		return

	cover.size = Vector2(1280, 720)
	root.add_child(cover)

	for _i in range(3):
		await process_frame

	net.set("user_profile", {})
	net.set("auth_config", {"google": true, "dev": true, "demo": true})

	if cover.has_method("_refresh_account"):
		cover.call("_refresh_account")
	elif net.has_signal("auth_changed"):
		net.emit_signal("auth_changed")

	for _i in range(3):
		await process_frame

	var buttons: Array[Node] = cover.find_children("*", "Button", true, false)
	var button_texts: Array[String] = []
	for b in buttons:
		if b is Button:
			button_texts.append((b as Button).text)

	check(button_texts.has("使用 Google 登入"), "Button with text '使用 Google 登入' exists")
	check(button_texts.has("測試登入"), "Button with text '測試登入' exists")
	check(button_texts.has("評審體驗碼"), "Button with text '評審體驗碼' exists")

	var account_area: Control = cover.get("_account_area") as Control
	if account_area == null:
		account_area = cover.find_child("AccountArea", true, false) as Control

	check(account_area != null, "account area exists under cover")
	if account_area != null:
		var area_rect: Rect2 = account_area.get_global_rect()
		var cover_rect: Rect2 = cover.get_global_rect()
		check(cover_rect.encloses(area_rect), "account area rect (%s) lies inside cover (%s)" % [area_rect, cover_rect])

		var enter_btn: Control = cover.get("_enter") as Control
		if enter_btn == null:
			enter_btn = cover.find_child("_enter", true, false) as Control
		check(enter_btn != null, "_enter button exists on cover")
		if enter_btn != null:
			var enter_rect: Rect2 = enter_btn.get_global_rect()
			check(area_rect.position.y >= enter_rect.end.y, "account area y (%f) lies below _enter end y (%f)" % [area_rect.position.y, enter_rect.end.y])

	cover.queue_free()
	net.set("user_profile", orig_profile)
	net.set("auth_config", orig_config)

	print("cover_login_smoke: ", "OK" if failures == 0 else "%d failure(s)" % failures)
	quit(1 if failures else 0)
