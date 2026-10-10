@tool
extends Node
## Network layer (Autoload "Net"): HTTP room creation / record queries + WebSocket room connection and auto-reconnect.
## Web version connects to same origin by default (Worker serves both web and API); desktop version connects to local wrangler dev by default.

signal welcomed(data: Dictionary)
signal state_changed(state: Dictionary)
signal server_error(message: String)
signal reaction(from_name: String, emoji: String)
signal connection_changed(online: bool)
signal quota_changed(used: int, limit: int, exhausted: bool)
signal auth_changed()
## Streaming fragment of client response during interview (currently accumulated text)
signal stream_text(text: String)
## Stream client answer finished (coach tip may still be generating)
signal stream_answer_done()
## The room no longer exists (host left, abandoned, or voided); the client should go back to the menu.
signal room_closed(message: String)

const DEFAULT_DESKTOP_URL := "http://localhost:8787"

var base_url := DEFAULT_DESKTOP_URL
var room_code := ""
var player_id := ""
var player_name := "顧問"
var spectator := false
var is_solo := false
var ai_enabled := false
var static_data: Dictionary = {}
## Previous seat {room, playerId}: allows returning to the original seat after page refresh (multiplayer rooms only)
var saved_seat: Dictionary = {}
var state: Dictionary = {}
var auth_config: Dictionary = {}
var user_profile: Dictionary = {}
var ai_quota: Dictionary = {"used": 0, "limit": 0}
var welcome_me: Variant = null
## Google avatar (downloaded once after login; Google image domain allows cross-origin, web version can fetch directly)
var avatar_tex: Texture2D = null
var _avatar_url := ""
var _avatar_tried := false
var _avatar_in_flight := false
signal avatar_loaded(tex: Texture2D)

var _ws: WebSocketPeer = null
var _was_open := false
var _want_connected := false
var _retry_at := 0.0
var _ping_at := 0.0
var _hello_sent := false
var _local := false
var _local_connected_emitted := false


func _ready() -> void:
	# Editor preview (@tool) only requires a state container, without reading settings or connecting
	if Engine.is_editor_hint():
		return
	if OS.has_feature("web"):
		var origin = JavaScriptBridge.eval("window.location.origin", true)
		if typeof(origin) == TYPE_STRING and String(origin).begins_with("http"):
			base_url = String(origin)
	var saved := _load_prefs()
	player_name = saved.get("name", player_name)
	var seat = saved.get("seat", {})
	saved_seat = seat if seat is Dictionary else {}
	if not OS.has_feature("web"):
		base_url = saved.get("server", base_url)


func is_web() -> bool:
	return OS.has_feature("web")


func local_available() -> bool:
	if Engine.is_editor_hint() or not OS.has_feature("web"):
		return false
	var res = JavaScriptBridge.eval("!!window.iqLocal", true)
	return bool(res)


func is_local() -> bool:
	return _local


func save_prefs() -> void:
	var f := FileAccess.open("user://prefs.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"name": player_name, "server": base_url, "seat": saved_seat}))


func _load_prefs() -> Dictionary:
	if not FileAccess.file_exists("user://prefs.json"):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("user://prefs.json"))
	return parsed if parsed is Dictionary else {}


# ───────── HTTP ─────────

## Returns [ok: bool, data: Variant]
func http_json(method: int, path: String, body: Variant = null) -> Array:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	# Web version is automatically decompressed by the browser; decompressing again in Godot will fail
	req.accept_gzip = false
	add_child(req)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var payload := "" if body == null else JSON.stringify(body)
	var err := req.request(base_url + path, headers, method, payload)
	if err != OK:
		req.queue_free()
		return [false, "無法連線到伺服器（%s）" % base_url]
	var res: Array = await req.request_completed
	req.queue_free()
	var code: int = res[1]
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var data = JSON.parse_string(text) if text != "" else null
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return [false, "無法連線到伺服器（%s）" % base_url]
	if code >= 400:
		var msg := "伺服器錯誤 %d" % code
		if data is Dictionary and data.has("error"):
			msg = str(data["error"])
		return [false, msg]
	return [true, data]


