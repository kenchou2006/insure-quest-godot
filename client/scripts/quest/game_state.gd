extends Node
## GameState (autoload): the mission data every page reads, in one place.
## The server stays authoritative for the board, the client profile, metrics, scores and AI text
## (read live from Net.state). This node adds the client-side training layer the server has no
## notion of: the per-client meeting clock, the decision history with reasons, clue / coverage /
## dialogue choices, compliance scan results, event responses, briefcase uses and advisor XP.
## Records are kept per room + player + client and saved, so a reload resumes the same clock.

signal changed
signal timer_tick(remaining: float, total: float)
## 60, 30, 10 … 1, 0 (seconds left) — each fires once per client
signal timer_mark(mark: int)
signal decision_added(entry: Dictionary)
signal client_changed(client_id: String)

const SAVE_PATH := "user://quest_state.cfg"
const PROFILE_PATH := "user://quest_profile.cfg"
## Meeting budget by difficulty (seconds): 入門 8, 進階 10, 挑戰 12 minutes
const BUDGET := {"入門": 480.0, "進階": 600.0, "挑戰": 720.0}
const DEFAULT_BUDGET := 600.0
const XP_PER_LEVEL := 200
const SETTINGS_PATH := "user://quest_settings.cfg"
## Text display speed: 0 = instant, 0.6 slow, 1 normal, 1.8 fast
const TEXT_SPEEDS := {"慢": 0.6, "標準": 1.0, "快": 1.8, "立即": 0.0}

## The classic panels stay one switch away (?classic=1 on web, or set from tests)
var classic_ui := false
## Set by the mission layer while a page that runs the clock is on screen
var timed_page := false
## Reasons the clock is held by pages themselves (settings pause, critical reveal …)
var holds: Dictionary = {}

var client_id := ""
var record: Dictionary = {}
var _records: Dictionary = {}
var _game_key := ""
var _save_timer := 0.0
var _marks_fired: Dictionary = {}
var _visited: Array = []
var _last_pos := -1
var profile_xp := 0
var text_speed := 1.0
var subtitles := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web") and not Engine.is_editor_hint():
		var q = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('classic') || ''", true)
		classic_ui = str(q) == "1"
	var prof := ConfigFile.new()
	if prof.load(PROFILE_PATH) == OK:
		profile_xp = int(prof.get_value("advisor", "xp", 0))
	var st := ConfigFile.new()
	if st.load(SETTINGS_PATH) == OK:
		text_speed = float(st.get_value("text", "speed", 1.0))
		subtitles = bool(st.get_value("text", "subtitles", true))
	if not Engine.is_editor_hint():
		Net.state_changed.connect(_on_state)


# --- Live data from the server state (spec names) -------------------------------------------------

func state() -> Dictionary:
	return Net.state


func my_session() -> Dictionary:
	var s: Variant = Net.state.get("session")
	if s is Dictionary and str((s as Dictionary).get("playerId", "")) == Net.player_id:
		return s
	return {}


func my_event() -> Dictionary:
	var e: Variant = Net.state.get("event")
	if e is Dictionary and str((e as Dictionary).get("playerId", "")) == Net.player_id and not (Net.state.get("session") is Dictionary):
		return e
	return {}


func main_case() -> Dictionary:
	var mc: Variant = Net.me().get("mainCase")
	return mc if mc is Dictionary else {}


## Full client card: the live session client, else the primary case from caseOptions
func current_client() -> Dictionary:
	var sess := my_session()
	if not sess.is_empty() and sess.get("client") is Dictionary:
		return sess.client
	var mc := main_case()
	var id := str(mc.get("clientId", ""))
	if id == "":
		return {}
	for c in Net.state.get("caseOptions", []):
		if c is Dictionary and str(c.get("id", "")) == id:
			return c
	return {"id": id, "name": mc.get("clientName", ""), "job": mc.get("job", ""), "amount": mc.get("amount", "")}


func client_name() -> String:
	return str(current_client().get("name", ""))


func client_portrait() -> Texture2D:
	var c := current_client()
	var id := str(c.get("id", ""))
	if id == "" or Engine.is_editor_hint():
		return null
	var key := str((Net.state.get("portraits", {}) as Dictionary).get(id, id)) if Net.state.get("portraits") is Dictionary else id
	return Portraits.get_texture(key)


