extends RefCounted
## Per-attempt local checkpoints. Web uses synchronous localStorage so closing a tab
## cannot outrun an IndexedDB sync; native builds use atomic file replacement.
var storage_dir := "user://training_attempts"
var storage_key := "iq-training-attempts-v1"
var attempts: Dictionary = {}
var last_error := ""
var active_id := ""

func load_records() -> void:
	attempts.clear()
	if OS.has_feature("web"):
		var raw: Variant = JavaScriptBridge.eval("(function(){try{return localStorage.getItem(" + JSON.stringify(storage_key) + ");}catch(e){return null;}})()", true)
		var parsed: Variant = JSON.parse_string(str(raw)) if raw != null else null
		if parsed is Dictionary: attempts = parsed
	else:
		var folder := DirAccess.open(storage_dir)
		if folder != null:
			for file: String in folder.get_files():
				if file.ends_with(".json"):
					var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(storage_dir.path_join(file)))
					if parsed is Dictionary and parsed.has("attempt_id"):
						attempts[str(parsed.attempt_id)] = parsed

func _write(record: Dictionary) -> bool:
	last_error = ""
	attempts[str(record.attempt_id)] = record
	if OS.has_feature("web"):
		var script := "(function(){try{localStorage.setItem(%s,%s);return true;}catch(e){return false;}})()" % [JSON.stringify(storage_key), JSON.stringify(JSON.stringify(attempts))]
		if not bool(JavaScriptBridge.eval(script, true)):
			last_error = "本機儲存失敗，請檢查瀏覽器可用空間後重試"
			return false
		return true
	var error := DirAccess.make_dir_recursive_absolute(storage_dir)
	if error != OK and error != ERR_ALREADY_EXISTS:
		last_error = "無法建立訓練紀錄資料夾"
		return false
	var path := storage_dir.path_join(str(record.attempt_id).sha256_text() + ".json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "訓練紀錄無法寫入，請重試"
		return false
	file.store_string(JSON.stringify(record))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		last_error = "訓練紀錄儲存失敗，請重試"
		return false
	return true

func checkpoint(state: Dictionary, player_id: String, game_id: String, owner: String) -> bool:
	if str(state.get("phase", "")) not in ["playing", "ended"]: return true
	var me: Dictionary = {}
	for player: Dictionary in state.get("players", []):
		if str(player.get("id", "")) == player_id and not bool(player.get("isBot", false)):
			me = player
	if me.is_empty(): return true
	var now := int(Time.get_unix_time_from_system() * 1000)
	var identity: String = state.get("trainingAttemptId", "") if state.get("trainingAttemptId") is String else ""
	if identity.is_empty(): identity = game_id
	if not identity.ends_with(":" + player_id): identity += ":" + player_id
	active_id = identity
	var record: Dictionary = attempts.get(identity, {"attempt_id": identity, "owner": owner, "started_at": now, "data": {"decisions": [], "interviews": {}, "stages": []}}).duplicate(true)
	if str(record.get("owner", "")) != owner:
		last_error = "紀錄帳號不符，未覆寫"
		return false
	record.name = str(me.get("name", "顧問"))
	record.room = str(state.get("code", game_id))
	record.updated_at = now
	record.status = "completed" if state.get("phase") == "ended" else "in_progress"
	record.round = int(state.get("round", 1))
	record.stage = str(state.get("turnStage", "roll"))
	var data: Dictionary = record.data
	var incoming: Array = me.get("decisions", [])
	var decisions: Array = data.get("decisions", [])
	# The public state contains a rolling tail. Match the longest suffix/prefix
	# overlap, preserving even repeated identical decisions without duplicates.
	var overlap := 0
	for count: int in range(1, mini(decisions.size(), incoming.size()) + 1):
		if decisions.slice(decisions.size() - count) == incoming.slice(0, count): overlap = count
	decisions.append_array(incoming.slice(overlap))
	data.decisions = decisions
	data.book = me.get("book", []).duplicate(true)
	data.metrics = {"reputation": me.get("reputation", 0), "commission": me.get("commission", 0)}
	data.quizCorrect = me.get("quizCorrect", 0)
	data.quizTotal = me.get("quizTotal", 0)
	var session: Variant = state.get("session")
	if session is Dictionary and str(session.get("playerId", "")) == player_id:
		var client: Dictionary = session.get("client", {})
		var key := "%s:%s" % [record.round, str(client.get("id", ""))]
		data.interviews[key] = session.duplicate(true)
		data.currentSession = session.duplicate(true)
		record.stage = str(session.get("step", ""))
		record.client = str(client.get("name", ""))
		var stage_key := key + ":" + str(record.stage)
		var stages: Array = data.stages
		if stages.is_empty() or stages.back().get("key", "") != stage_key:
			stages.append({"key": stage_key, "at": now, "client": record.client, "stage": record.stage})
	for result: Dictionary in state.get("final", []) if state.get("final") is Array else []:
		if str(result.get("playerId", "")) == player_id:
			data.final = result.duplicate(true)
			record.score = result.get("score", 0)
			record.grade = result.get("grade", "")
	return _write(record)

func close_attempt() -> bool:
	if active_id.is_empty() or not attempts.has(active_id): return true
	var record: Dictionary = attempts[active_id].duplicate(true)
	active_id = ""
	if record.get("status") == "completed": return true
	record.status = "abandoned"
	record.updated_at = int(Time.get_unix_time_from_system() * 1000)
	return _write(record)

func retry() -> bool:
	var okay := true
	var failure := ""
	for record: Dictionary in attempts.values():
		if not _write(record):
			okay = false
			failure = last_error
	last_error = failure
	return okay

func delete_owner(owner: String) -> bool:
	var okay := true
	for id: String in attempts.keys():
		if str(attempts[id].get("owner", "")) != owner: continue
		attempts.erase(id)
		if id == active_id: active_id = ""
		if not OS.has_feature("web"):
			var path := storage_dir.path_join(id.sha256_text() + ".json")
			if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK: okay = false
	if OS.has_feature("web"):
		okay = bool(JavaScriptBridge.eval("(function(){try{localStorage.setItem(%s,%s);return true;}catch(e){return false;}})()" % [JSON.stringify(storage_key), JSON.stringify(JSON.stringify(attempts))], true))
	return okay

func list_records(owner: String) -> Array:
	var result: Array = []
	for record: Dictionary in attempts.values():
		if str(record.get("owner", "")) == owner: result.append(record.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.updated_at) > int(b.updated_at))
	return result
