@tool
class_name Portraits
## Static cache and loader for client portraits (Batch 8 / Batch 9 contract).
## Prioritizes res://assets/portraits/<id>.jpg, falling back to scene illustration or name initial.

static var _cache: Dictionary = {}


static func get_texture(client_id: String) -> Texture2D:
	if client_id == "" or client_id == "null":
		return null
	# AI-generated clients map to a shared generic portrait (state.portraits: clientId -> pool key)
	var key := client_id
	if not Engine.is_editor_hint():
		var pmap: Variant = Net.state.get("portraits", {})
		if pmap is Dictionary and (pmap as Dictionary).has(client_id):
			key = str(pmap[client_id])
	if _cache.has(key):
		return _cache[key]

	# 1. Primary path: res://assets/portraits/<id or pool key>.<ext>
	for ext in ["jpg", "webp", "png"]:
		var p := "res://assets/portraits/%s.%s" % [key, ext]
		if ResourceLoader.exists(p):
			var tex: Texture2D = load(p)
			if tex != null:
				_cache[key] = tex
				return tex

	# 2. Fallback: dedicated illustration or matched scene
	var scene_p := UI.client_scene_path(client_id)
	if scene_p != "" and ResourceLoader.exists(scene_p):
		var tex: Texture2D = load(scene_p)
		if tex != null:
			_cache[client_id] = tex
			return tex

	_cache[client_id] = null
	return null


static func has_portrait(client_id: String) -> bool:
	return get_texture(client_id) != null


static func create_avatar(client_id: String, client_name: String, size := 40) -> Control:
	var tex := get_texture(client_id)
	return UI.avatar(tex, client_name, size)


static func clear_cache() -> void:
	_cache.clear()
	_player_cache.clear()


# Player avatar cache (Batch 11 contract)
static var _player_cache: Dictionary = {}        # url -> Texture2D
static var _failed_urls: Dictionary = {}         # url -> true (never retry in same session)
static var _in_flight: Dictionary = {}           # url -> true
static var _queue: Array[String] = []            # urls queued for download
static var _active_requests: int = 0
const MAX_CONCURRENT_AVATARS := 4

static var _avatar_callbacks: Array[Callable] = []


static func add_player_avatar_callback(cb: Callable) -> void:
	if not _avatar_callbacks.has(cb):
		_avatar_callbacks.append(cb)


static func remove_player_avatar_callback(cb: Callable) -> void:
	_avatar_callbacks.erase(cb)


static func _notify_avatar_loaded(url: String, tex: Texture2D) -> void:
	var valid: Array[Callable] = []
	for cb in _avatar_callbacks:
		if cb.is_valid():
			valid.append(cb)
			cb.call(url, tex)
	_avatar_callbacks = valid


static func get_player_avatar(url: String) -> Texture2D:
	if url == "" or url == "null":
		return null
	# Prefer local player cached avatar if this URL belongs to local player
	if not Engine.is_editor_hint():
		if Net != null:
			if Net.avatar_tex != null and Net.is_logged_in() and str(Net.get_user().get("picture", "")) == url:
				return Net.avatar_tex

	if _player_cache.has(url):
		return _player_cache[url]

	if Engine.is_editor_hint():
		return null

	if not url.begins_with("https://"):
		return null

	if _failed_urls.has(url):
		return null

	if not _in_flight.has(url) and not _queue.has(url):
		_queue.append(url)
		_pump_avatar_queue()

	return null


static func _pump_avatar_queue() -> void:
	if Engine.is_editor_hint():
		return
	while _active_requests < MAX_CONCURRENT_AVATARS and not _queue.is_empty():
		var url: String = _queue.pop_front()
		if url == "" or _failed_urls.has(url) or _player_cache.has(url) or _in_flight.has(url):
			continue
		_in_flight[url] = true
		_active_requests += 1
		_start_download(url)


static func _start_download(url: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_on_download_finished(url, null, false)
		return

	var parent: Node = null
	if Net != null and Net.is_inside_tree():
		parent = Net
	elif tree.root != null:
		parent = tree.root

	if parent == null:
		_on_download_finished(url, null, false)
		return

	var req := HTTPRequest.new()
	req.timeout = 10.0
	req.accept_gzip = false
	parent.add_child(req)

	req.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		var success := false
		var tex: Texture2D = null
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var img := Image.new()
			var err := ERR_FILE_UNRECOGNIZED
			if body.size() > 3 and body[0] == 0xFF and body[1] == 0xD8:
				err = img.load_jpg_from_buffer(body)
			elif body.size() > 3 and body[0] == 0x89 and body[1] == 0x50:
				err = img.load_png_from_buffer(body)
			elif body.size() > 12 and body.slice(8, 12).get_string_from_ascii() == "WEBP":
				err = img.load_webp_from_buffer(body)

			if err == OK and not img.is_empty():
				tex = ImageTexture.create_from_image(img)
				success = (tex != null)

		_on_download_finished(url, tex, success)
	)

	var err := req.request(url)
	if err != OK:
		req.queue_free()
		_on_download_finished(url, null, false)


static func _on_download_finished(url: String, tex: Texture2D, success: bool) -> void:
	_in_flight.erase(url)
	_active_requests = maxi(0, _active_requests - 1)
	if success and tex != null:
		_player_cache[url] = tex
		_notify_avatar_loaded(url, tex)
	else:
		_failed_urls[url] = true

	_pump_avatar_queue()