func client_portrait_id() -> String:
	var id := str(current_client().get("id", ""))
	if Net.state.get("portraits") is Dictionary:
		return str((Net.state.portraits as Dictionary).get(id, id))
	return id


func client_age() -> int:
	return int(current_client().get("age", 0))


func client_job() -> String:
	return str(current_client().get("job", ""))


func client_family() -> String:
	return str(current_client().get("family", ""))


## 目標金額 and income note (the server has no monthly premium figure)
func client_budget() -> Dictionary:
	var c := current_client()
	return {"amount": str(c.get("amount", "")), "income": str(c.get("incomeInfo", "")), "units": 10}


## Needs the advisor has actually uncovered: answer keys and observed real clue facts
func client_needs() -> Array:
	var out: Array = []
	var sess := my_session()
	for a in sess.get("asked", []):
		var k: Variant = (a as Dictionary).get("key")
		if k != null and str(k) != "" and not out.has(str(k)):
			out.append(str(k))
	for cl in sess.get("clues", []):
		var d := cl as Dictionary
		if bool(d.get("observed", false)) and bool(d.get("real", false)) and str(d.get("fact", "")) != "":
			if not out.has(str(d.fact)):
				out.append(str(d.fact))
	return out


func metrics() -> Dictionary:
	var sess := my_session()
	if sess.get("metrics") is Dictionary:
		return sess.metrics
	var mc := main_case()
	if mc.get("metrics") is Dictionary:
		return mc.metrics
	return {}


func trust() -> float:
	return float(metrics().get("trust", 50))


func needs_insight() -> float:
	return float(metrics().get("insight", 20))


func budget_fit() -> float:
	return float(metrics().get("fit", 50))


func compliance() -> float:
	return float(metrics().get("compliance", 100))


func risk_level() -> String:
	var r := float(metrics().get("risk", 30))
	return "低" if r >= 70 else ("中" if r >= 45 else "高")


func dice_value() -> int:
	var v: Variant = Net.state.get("lastRoll")
	return int(v) if v != null else 0


func current_node() -> int:
	return int(Net.me().get("pos", 0))


func board() -> Array:
	return Net.static_data.get("board", [])


## Next station worth knowing: the next client tile ahead (where the case continues)
func next_node() -> int:
	var b := board()
	if b.size() != 24:
		return -1
	var pos := current_node()
	for k in range(1, 25):
		var i := (pos + k) % 24
		if str((b[i] as Dictionary).get("type", "")) == "client":
			return i
	return -1


func completed_nodes() -> Array:
	return _visited.duplicate()


## Stations beyond one roll (more than 6 ahead) and not yet visited
func locked_nodes() -> Array:
	var out: Array = []
	var pos := current_node()
	for i in range(24):
		var ahead := posmod(i - pos, 24)
		if ahead > 6 and not _visited.has(i):
			out.append(i)
	return out


func current_stage() -> int:
	return int(Net.state.get("round", 1))


func total_stages() -> int:
	return int((Net.state.get("settings", {}) as Dictionary).get("rounds", 6))


func decision_history() -> Array:
	return record.get("decisions", [])


func server_decisions() -> Array:
	return Net.me().get("decisions", [])


func latest_feedback() -> String:
	var d := decision_history()
	if not d.is_empty():
		return str((d.back() as Dictionary).get("detail", ""))
	var sd := server_decisions()
	if not sd.is_empty():
		return str((sd.back() as Dictionary).get("body", ""))
	return ""


func selected_clues() -> Dictionary:
	return record.get("clues", {})


func selected_coverage() -> Dictionary:
	return record.get("coverage", {})


func selected_dialogue() -> Dictionary:
	return record.get("dialogue", {})


func advisor_xp() -> int:
	return profile_xp


func advisor_level() -> int:
	return 1 + profile_xp / XP_PER_LEVEL


func secretary() -> Node:
	var m := get_tree().current_scene if get_tree() else null
	if m and m.has_method("secretary_guide"):
		return m.secretary_guide()
	return null


func selected_secretary() -> String:
	var g := secretary()
	if g and bool(g.get("enabled")):
		return str(g.call("selected_secretary"))
	return "none"


func secretary_voice() -> bool:
	var g := secretary()
	return g != null and bool(g.get("voice_on"))


func tutorial_completed() -> bool:
	return Tutorial.get_local_games() > 0


# --- Reading settings ------------------------------------------------------------------------

