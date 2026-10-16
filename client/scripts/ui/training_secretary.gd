extends Control
## Optional docked guide; state identity prevents repeat narration on refresh.
signal dock_changed(height: float)
const PREFS := "user://training_secretary.cfg"
const FEMALE := preload("res://assets/startup/advisor_f.png")
const MALE := preload("res://assets/startup/advisor_m.png")
var configured := false
var enabled := false
var role := "female"
var _voice := ""
var _speech_unlocked := false
var _seen: Dictionary = {}
var _lines: Array = []
var _index := 0
var _subtitle: Label
var _heading: Label
var _portrait: TextureRect
var _panel: PanelContainer
var _replay: Button
var _next: Button
var _active_key := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cfg := ConfigFile.new()
	if cfg.load(PREFS) == OK:
		configured = bool(cfg.get_value("guide", "configured", false))
		enabled = bool(cfg.get_value("guide", "enabled", false))
		role = str(cfg.get_value("guide", "role", "female"))
	_panel = UI.panel(UI.PANEL, 12, 12)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_top = -176
	_panel.offset_bottom = -8
	_panel.offset_left = 8
	_panel.offset_right = -8
	add_child(_panel)
	var row := UI.hbox(12)
	_panel.add_child(row)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.custom_minimum_size = Vector2(76, 130)
	row.add_child(_portrait)
	var body := UI.vbox(4)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(body)
	_heading = UI.label("", 14, UI.GOLD)
	body.add_child(_heading)
	_subtitle = UI.label("", 16, UI.TEXT, true)
	_subtitle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_subtitle)
	var buttons := UI.hbox(8)
	body.add_child(buttons)
	_replay = UI.button("重播", _speak, 14, UI.PANEL_2)
	buttons.add_child(_replay)
	_next = UI.button("下一句", _advance, 14, UI.ACCENT)
	buttons.add_child(_next)
	buttons.add_child(UI.button("跳過", dismiss, 14, UI.PANEL_2))
	visible = false

func choose(use_guide: bool, selected_role: String) -> void:
	# Stop the previous narration before changing the playback permission.
	dismiss()
	configured = true
	enabled = use_guide
	role = selected_role if selected_role in ["female", "male"] else "female"
	_speech_unlocked = use_guide
	_seen.clear()
	var cfg := ConfigFile.new()
	cfg.set_value("guide", "configured", true)
	cfg.set_value("guide", "enabled", enabled)
	cfg.set_value("guide", "role", role)
	if cfg.save(PREFS) != OK:
		push_warning("無法保存秘書偏好，本次選擇仍有效。")
	_find_voice()

func unlock_speech() -> void:
	# Called by the explicit cover enter button, including returning users.
	_speech_unlocked = enabled
	_find_voice()

func _find_voice() -> void:
	_voice = ""
	if not enabled or DisplayServer.get_name() == "headless":
		return
	var voices := DisplayServer.tts_get_voices_for_language("zh")
	if not voices.is_empty():
		_voice = voices[0]

func dismiss() -> void:
	if _speech_unlocked and DisplayServer.get_name() != "headless":
		DisplayServer.tts_stop()
	visible = false
	dock_changed.emit(0.0)

func screen_changed(kind: String) -> void:
	dismiss()
	_active_key = ""
	if kind == "menu":
		show_lines("menu", ["歡迎來到法巴新人顧問培訓。從單人練習開始，探索客戶生活圈。", "完成任務後，可以到訓練紀錄回顧決策與回饋。"])
	elif kind == "report":
		show_lines("report", ["本次培訓已完成。看看能力表現與建議，再回顧自己的關鍵決策。"])

func observe(state: Dictionary) -> void:
	if not enabled or str(state.get("phase", "")) != "playing":
		return
	if not Net.is_my_turn():
		if _active_key != "":
			dismiss()
			_active_key = ""
		return
	var turn_key := "%s/%s/%s" % [state.get("round", 1), state.get("turn", 0), state.get("turnStage", "")]
	var sess: Variant = state.get("session")
	if sess is Dictionary:
		var step := str(sess.get("step", ""))
		var key := turn_key + "/" + str(sess.get("client", {}).get("id", "")) + "/" + step
		var messages := {
			"discover": ["先了解客戶的生活與需求。觀察線索，再提出合適的問題。", "別急著推薦商品，找出客戶真正擔心的風險。"],
			"plan": ["依照已發現的需求配置方案，兼顧保障缺口與客戶預算。"],
			"objection": ["先理解客戶的疑慮，再清楚說明方案的價值與限制。"],
			"result": ["檢視這次決策的結果與回饋，看看下一次可以如何改善。"]
		}
		if messages.has(step):
			show_lines(key, messages[step])
		elif key != _active_key:
			dismiss()
			_active_key = key
	elif str(state.get("turnStage", "")) == "roll":
		show_lines(turn_key, ["輪到你了！擲出骰子，前往城市中的下一個培訓任務。"])
	else:
		dismiss()
		_active_key = turn_key

func show_lines(key: String, lines: Array) -> void:
	if not enabled or key == _active_key:
		return
	dismiss()
	_active_key = key
	if _seen.has(key):
		return
	_seen[key] = true
	_lines = lines
	_index = 0
	_portrait.texture = FEMALE if role == "female" else MALE
	visible = true
	dock_changed.emit(176.0)
	_update_line()

func begin_training() -> void:
	_seen.clear()
	_active_key = ""
	dismiss()

func _update_line() -> void:
	_heading.text = ("女性" if role == "female" else "男性") + "培訓秘書 · %d/%d" % [_index + 1, _lines.size()]
	if _voice == "":
		_heading.text += " · 字幕導覽"
	_subtitle.text = str(_lines[_index])
	_next.text = "完成" if _index == _lines.size() - 1 else "下一句"
	_replay.disabled = _voice == ""
	_speak()

func _speak() -> void:
	if enabled and _speech_unlocked and _voice != "" and not _lines.is_empty():
		DisplayServer.tts_stop()
		DisplayServer.tts_speak(str(_lines[_index]), _voice, 80, 1.0, 0.95)

func _advance() -> void:
	_index += 1
	if _index >= _lines.size():
		dismiss()
	else:
		_update_line()

func _exit_tree() -> void:
	if _speech_unlocked and DisplayServer.get_name() != "headless":
		DisplayServer.tts_stop()

