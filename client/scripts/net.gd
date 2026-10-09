@tool
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
## 面談中客戶回答的串流片段（目前累積的文字）
signal stream_text(text: String)

const DEFAULT_DESKTOP_URL := "http://localhost:8787"

var base_url := DEFAULT_DESKTOP_URL
var room_code := ""
var player_id := ""
var player_name := "顧問"
var spectator := false
var is_solo := false
var ai_enabled := false
var static_data: Dictionary = {}
## 上次的座位 {room, playerId}：重新整理頁面後可以回到原本的位置（僅限多人房間）
var saved_seat: Dictionary = {}
var state: Dictionary = {}
var auth_config: Dictionary = {}
var user_profile: Dictionary = {}
var ai_quota: Dictionary = {"used": 0, "limit": 0}
var welcome_me: Variant = null
## Google 大頭貼（登入後下載一次；Google 圖片網域允許跨來源，網頁版可直接抓）
var avatar_tex: Texture2D = null
var _avatar_url := ""
var _avatar_tried := false

var _ws: WebSocketPeer = null
var _was_open := false
var _want_connected := false
var _retry_at := 0.0
var _ping_at := 0.0
var _hello_sent := false


func _ready() -> void:
	# 編輯器預覽（@tool）只需要狀態容器，不讀設定也不連線
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


## 顧問等級 {level, title, xp, floor, next, games}；未登入為空
func get_level() -> Dictionary:
	return user_profile.get("level", {}) if user_profile.get("level") is Dictionary else {}


## Google 大頭貼本地快取（期效 7 天，避免頻繁請求觸發 429）
const AVATAR_CACHE_TTL := 7 * 86400
const AVATAR_IMG_PATH := "user://avatar_cache.png"
const AVATAR_META_PATH := "user://avatar_meta.json"


## 下載 Google 大頭貼（帶期效的本地持久化快取，失敗或沒有頭貼時回傳 null）
func fetch_avatar() -> Texture2D:
	if avatar_tex != null or _avatar_tried or _avatar_url == "" or not _avatar_url.begins_with("https://"):
		return avatar_tex
	_avatar_tried = true

	var now := int(Time.get_unix_time_from_system())
	var meta: Dictionary = _load_avatar_meta()
	var cached_url: String = str(meta.get("url", ""))
	var cached_time: int = int(meta.get("timestamp", 0))
	var has_cached_file: bool = FileAccess.file_exists(AVATAR_IMG_PATH)

	# 1. 本地有圖、網址相同，且尚未過期（< 7 天）-> 直接讀取本地快取，不發任何網路請求
	if has_cached_file and cached_url == _avatar_url and (now - cached_time) < AVATAR_CACHE_TTL:
		var img := Image.load_from_file(AVATAR_IMG_PATH)
		if img != null and not img.is_empty():
			avatar_tex = ImageTexture.create_from_image(img)
			return avatar_tex

	# 2. 已過期、網址改變，或第一次進入 -> 向 Google 下載
	var url := _avatar_url
	var req := HTTPRequest.new()
	req.timeout = 10.0
	req.accept_gzip = false
	add_child(req)
	if req.request(url) != OK:
		req.queue_free()
		return _fallback_to_cached_or_null(has_cached_file)

	var res: Array = await req.request_completed
	req.queue_free()

	# 3. 請求失敗（例如 429、離線）-> 觸發舊圖兜底，有舊圖就繼續用舊圖
	if res[0] != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200 or url != _avatar_url:
		return _fallback_to_cached_or_null(has_cached_file)

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
		return _fallback_to_cached_or_null(has_cached_file)

	# 4. 下載成功，寫入本地快取與時間戳
	img.save_png(AVATAR_IMG_PATH)
	_save_avatar_meta({"url": _avatar_url, "timestamp": now})

	avatar_tex = ImageTexture.create_from_image(img)
	return avatar_tex


## 失敗時兜底：若有過期舊圖繼續使用，無舊圖則回傳 null
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
	if not is_logged_in():
		return 0
	return maxi(0, int(ai_quota.get("limit", 0)) - int(ai_quota.get("used", 0)))


# ───────── WebSocket ─────────

func join(code: String, resume_seat := false) -> void:
	# leave() 會清掉單人標記；保留下來，單人練習才不會被記成可回去的房間
	var solo := is_solo
	leave(false)
	is_solo = solo
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
	is_solo = false
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
	if Engine.is_editor_hint():
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
			# 記住座位；房間代號僅用於多人連線，單人練習或旁觀者不記憶房間代號
			saved_seat = {} if (spectator or is_solo) else {"room": room_code, "playerId": player_id}
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
		"react":
			reaction.emit(str(m.get("from", "")), str(m.get("emoji", "")))
		"stream":
			stream_text.emit(str(m.get("text", "")))
		"quota":
			var used: int = int(m.get("used", 0))
			var limit: int = int(m.get("limit", 50))
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


func is_multiplayer() -> bool:
	if is_solo:
		return false
	var human_count := 0
	for p in state.get("players", []):
		if not bool(p.get("isBot", false)):
			human_count += 1
	return human_count > 1 or str(state.get("phase", "")) == "lobby"
