extends SceneTree
## Run: godot --headless --path client --script res://tests/auth_login_smoke.gd

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

	var orig_base_url: String = str(net.get("base_url"))
	var orig_player_name: String = str(net.get("player_name"))

	net.set("base_url", "http://localhost:8787")
	net.set("player_name", "")

	# dev_login_url with an explicit name
	var explicit_name := "王 小明"
	var explicit_url: String = str(net.call("dev_login_url", explicit_name))
	check(explicit_url.contains(explicit_name.uri_encode()), "dev_login_url('王 小明') contains encoded name")
	check(explicit_url.contains("/api/auth/dev-login?name="), "dev_login_url('王 小明') contains dev-login path")
	check(explicit_url.contains("&return=/"), "dev_login_url('王 小明') contains &return=/")

	# Fallback checks (PlayerProfile is an autoload in the running tree)
	var empty_url: String = str(net.call("dev_login_url", ""))
	check(empty_url.contains("/api/auth/dev-login?name="), "dev_login_url('') contains '/api/auth/dev-login?name='")
	check(empty_url.contains("&return=/"), "dev_login_url('') contains '&return=/'")
	var dev_name: String = str(net.call("dev_login_name"))
	check(empty_url == str(net.call("dev_login_url", dev_name)), "dev_login_url('') equals dev_login_url(dev_login_name())")
	check(dev_name != "", "dev_login_name() is never empty")

	net.set("base_url", orig_base_url)
	net.set("player_name", orig_player_name)

	print("auth_login_smoke: ", "OK" if failures == 0 else "%d failure(s)" % failures)
	quit(1 if failures else 0)