## Seconds per character for typewriters (0 = whole line at once)
func char_seconds(base := 0.03) -> float:
	return 0.0 if text_speed <= 0.0 else base / text_speed


func set_text_speed(v: float) -> void:
	text_speed = v
	_save_settings()


func set_subtitles(on: bool) -> void:
	subtitles = on
	_save_settings()


func _save_settings() -> void:
	var st := ConfigFile.new()
	st.set_value("text", "speed", text_speed)
	st.set_value("text", "subtitles", subtitles)
	st.save(SETTINGS_PATH)
	changed.emit()


# --- Client record ------------------------------------------------------------------------------

func _new_record(id: String, difficulty: String) -> Dictionary:
	var total: float = BUDGET.get(difficulty, DEFAULT_BUDGET)
	return {
		"client_id": id, "total": total, "remaining": total, "overtime": 0.0,
		"decisions": [], "clues": {}, "coverage": {}, "dialogue": {}, "scan": {},
		"events": [], "tools": {}, "hints": 0, "flags": {}, "xp": 0, "time_spent": [],
		"comm": {"listen": 0, "empathy": 0, "clarity": 0, "count": 0},
		"marks": {},
	}


## Switches the clock and record to this client (each client keeps its own clock)
func ensure_client(id: String, difficulty := "") -> void:
	if id == "" or id == client_id:
		return
	if client_id != "":
		_records[client_id] = record
	client_id = id
	record = _records.get(id, _new_record(id, difficulty))
	_records[id] = record
	_marks_fired = record.get("marks", {})
	client_changed.emit(id)
	changed.emit()
	_queue_save()


func total_time() -> float:
	return float(record.get("total", DEFAULT_BUDGET))


func remaining_time() -> float:
	return float(record.get("remaining", DEFAULT_BUDGET))


func overtime() -> float:
	return float(record.get("overtime", 0.0))


func time_ratio() -> float:
	return clampf(remaining_time() / maxf(1.0, total_time()), 0.0, 1.0)


func flag(key: String, default: Variant = null) -> Variant:
	return (record.get("flags", {}) as Dictionary).get(key, default)


func set_flag(key: String, value: Variant) -> void:
	if record.is_empty():
		return
	(record["flags"] as Dictionary)[key] = value
	changed.emit()
	_queue_save()


func set_value(key: String, value: Variant) -> void:
	if record.is_empty():
		return
	record[key] = value
	changed.emit()
	_queue_save()


## Records a decision with its reason and effects (shown in results and the report)
func add_decision(stage: String, title: String, detail: String, quality := "ok", effects := {}) -> void:
	if record.is_empty():
		return
	var entry := {"stage": stage, "title": title, "detail": detail, "quality": quality,
		"effects": effects, "round": current_stage(), "client": client_name(),
		"clock": remaining_time()}
	(record["decisions"] as Array).append(entry)
	decision_added.emit(entry)
	changed.emit()
	_queue_save()


## Time cost of a choice (wrong clue, detour, hint …); can run into overtime, never blocks
func spend_time(seconds: float, reason: String) -> void:
	if record.is_empty() or seconds <= 0:
		return
	var rem := remaining_time() - seconds
	if rem < 0:
		record["overtime"] = overtime() - rem
		rem = 0.0
	record["remaining"] = rem
	(record["time_spent"] as Array).append({"seconds": seconds, "reason": reason})
	timer_tick.emit(rem, total_time())
	_check_marks(rem)
	changed.emit()
	_queue_save()


func add_comm(listen: int, empathy: int, clarity: int) -> void:
	var c: Dictionary = record.get("comm", {})
	c["listen"] = int(c.get("listen", 0)) + listen
	c["empathy"] = int(c.get("empathy", 0)) + empathy
	c["clarity"] = int(c.get("clarity", 0)) + clarity
	c["count"] = int(c.get("count", 0)) + 1
	record["comm"] = c
	_queue_save()


## 0..100 communication score from the composed answers (50 when nothing composed yet)
func comm_score() -> float:
	var c: Dictionary = record.get("comm", {})
	var n := int(c.get("count", 0))
	if n == 0:
		return 50.0
	return clampf(50.0 + (float(c.get("listen", 0)) + float(c.get("empathy", 0)) + float(c.get("clarity", 0))) / n * 8.0, 0, 100)


## Time management 0..100: time left helps, overtime costs 2 points per 10 s
func time_score() -> float:
	return clampf(60.0 + time_ratio() * 40.0 - overtime() / 5.0, 0, 100)