func create_room(solo := false) -> Array:
	var r := await http_json(HTTPClient.METHOD_POST, "/api/rooms", {"solo": solo})
	if r[0]:
		return [true, str(r[1].get("code", ""))]
	return r


func fetch_records(name_filter: String) -> Array:
	return await fetch_records_scope("", name_filter)


func fetch_records_scope(scope: String = "", name_filter: String = "") -> Array:
	var q := "/api/records?limit=100"
	# scope is "all" = all learners (trainer); other non-empty values are treated as learner id (trainer viewing single learner)
	if scope.strip_edges() == "all":
		q += "&scope=all"
	elif scope.strip_edges() != "":
		q += "&user=" + scope.strip_edges().uri_encode()
	if name_filter.strip_edges() != "":
		q += "&name=" + name_filter.strip_edges().uri_encode()
	return await http_json(HTTPClient.METHOD_GET, q)


func fetch_auth_config() -> Array:
	var r: Array = await http_json(HTTPClient.METHOD_GET, "/api/auth/config")
	if bool(r[0]) and r[1] is Dictionary:
		auth_config = r[1]
	return r


func submit_demo_code(code: String) -> Array:
	var r: Array = await http_json(HTTPClient.METHOD_POST, "/api/auth/demo", {"code": code.strip_edges()})
	if bool(r[0]):
		await fetch_me()
		if is_logged_in():
			var u: Dictionary = get_user()
			var un: String = str(u.get("name", "")).strip_edges()
			if un != "":
				player_name = un
				save_prefs()
	return r


func check_and_consume_url_demo_code() -> String:
	if not OS.has_feature("web") or Engine.is_editor_hint():
		return ""
	var code_val = JavaScriptBridge.eval("""(function() {
		try {
			var params = new URLSearchParams(window.location.search);
			var c = params.get('code');
			if (c) {
				params.delete('code');
				var qs = params.toString() ? ('?' + params.toString()) : '';
				window.history.replaceState({}, '', window.location.pathname + qs + window.location.hash);
				return c;
			}
		} catch (e) {}
		return '';
	})()""", true)
	return str(code_val).strip_edges() if typeof(code_val) == TYPE_STRING else ""


func fetch_insights() -> Array:
	return await http_json(HTTPClient.METHOD_GET, "/api/insights")


func fetch_me() -> Array:
	var r: Array = await http_json(HTTPClient.METHOD_GET, "/api/me")
	if bool(r[0]) and r[1] is Dictionary:
		user_profile = r[1]
		if user_profile.get("ai") is Dictionary:
			var ai_dict: Dictionary = user_profile["ai"]
			ai_quota = {"used": int(ai_dict.get("used", 0)), "limit": int(ai_dict.get("limit", 50))}
		else:
			ai_quota = {"used": 0, "limit": 0}
		var pic: String = str(get_user().get("picture", "")) if is_logged_in() else ""
		if pic != _avatar_url:
			_avatar_url = pic
			avatar_tex = null
			_avatar_tried = false
		auth_changed.emit()
	return r


## Advisor level {level, title, xp, floor, next, games}; empty if not logged in
func get_level() -> Dictionary:
	return user_profile.get("level", {}) if user_profile.get("level") is Dictionary else {}


## Google avatar local cache (7-day TTL to prevent frequent requests from triggering 429)
const AVATAR_CACHE_TTL := 7 * 86400
const AVATAR_IMG_PATH := "user://avatar_cache.png"
const AVATAR_META_PATH := "user://avatar_meta.json"


