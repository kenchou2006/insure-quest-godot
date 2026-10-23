extends Node
## TutorialManager (autoload): when the 培訓秘書 speaks on the mission pages, and what holds the clock.
## The secretary appears only when it helps: the first time a page is used, after a long idle
## stretch, at a major crisis, or when the player presses the 培訓秘書 button. Each appearance uses
## the one focus guide (secretary_focus.gd): 55% dim, the explained element kept bright, clock held,
## input blocked; 下一句 / 跳過本次引導 end it and every control comes back.
## Skipping only skips the explanation, never the task.

signal guide_closed(page_id: String, reason: String)

const SEEN_PATH := "user://quest_guides.cfg"
const IDLE_SECONDS := 45.0
## Most crisis lines one client hears (they must stay rare)
const CRISIS_MAX := 2

var _seen: Dictionary = {}
var _idle := 0.0
var _page := ""
var _idle_lines: Array = []
var _avoid_provider: Callable
var _nudged: Dictionary = {}
var _crisis_said: Dictionary = {}
var _crisis_count := 0
var _connected_focus: Object = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(SEEN_PATH) == OK:
		_seen = cfg.get_value("guides", "seen", {})
	if not Engine.is_editor_hint():
		TensionManager.message.connect(_on_tension_message)
		GameState.client_changed.connect(func(_id): _nudged.clear(); _crisis_said.clear(); _crisis_count = 0)


func _guide() -> Node:
	return GameState.secretary()


func _focus() -> Node:
	var g := _guide()
	if g == null:
		return null
	var f: Variant = g.get("_focus")
	return f if f is Node and is_instance_valid(f) else null


func secretary_on() -> bool:
	var g := _guide()
	return g != null and bool(g.get("enabled"))


func focus_active() -> bool:
	var f := _focus()
	return f != null and bool(f.get("guide_active"))


## True while anything tutorial-like is in front of the player (the clock stops)
func blocking() -> bool:
	if Tutorial.has_active():
		return true
	if focus_active():
		return true
	var g := _guide()
	if g != null and bool(g.get("_open")) and bool(g.get("_modal")):
		return true
	return MusicManager.ducked


## The page now on screen: its idle hint and the buttons the secretary must not cover
func set_page(page_id: String, idle_lines: Array = [], avoid_provider := Callable()) -> void:
	_page = page_id
	_idle = 0.0
	_idle_lines = idle_lines
	_avoid_provider = avoid_provider


func seen(page_id: String) -> bool:
	return bool(_seen.get(page_id, false))


func reset_seen() -> void:
	_seen = {}
	_save()


## First visit only: plays the page's guide and remembers it
## providers（可省略）：{"highlights": Callable, "avoid": Callable}，導覽開著時持續取得最新位置
func first_time(page_id: String, lines: Array, highlights: Array = [], avoid: Array = [], providers := {}) -> bool:
	if seen(page_id) or not secretary_on():
		return false
	if Tutorial.is_automation_mode():
		return false
	var ok := explain(page_id, lines, highlights, avoid, providers)
	if ok:
		_seen[page_id] = true
		_save()
	return ok


## Plays lines now (secretary button, idle nudge, crisis); false when no secretary or one is open
func explain(page_id: String, lines: Array, highlights: Array = [], avoid: Array = [], providers := {}) -> bool:
	var g := _guide()
	var f := _focus()
	if g == null or f == null or not secretary_on() or lines.is_empty():
		return false
	if bool(f.get("guide_active")):
		return false
	if g.has_method("dismiss") and bool(g.get("_open")):
		g.call("dismiss")
	if avoid.is_empty() and _avoid_provider.is_valid():
		avoid = _avoid_provider.call()
	var who := "女性培訓秘書 · Aly" if str(g.get("secretary_id")) != "kevin" else "男性培訓秘書 · Kevin"
	var tex: Texture2D = null
	var p: Variant = g.get("_portrait")
	if p is TextureRect:
		tex = (p as TextureRect).texture
	if _connected_focus != f:
		_connected_focus = f
		f.connect("finished", _on_focus_finished)
	_idle = 0.0
	var opts := {"highlights": highlights, "avoid": avoid}
	if providers.has("highlights"):
		opts["highlight_provider"] = providers.highlights
	if providers.has("avoid"):
		opts["avoid_provider"] = providers.avoid
	return bool(f.call("begin_secretary_focus", "quest_" + page_id, lines, str(g.call("selected_secretary")), tex, who, bool(g.get("voice_on")), opts))


func close() -> void:
	var f := _focus()
	if f != null and bool(f.get("guide_active")):
		f.call("end_secretary_focus", "page_change")


func _on_focus_finished(pid: String, reason: String) -> void:
	_idle = 0.0
	if pid.begins_with("quest_"):
		guide_closed.emit(pid.substr(6), reason)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventKey or event is InputEventScreenTouch:
		_idle = 0.0


func _process(delta: float) -> void:
	if not GameState.timed_page or blocking() or _page == "" or _idle_lines.is_empty():
		_idle = 0.0
		return
	_idle += delta
	if _idle >= IDLE_SECONDS:
		_idle = 0.0
		var key := GameState.client_id + ":" + _page
		if _nudged.has(key):
			return
		_nudged[key] = true
		explain(_page, _idle_lines)


func _on_tension_message(text: String, level: int) -> void:
	if level < 2 or not GameState.timed_page or not secretary_on():
		return
	if _crisis_said.has(text) or _crisis_count >= CRISIS_MAX:
		return
	var line := ""
	match text:
		"會談時間所剩不多":
			line = "會談時間只剩不到四分之一。先完成最關鍵的決定，細節可以下次會談再補。"
		"客戶信任過低":
			line = "客戶的信任正在流失。先回到他在意的事，確認感受，再談方案。"
		"目前方案超出客戶每月預算":
			line = "方案超出每月預算，客戶會直接拒絕。先保留核心保障，其他項目往後排。"
		"出現重大合規風險":
			line = "剛才的說法有合規風險。保證獲利、施壓成交都不行，換成說明風險與選擇。"
		"重大人生事件正在衝擊客戶":
			line = "客戶的生活出現重大變化。先確認影響，再決定要調整哪一部分方案。"
	if line == "":
		return
	_crisis_said[text] = true
	_crisis_count += 1
	# Next frame: the page that raised it finishes laying out first
	await get_tree().process_frame
	explain(_page if _page != "" else "crisis", [line])


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("guides", "seen", _seen)
	cfg.save(SEEN_PATH)
