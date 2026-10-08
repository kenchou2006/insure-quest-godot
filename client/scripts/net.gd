extends Node
## 網路層（Autoload "Net"）：HTTP 建房／查紀錄＋WebSocket 房間連線與自動重連。
## 網頁版預設連回同源（Worker 同時提供網頁與 API），桌面版預設連本機 wrangler dev。

signal welcomed(data: Dictionary)
signal state_changed(state: Dictionary)
signal server_error(message: String)
signal reaction(from_name: String, emoji: String)
signal connection_changed(online: bool)
signal quota_changed(used: int, limit: int, exhausted: bool)
signal auth_changed()

const DEFAULT_DESKTOP_URL := "http://127.0.0.1:8787"

var base_url := DEFAULT_DESKTOP_URL
var room_code := ""
var player_id := ""
var player_name := "顧問"
var spectator := false
var ai_enabled := false
var static_data: Dictionary = {}
## 上次的座位 {room, playerId}：重新整理頁面後可以回到原本的位置
var saved_seat: Dictionary = {}
var state: Dictionary = {}
var auth_config: Dictionary = {}
var user_profile: Dictionary = {}
var ai_quota: Dictionary = {"used": 0, "limit": 100}
var welcome_me: Variant = null

var _ws: WebSocketPeer = null
var _was_open := false
var _want_connected := false
var _retry_at := 0.0
var _ping_at := 0.0
var _hello_sent := false


func _ready() -> void:
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

## 回傳 [ok: bool, data: Variant]
func http_json(method: int, path: String, body: Variant = null) -> Array:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	# 網頁版由瀏覽器自動解壓，Godot 再解一次會失敗
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


func create_room() -> Array:
	var r := await http_json(HTTPClient.METHOD_POST, "/api/rooms", {})
	if r[0]:
		return [true, str(r[1].get("code", ""))]
	return r


func fetch_records(name_filter: String) -> Array:
	return await fetch_records_scope("", name_filter)


func fetch_records_scope(scope: String = "", name_filter: String = "") -> Array:
	var q := "/api/records?limit=100"
	# scope 為 "all"＝全部學員（講師）；其他非空值視為學員 id（講師查看單一學員）
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


func fetch_me() -> Array:
	var r: Array = await http_json(HTTPClient.METHOD_GET, "/api/me")
	if bool(r[0]) and r[1] is Dictionary:
		user_profile = r[1]
		if user_profile.get("ai") is Dictionary:
			var ai_dict: Dictionary = user_profile["ai"]
			ai_quota = {"used": int(ai_dict.get("used", 0)), "limit": int(ai_dict.get("limit", 100))}
		auth_changed.emit()
	return r


func logout() -> Array:
	var r: Array = await http_json(HTTPClient.METHOD_POST, "/api/auth/logout", {})
	await fetch_me()
	return r


## Google 登入：FedCM／One Tap 優先，失敗自動退回重新導向（實作在 GoogleAuth autoload）
func google_sign_in() -> void:
	GoogleAuth.sign_in()


## 直接走 OAuth 重新導向（FedCM 被關閉進入冷卻期時的備用入口）
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
	return maxi(0, int(ai_quota.get("limit", 100)) - int(ai_quota.get("used", 0)))


# ───────── WebSocket ─────────

func join(code: String, resume_seat := false) -> void:
	leave(false)
	room_code = code.strip_edges().to_upper()
	player_id = str(saved_seat.get("playerId", "")) if resume_seat and str(saved_seat.get("room", "")) == room_code else ""
	state = {}
	_want_connected = true
	_open_socket()


func leave(forget_seat := true) -> void:
	if forget_seat and not saved_seat.is_empty():
		saved_seat = {}
		save_prefs()
	_want_connected = false
	if _ws:
		_ws.close()
	_ws = null
	_was_open = false
	room_code = ""
	state = {}


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
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))


func act(action: Dictionary) -> void:
	send({"t": "action", "action": action})


func is_online() -> bool:
	return _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func _process(_delta: float) -> void:
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
		if _was_open:
			connection_changed.emit(false)
		_was_open = false
		_ws = null
		_retry_at = now + 2.0


func _handle(text: String) -> void:
	var m = JSON.parse_string(text)
	if not (m is Dictionary):
		return
	match str(m.get("t", "")):
		"welcome":
			if m.get("playerId") != null:
				player_id = str(m["playerId"])
			spectator = bool(m.get("spectator", false))
			# 記住座位；若舊座位已失效（變成旁觀者）就清掉
			saved_seat = {} if spectator else {"room": room_code, "playerId": player_id}
			save_prefs()
			ai_enabled = bool(m.get("ai", false))
			static_data = m.get("static", {})
			if m.get("me") != null and m["me"] is Dictionary:
				welcome_me = m["me"]
				if m["me"].get("ai") is Dictionary:
					var ai_dict: Dictionary = m["me"]["ai"]
					ai_quota = {"used": int(ai_dict.get("used", 0)), "limit": int(ai_dict.get("limit", 100))}
					quota_changed.emit(int(ai_quota["used"]), int(ai_quota["limit"]), false)
			welcomed.emit(m)
		"state":
			state = m["state"]
			state_changed.emit(state)
		"error":
			server_error.emit(str(m.get("message", "錯誤")))
		"react":
			reaction.emit(str(m.get("from", "")), str(m.get("emoji", "")))
		"quota":
			var used: int = int(m.get("used", 0))
			var limit: int = int(m.get("limit", 100))
			var exhausted: bool = bool(m.get("exhausted", false))
			ai_quota = {"used": used, "limit": limit}
			quota_changed.emit(used, limit, exhausted)


# ───────── 狀態輔助 ─────────

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