## Download Google avatar (local persistent cache with TTL; returns null on failure or if no avatar)
func fetch_avatar() -> Texture2D:
	if avatar_tex != null:
		return avatar_tex
	if _avatar_in_flight:
		await avatar_loaded
		return avatar_tex
	if _avatar_tried or _avatar_url == "" or not _avatar_url.begins_with("https://"):
		return avatar_tex
	_avatar_in_flight = true
	_avatar_tried = true

	var now := int(Time.get_unix_time_from_system())
	var meta: Dictionary = _load_avatar_meta()
	var cached_url: String = str(meta.get("url", ""))
	var cached_time: int = int(meta.get("timestamp", 0))
	var has_cached_file: bool = FileAccess.file_exists(AVATAR_IMG_PATH)

	# 1. Image exists locally, URL identical, and not expired (< 7 days) -> read directly from local cache, no network request sent
	if has_cached_file and cached_url == _avatar_url and (now - cached_time) < AVATAR_CACHE_TTL:
		var img := Image.load_from_file(AVATAR_IMG_PATH)
		if img != null and not img.is_empty():
			avatar_tex = ImageTexture.create_from_image(img)
			_avatar_in_flight = false
			avatar_loaded.emit(avatar_tex)
			return avatar_tex

	# 2. Expired, URL changed, or first visit -> download from Google
	var url := _avatar_url
	var req := HTTPRequest.new()
	req.timeout = 10.0
	req.accept_gzip = false
	add_child(req)
	if req.request(url) != OK:
		req.queue_free()
		var res_fb: Texture2D = _fallback_to_cached_or_null(has_cached_file)
		_avatar_in_flight = false
		avatar_loaded.emit(res_fb)
		return res_fb

	var res: Array = await req.request_completed
	req.queue_free()

	# 3. Request failed (e.g. 429, offline) -> fallback to cached image if available
	if res[0] != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200 or url != _avatar_url:
		var res_fb: Texture2D = _fallback_to_cached_or_null(has_cached_file)
		_avatar_in_flight = false
		avatar_loaded.emit(res_fb)
		return res_fb

	var buf: PackedByteArray = res[3]
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if buf.size() > 3 and buf[0] == 0xFF and buf[1] == 0xD8:
		err = img.load_jpg_from_buffer(buf)
	elif buf.size() > 3 and buf[0] == 0x89 and buf[1] == 0x50:
		err = img.load_png_from_buffer(buf)
	elif buf.size() > 12 and buf.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(buf)

	if err != OK:
		var res_fb: Texture2D = _fallback_to_cached_or_null(has_cached_file)
		_avatar_in_flight = false
		avatar_loaded.emit(res_fb)
		return res_fb

	# 4. Download succeeded, write to local cache and timestamp
	img.save_png(AVATAR_IMG_PATH)
	_save_avatar_meta({"url": _avatar_url, "timestamp": now})

	avatar_tex = ImageTexture.create_from_image(img)
	_avatar_in_flight = false
	avatar_loaded.emit(avatar_tex)
	return avatar_tex


## Fallback on failure: continue using expired cached image if available, otherwise return null
func _fallback_to_cached_or_null(has_cached_file: bool) -> Texture2D:
	if has_cached_file:
		var img := Image.load_from_file(AVATAR_IMG_PATH)
		if img != null and not img.is_empty():
			avatar_tex = ImageTexture.create_from_image(img)
			return avatar_tex
	return null