func add_xp(amount: int, reason: String) -> void:
	if amount <= 0:
		return
	record["xp"] = int(record.get("xp", 0)) + amount
	profile_xp += amount
	var prof := ConfigFile.new()
	prof.load(PROFILE_PATH)
	prof.set_value("advisor", "xp", profile_xp)
	prof.save(PROFILE_PATH)
	add_decision("經驗值", "顧問經驗 +%d" % amount, reason, "good")


func game_xp() -> int:
	var total := 0
	for id in _records:
		total += int((_records[id] as Dictionary).get("xp", 0))
	return total


func all_records() -> Dictionary:
	if client_id != "":
		_records[client_id] = record
	return _records


# --- Clock --------------------------------------------------------------------------------------

## Held while: secretary speaks / modal guide / tutorial / settings pause / transition / AI waits /
## not my turn / no timed page on screen
func clock_running() -> bool:
	if record.is_empty() or not timed_page or not holds.is_empty():
		return false
	if not Net.is_my_turn():
		return false
	if TutorialManager.blocking():
		return false
	if SceneTransitionManager.active:
		return false
	var sess := my_session()
	if bool(sess.get("aiBusy", false)) or bool(Net.state.get("aiPending", false)):
		return false
	return true


func hold(reason: String, on: bool) -> void:
	if on:
		holds[reason] = true
	else:
		holds.erase(reason)


func _process(delta: float) -> void:
	if _save_timer > 0:
		_save_timer -= delta
		if _save_timer <= 0:
			_save()
	if not clock_running():
		return
	var rem := remaining_time() - delta
	if rem < 0:
		record["overtime"] = overtime() - rem
		rem = 0.0
	record["remaining"] = rem
	timer_tick.emit(rem, total_time())
	_check_marks(rem)


func _check_marks(rem: float) -> void:
	for m in [60, 30, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]:
		if rem <= float(m) and not _marks_fired.has(str(m)):
			_marks_fired[str(m)] = true
			record["marks"] = _marks_fired
			# Only the latest crossing speaks (a big time cost never plays a burst of ticks)
			if rem > float(m) - 1.0 or m == 0:
				timer_mark.emit(m)


# --- Server state tracking ------------------------------------------------------------------------

func _on_state(s: Dictionary) -> void:
	var key := "%s:%s" % [Net.room_code, Net.player_id]
	if key != _game_key and Net.room_code != "":
		_game_key = key
		_load()
	var pos := int(Net.me().get("pos", -1))
	if pos >= 0 and pos != _last_pos:
		if _last_pos >= 0 and not _visited.has(_last_pos):
			_visited.append(_last_pos)
		_last_pos = pos
	var c := current_client()
	var id := str(c.get("id", ""))
	if id != "":
		ensure_client(id, str(c.get("difficulty", "")))
	if str(s.get("phase", "")) == "ended":
		_queue_save()


func reset_for_tests() -> void:
	client_id = ""
	record = {}
	_records = {}
	_marks_fired = {}
	_visited = []
	_last_pos = -1
	holds = {}
	timed_page = false


func _queue_save() -> void:
	_save_timer = 0.5


func _save() -> void:
	if _game_key == "" or Engine.is_editor_hint():
		return
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	var data := all_records()
	cfg.set_value("games", _game_key.replace(":", "_"), {"records": data, "visited": _visited, "client": client_id})
	# Keep the file small: only the latest few games
	var keys := cfg.get_section_keys("games") if cfg.has_section("games") else PackedStringArray()
	if keys.size() > 6:
		for k in keys.slice(0, keys.size() - 6):
			cfg.erase_section_key("games", k)
	cfg.save(SAVE_PATH)


func _load() -> void:
	_records = {}
	record = {}
	client_id = ""
	_visited = []
	_marks_fired = {}
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var gk := _game_key.replace(":", "_")
	if not cfg.has_section_key("games", gk):
		return
	var saved: Variant = cfg.get_value("games", gk, {})
	if saved is Dictionary:
		_records = (saved as Dictionary).get("records", {})
		_visited = (saved as Dictionary).get("visited", [])
		var cid := str((saved as Dictionary).get("client", ""))
		if cid != "" and _records.has(cid):
			client_id = cid
			record = _records[cid]
			_marks_fired = record.get("marks", {})