func _save_avatar_meta(data: Dictionary) -> void:
	var f := FileAccess.open(AVATAR_META_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func _load_avatar_meta() -> Dictionary:
	if not FileAccess.file_exists(AVATAR_META_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(AVATAR_META_PATH))
	return parsed if parsed is Dictionary else {}


func logout() -> Array:
	var r: Array = await http_json(HTTPClient.METHOD_POST, "/api/auth/logout", {})
	ai_quota = {"used": 0, "limit": 0}
	ai_enabled = false
	avatar_tex = null
	_avatar_url = ""
	_avatar_tried = false
	await fetch_me()
	return r


## Google sign-in: FedCM / One Tap priority, automatically falls back to redirect on failure (implemented in GoogleAuth autoload)
func google_sign_in() -> void:
	GoogleAuth.sign_in()


## Direct OAuth redirect (fallback entry point when FedCM is disabled and in cooldown)
func google_sign_in_redirect() -> void:
	GoogleAuth.sign_in_redirect()


func fetch_profile(user_id: String = "") -> Array:
	var path := "/api/profile"
	if user_id.strip_edges() != "":
		path += "?user=" + user_id.strip_edges().uri_encode()
	return await http_json(HTTPClient.METHOD_GET, path)


func is_logged_in() -> bool:
	return user_profile.get("user") != null and user_profile.get("user") is Dictionary


func is_trainer() -> bool:
	return is_logged_in() and bool(user_profile.get("user", {}).get("trainer", false))


func get_user() -> Dictionary:
	if is_logged_in():
		return user_profile.get("user", {})
	return {}


func get_ai_remaining() -> int:
	if not is_logged_in():
		return 0
	return maxi(0, int(ai_quota.get("limit", 0)) - int(ai_quota.get("used", 0)))


# ───────── WebSocket ─────────

func join(code: String, resume_seat := false) -> void:
	# leave() clears the solo flag; preserve it so solo practice is not remembered as a resumable room
	var solo := is_solo
	leave(false)
	is_solo = solo
	room_code = code.strip_edges().to_upper()
	player_id = str(saved_seat.get("playerId", "")) if resume_seat and str(saved_seat.get("room", "")) == room_code else ""
	state = {}
	_want_connected = true
	_open_socket()


func join_local() -> void:
	var solo := is_solo
	leave(false)
	is_solo = solo
	_local = true
	_local_connected_emitted = false
	room_code = "LOCAL"
	player_id = ""
	state = {}
	if OS.has_feature("web") and not Engine.is_editor_hint():
		var local_iface = JavaScriptBridge.get_interface("iqLocal")
		if local_iface:
			local_iface.open()
	_send_local_hello()


func _send_local_hello() -> void:
	await get_tree().process_frame
	if _local:
		send({"t": "hello", "playerId": player_id, "name": player_name})


func leave(forget_seat := true) -> void:
	if _local:
		if OS.has_feature("web") and not Engine.is_editor_hint():
			var local_iface = JavaScriptBridge.get_interface("iqLocal")
			if local_iface:
				local_iface.close()
		_local = false
		_local_connected_emitted = false
	if forget_seat and not saved_seat.is_empty():
		saved_seat = {}
		save_prefs()
	_want_connected = false
	if _ws:
		_ws.close()
	_ws = null
	_was_open = false
	room_code = ""
	is_solo = false
	state = {}


func _close_room(message: String) -> void:
	leave()
	room_closed.emit(message)


var _checking_room := false

## Asks the server whether the room still exists; a 404 means it was deleted, so stop reconnecting.
func _check_room_gone(code: String) -> void:
	if _checking_room:
		return
	_checking_room = true
	var req := HTTPRequest.new()
	req.timeout = 10.0
	req.accept_gzip = false
	add_child(req)
	var err := req.request(base_url + "/api/rooms/%s/info" % code)
	if err != OK:
		req.queue_free()
		_checking_room = false
		return
	var res: Array = await req.request_completed
	req.queue_free()
	_checking_room = false
	if res[0] == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 404 and room_code == code and _want_connected:
		_close_room("房間已不存在")


func _ws_url() -> String:
	var u := base_url.replace("https://", "wss://").replace("http://", "ws://")
	return "%s/api/rooms/%s/ws" % [u, room_code]


func _open_socket() -> void:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	_hello_sent = false
	var err := _ws.connect_to_url(_ws_url())
	if err != OK:
		_ws = null
		_retry_at = Time.get_ticks_msec() / 1000.0 + 2.0


func send(msg: Dictionary) -> void:
	if _local:
		if OS.has_feature("web") and not Engine.is_editor_hint():
			var local_iface = JavaScriptBridge.get_interface("iqLocal")
			if local_iface:
				local_iface.send(JSON.stringify(msg))
		return
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))


func act(action: Dictionary) -> void:
	send({"t": "action", "action": action})


func is_online() -> bool:
	if _local:
		return true
	return _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _local:
		if not _local_connected_emitted:
			_local_connected_emitted = true
			connection_changed.emit(true)
		if OS.has_feature("web"):
			var local_iface = JavaScriptBridge.get_interface("iqLocal")
			if local_iface:
				var raw = local_iface.drain()
				if typeof(raw) == TYPE_STRING and raw != "":
					var arr = JSON.parse_string(raw)
					if arr is Array:
						for item in arr:
							_handle(JSON.stringify(item))
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _ws == null:
		if _want_connected and now >= _retry_at and room_code != "":
			_open_socket()
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			connection_changed.emit(true)
		if not _hello_sent:
			_hello_sent = true
			send({"t": "hello", "playerId": player_id, "name": player_name})
		if now >= _ping_at:
			_ping_at = now + 20.0
			send({"t": "ping"})
		while _ws.get_available_packet_count() > 0:
			_handle(_ws.get_packet().get_string_from_utf8())
	elif st == WebSocketPeer.STATE_CLOSED:
		var opened := _was_open
		if _was_open:
			connection_changed.emit(false)
		_was_open = false
		_ws = null
		_retry_at = now + 2.0
		# A socket that never opened may mean the room was deleted; stop retrying if so.
		if not opened and _want_connected and room_code != "":
			_check_room_gone(room_code)


func _handle(text: String) -> void:
	var m = JSON.parse_string(text)
	if not (m is Dictionary):
		return
	match str(m.get("t", "")):
		"welcome":
			if m.get("playerId") != null:
				player_id = str(m["playerId"])
			spectator = bool(m.get("spectator", false))
			# Remember seat; room code is only for multiplayer, solo practice or spectators do not remember room code
			saved_seat = {} if (spectator or is_solo or _local) else {"room": room_code, "playerId": player_id}
			save_prefs()
			ai_enabled = bool(m.get("ai", false)) and is_logged_in()
			static_data = m.get("static", {})
			if m.get("me") != null and m["me"] is Dictionary:
				welcome_me = m["me"]
				if m["me"].get("ai") is Dictionary:
					var ai_dict: Dictionary = m["me"]["ai"]
					ai_quota = {"used": int(ai_dict.get("used", 0)), "limit": int(ai_dict.get("limit", 50))}
					quota_changed.emit(int(ai_quota["used"]), int(ai_quota["limit"]), false)
			else:
				if not is_logged_in():
					ai_quota = {"used": 0, "limit": 0}
					quota_changed.emit(0, 0, false)
			welcomed.emit(m)
		"state":
			state = m["state"]
			state_changed.emit(state)
		"error":
			server_error.emit(str(m.get("message", "錯誤")))
		"closed":
			_close_room(str(m.get("message", "房間已關閉")))
		"react":
			reaction.emit(str(m.get("from", "")), str(m.get("emoji", "")))
		"stream":
			stream_text.emit(str(m.get("text", "")))
			if bool(m.get("answerDone", false)):
				stream_answer_done.emit()
		"quota":
			var used: int = int(m.get("used", 0))
			var limit: int = int(m.get("limit", 50))
			var exhausted: bool = bool(m.get("exhausted", false))
			ai_quota = {"used": used, "limit": limit}
			quota_changed.emit(used, limit, exhausted)


# ───────── State Helpers ─────────

func me() -> Dictionary:
	for p in state.get("players", []):
		if str(p["id"]) == player_id:
			return p
	return {}


func current_player() -> Dictionary:
	var ps: Array = state.get("players", [])
	var t := int(state.get("turn", 0))
	return ps[t] if t < ps.size() else {}


func is_my_turn() -> bool:
	return state.get("phase", "") == "playing" and str(current_player().get("id", "")) == player_id


func is_host() -> bool:
	return str(state.get("hostId", "")) == player_id


func is_multiplayer() -> bool:
	if is_solo or _local:
		return false
	var human_count := 0
	for p in state.get("players", []):
		if not bool(p.get("isBot", false)):
			human_count += 1
	return human_count > 1 or str(state.get("phase", "")) == "lobby"
